local bit = require("bit")
local browser = require("cesp.browser")
local buffer = require("cesp.buffer")
local utils = require("cesp.utils")

local M = {}
M.state = {}

function M.send_event(event_table)
	local network = require("cesp.network")

	if not network.handle or network.handle:is_closing() then
		print("Unable to send the event, maybe join?")
		return
	end

	local event_str = utils.encode_json(event_table)
	if event_str then
		local payload_len = #event_str

		-- Make payload len big endian uint32
		local l1 = bit.band(bit.rshift(payload_len, 24), 0xFF)
		local l2 = bit.band(bit.rshift(payload_len, 16), 0xFF)
		local l3 = bit.band(bit.rshift(payload_len, 8), 0xFF)
		local l4 = bit.band(payload_len, 0xFF)

		-- Magic bytes are C and E
		local header = string.char(0x0C, 0x0E, l1, l2, l3, l4)
		network.handle:write(header .. event_str)
	end
end

local events = {
	["auth:handshake_res"] = function(payload)
		if not payload.id or not payload.name then
			return
		end
		M.state = { id = payload.id, name = payload.name }
		print("Joined as " .. M.state.name)
	end,

	["fs:list_res"] = function(payload)
		vim.schedule(function()
			if payload.files and #payload.files > 0 then
				browser.open_file_browser(payload.files, function(path)
					M.send_event({ e = "doc:open", p = { path = path } })
				end)
			else
				print("No files received")
			end
		end)
	end,

	["doc:open_res"] = function(payload)
		if not payload.content then
			print("No content from " .. payload.path)
		end

		browser.open_remote_file(payload.path, payload.content, function(buf)
			buffer.attach_buf_listener(buf, function(p, c)
				M.send_event({ e = "doc:update", p = { path = p, changes = c } })
			end)
			vim.api.nvim_create_autocmd("BufWriteCmd", {
				buffer = buf,
				callback = function()
					M.send_event({ e = "doc:save", p = { path = payload.path } })
				end,
			})
		end)
	end,

	["doc:update"] = function(payload)
		vim.schedule(function()
			local bufnr = utils.find_buffer_by_name(payload.path)
			if utils.is_valid_buf(bufnr) then
				buffer.apply_change(bufnr, payload.changes)
			end
		end)
	end,

	["cursor:move"] = function(payload)
		local cursor = require("cesp.cursor")
		vim.schedule(function()
			cursor.handle_cursor_move(payload)
		end)
	end,

	["cursor:range"] = function(payload)
		local cursor = require("cesp.cursor")
		vim.schedule(function()
			cursor.handle_cursor_range(payload)
		end)
	end,

	["user:join"] = function(payload)
		if payload.name then
			print(payload.name .. " joined!")
		end
	end,

	["user:leave"] = function(payload)
		local cursor = require("cesp.cursor")
		if not payload.name then
			return
		end

		vim.schedule(function()
			cursor.handle_cursor_leave(payload)
		end)

		print(payload.name .. " left :(")
	end,

	["ping"] = function()
		M.send_event({ event = "pong" })
	end,

	["server:error"] = function(payload)
		if payload.message then
			print(payload.message)
		end
	end,
}

-- Handles every event received from server
function M.handle_event(json_str)
	local payload_json = utils.decode_json(json_str)

	if not payload_json or not payload_json.e or not payload_json.p then
		return
	end

	local handler = events[payload_json.e]

	if handler then
		handler(payload_json.p)
	else
		print("Not implemented :( " .. payload_json.e)
	end
end

return M
