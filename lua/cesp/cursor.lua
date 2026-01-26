local events = require("cesp.events")
local utils = require("cesp.utils")
local config = require("cesp.config").config

local M = {}

local cursor_au = vim.api.nvim_create_augroup("RemoteCursor", {
	clear = true,
})
local cursor_ns = vim.api.nvim_create_namespace("remote_cursors")

local RANGE_ID_OFFSET = 100000 -- Offset to keep selection ids unique from cursor ids

-- Goes trough every valid buffer and clears it's cursor namespace
function M.clear_all_remote_cursors()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, cursor_ns, 0, -1)
		end
	end
end

-- On "cursor_leave" event delete cursor based on "from_id"
-- Cursor extmarks are marked with client's id
function M.handle_cursor_leave(payload)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_del_extmark, buf, cursor_ns, payload.from_id)
			pcall(
				vim.api.nvim_buf_del_extmark,
				buf,
				cursor_ns,
				payload.from_id + RANGE_ID_OFFSET
			)
		end
	end
end

-- Create autocmds for cursor tracking
function M.start_cursor_tracker()
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
		group = cursor_au,
		callback = function()
			local path = utils.get_rel_path(0)
			if not path or path == "" then
				return
			end

			local mode = vim.api.nvim_get_mode().mode
			local payload = {
				event = "cursor_move",
				position = vim.api.nvim_win_get_cursor(0),
				path = path,
			}

			-- Check if in visual mode (v, V)
			if mode:match("[vV]") then
				local v_pos = vim.fn.getpos("v") -- [buf, row, col, off]
				payload.selection = {
					start_pos = { v_pos[2], v_pos[3] - 1 },
				}
			end

			events.send_event(payload)
		end,
	})
	-- On leave signal to other clients to delete this cursor
	vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
		group = cursor_au,
		callback = function()
			events.send_event({
				event = "cursor_leave",
			})
		end,
	})
end

function M.handle_cursor_move(payload)
	if not payload.from_id then
		return
	end

	local row = payload.position[1] - 1
	local col = payload.position[2]
	local name = payload.name or "???"
	local cursor_id = payload.from_id
	local selection_id = payload.from_id + RANGE_ID_OFFSET

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			-- Clear cursor and selection
			pcall(vim.api.nvim_buf_del_extmark, buf, cursor_ns, cursor_id)
			pcall(vim.api.nvim_buf_del_extmark, buf, cursor_ns, selection_id)
		end
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_buf_get_name(buf):find(payload.path, 1, true)
		then
			-- Draw the regular cursor
			local cursor_opts = {
				id = cursor_id,
				hl_group = "TermCursor",
				virt_text = { { " " .. name, config.cursor.hl_group } },
				virt_text_pos = config.cursor.pos,
				end_row = row,
				end_col = col + 1, -- Highlight exactly one character
				strict = false,
			}
			pcall(
				vim.api.nvim_buf_set_extmark,
				buf,
				cursor_ns,
				row,
				col,
				cursor_opts
			)

			-- If selection draw the range
			if payload.selection then
				local s_row = payload.selection.start_pos[1] - 1
				local s_col = payload.selection.start_pos[2]

				-- Normalize start/end for the extmark range logic
				local start_r, start_c, end_r, end_c
				if s_row < row or (s_row == row and s_col < col) then
					start_r, start_c = s_row, s_col
					end_r, end_c = row, col
				else
					start_r, start_c = row, col
					end_r, end_c = s_row, s_col
				end

				local selection_opts = {
					id = selection_id,
					hl_group = "Visual",
					end_row = end_r,
					end_col = end_c,
					strict = false,
				}
				pcall(
					vim.api.nvim_buf_set_extmark,
					buf,
					cursor_ns,
					start_r,
					start_c,
					selection_opts
				)
			end
			break
		end
	end
end

return M
