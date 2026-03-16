local events = require("cesp.events")
local utils = require("cesp.utils")

local M = {}

local CURSOR_GROUP =
	vim.api.nvim_create_augroup("RemoteCursor", { clear = true })
local NS_CURSOR = vim.api.nvim_create_namespace("cesp_cursors")
local NS_SELECT = vim.api.nvim_create_namespace("cesp_selection")

-- Track which buffer each remote client is currently in
M.remote_clients = {}

-- Clears all client extmarks from buffer
local function clear_client_from_buf(buf, extmark_id)
	if
		buf
		and vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_is_loaded(buf)
	then
		pcall(vim.api.nvim_buf_del_extmark, buf, NS_CURSOR, extmark_id)
		pcall(vim.api.nvim_buf_del_extmark, buf, NS_SELECT, extmark_id)
	end
end

-- Clears all extmarks
function M.clear_all_remote_cursors()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, NS_CURSOR, 0, -1)
			vim.api.nvim_buf_clear_namespace(buf, NS_SELECT, 0, -1)
		end
	end
	M.remote_clients = {}
end

function M.handle_cursor_leave(payload)
	local client_id = payload.from_id
	if not client_id or not M.remote_clients[client_id] then
		return
	end

	local extmark_id = client_id + 1
	clear_client_from_buf(M.remote_clients[client_id].buf, extmark_id)
	M.remote_clients[client_id] = nil
end

function M.start_cursor_tracker()
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
		group = CURSOR_GROUP,
		callback = function()
			local path = utils.get_rel_path(0)
			if not path or path == "" then
				return
			end

			local cursor_pos = vim.api.nvim_win_get_cursor(0)
			local payload = {
				event = "cursor_move",
				-- Make 0- indexed
				position = { cursor_pos[1] - 1, cursor_pos[2] },
				path = path,
			}

			-- On visual mode add hightlight start_pos to cursor_move
			-- Highlight will be drawn between this start_pos (start) and cursor_pos (end)
			local mode = vim.api.nvim_get_mode().mode
			if mode:match("[vV]") then
				local v_pos = vim.fn.getpos("v")
				payload.selection = {
					start_pos = { v_pos[2] - 1, v_pos[3] - 1 },
				}
			end

			events.send_event(payload)
		end,
	})
end

function M.handle_cursor_move(payload)
	local client_id = payload.from_id
	if not client_id or not payload.path then
		return
	end

	local extmark_id = client_id + 1
	local row, col = payload.position[1], payload.position[2]
	local name = payload.name or "???"
	local target_buf = utils.find_buffer_by_rel_path(payload.path)
	local config = require("cesp.config").config

	-- If client moved to a different buffer, clear them from the old one
	if
		M.remote_clients[client_id]
		and M.remote_clients[client_id].buf ~= target_buf
	then
		clear_client_from_buf(M.remote_clients[client_id].buf, extmark_id)
	end

	M.remote_clients[client_id] = { buf = target_buf, name = name }

	-- Only draw if the buffer is actually loaded here
	if
		not target_buf
		or not vim.api.nvim_buf_is_valid(target_buf)
		or not vim.api.nvim_buf_is_loaded(target_buf)
	then
		return
	end

	pcall(vim.api.nvim_buf_set_extmark, target_buf, NS_CURSOR, row, col, {
		id = extmark_id,
		hl_group = "TermCursor",
		virt_text = { { " " .. name, config.cursor.hl_group } },
		virt_text_pos = config.cursor.pos,
		end_row = row,
		end_col = col + 1,
		strict = false,
	})

	if payload.selection then
		local s_row, s_col =
			payload.selection.start_pos[1], payload.selection.start_pos[2]

		-- Extmarks require end to be larger
		local r1, c1, r2, c2 = row, col, s_row, s_col
		if r1 > r2 or (r1 == r2 and c1 > c2) then
			r1, c1, r2, c2 = r2, c2, r1, c1
		end

		pcall(vim.api.nvim_buf_set_extmark, target_buf, NS_SELECT, r1, c1, {
			id = extmark_id,
			hl_group = "Visual",
			end_row = r2,
			end_col = c2 + 1,
			strict = false,
		})
	else
		-- Clear selection if they aren't in visual mode anymore
		pcall(vim.api.nvim_buf_del_extmark, target_buf, NS_SELECT, extmark_id)
	end
end

return M
