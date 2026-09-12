local config = require("cesp.config")
local events = require("cesp.events")
local utils = require("cesp.utils")

local M = {}

local cursor_group = vim.api.nvim_create_augroup("CespCursor", { clear = true })
-- Regular cursors
local ns_cursor = vim.api.nvim_create_namespace("cesp_cursors")
-- Cursors with selected range
local ns_select = vim.api.nvim_create_namespace("cesp_selection")

M.clients = {}
local following = ""

local function clear_client_from_buf(buf, extmark_id)
	if utils.is_valid_buf(buf) then
		pcall(vim.api.nvim_buf_del_extmark, buf, ns_cursor, extmark_id)
		pcall(vim.api.nvim_buf_del_extmark, buf, ns_select, extmark_id)
	end
end

-- Finds client's extmark_id
local function get_client(client_id, target_buf, name)
	local extmark_id = client_id + 1
	local client = M.clients[client_id]

	if client and client.buf ~= target_buf then
		clear_client_from_buf(client.buf, extmark_id)
	end

	M.clients[client_id] = { buf = target_buf, name = name }
	return extmark_id
end

local function draw_cursor(buf, extmark_id, row, col, name)
	local cfg = config.config.cursor
	pcall(vim.api.nvim_buf_set_extmark, buf, ns_cursor, row, col, {
		id = extmark_id,
		hl_group = "TermCursor",
		virt_text = { { " " .. name, cfg.hl_group } },
		virt_text_pos = cfg.pos,
		end_row = row,
		end_col = col + 1,
		strict = false,
	})
end

local function handle_following(name, path, target_buf, row, col)
	if following ~= name or not row or not col then
		return
	end

	if utils.is_valid_buf(target_buf) then
		vim.api.nvim_set_current_buf(target_buf)
	else
		events.send_event({ event = "doc:open", payload = { path = path } })
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
	vim.cmd.normal({ bang = true, "zz" })
end

function M.clear_all_remote_cursors()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		-- Buf doesn't have to be loaded
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, ns_cursor, 0, -1)
			vim.api.nvim_buf_clear_namespace(buf, ns_select, 0, -1)
		end
	end
	M.clients = {}
end

function M.handle_cursor_leave(payload)
	local client = M.clients[payload.id]
	if client then
		clear_client_from_buf(client.buf, payload.id + 1)
		M.clients[payload.id] = nil
	end
end

function M.start_cursor_tracker()
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
		group = cursor_group,
		callback = function()
			local path = utils.get_buf_path(0)
			if not path or path == "" then
				return
			end

			local cursor = vim.api.nvim_win_get_cursor(0)
			local row, col = cursor[1] - 1, cursor[2]

			if vim.api.nvim_get_mode().mode:match("[vV\22]") then
				local v_pos = vim.fn.getpos("v")
				events.send_event({
					event = "cursor:range",
					payload = {
						path = path,
						range = { v_pos[2] - 1, v_pos[3] - 1, row, col },
					},
				})
			else
				events.send_event({
					event = "cursor:move",
					payload = { path = path, pos = { row, col } },
				})
			end
		end,
	})
end

function M.handle_cursor_move(payload)
	if not payload.id or not payload.path or not payload.pos then
		return
	end

	local name = payload.name or "???"
	local target_buf = utils.find_buffer_by_name(payload.path)
	local row, col = payload.pos[1], payload.pos[2]
	local extmark_id = get_client(payload.id, target_buf, name)

	handle_following(name, payload.path, target_buf, row, col)

	if not utils.is_valid_buf(target_buf) then
		return
	end

	draw_cursor(target_buf, extmark_id, row, col, name)
	pcall(vim.api.nvim_buf_del_extmark, target_buf, ns_select, extmark_id)
end

function M.handle_cursor_range(payload)
	if not payload.id or not payload.path or not payload.range then
		return
	end

	local name = payload.name or "???"
	local target_buf = utils.find_buffer_by_name(payload.path)
	local extmark_id = get_client(payload.id, target_buf, name)

	if not utils.is_valid_buf(target_buf) then
		return
	end

	local r1, c1, r2, c2 = unpack(payload.range)
	draw_cursor(target_buf, extmark_id, r2, c2, name)

	-- Order correctly for selection highlight
	if r1 > r2 or (r1 == r2 and c1 > c2) then
		r1, c1, r2, c2 = r2, c2, r1, c1
	end

	pcall(vim.api.nvim_buf_set_extmark, target_buf, ns_select, r1, c1, {
		id = extmark_id,
		hl_group = "Visual",
		end_row = r2,
		end_col = c2 + 1,
		strict = false,
	})
end

function M.follow(name)
	following = name
	print("Following " .. name)
end

return M
