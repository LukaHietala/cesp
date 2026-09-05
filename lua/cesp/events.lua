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

-- Handles every event received from server
function M.handle_event(json_str)
	local cursor = require("cesp.cursor")
	-- Get event details
	local payload_json = utils.decode_json(json_str)
	if not payload_json then
		return
	end

	local event = payload_json.e
	local payload = payload_json.p

	if not payload or not event then
		return
	end

	if event == "auth:handshake_res" then
		if payload.id == nil or payload.name == nil then
			return
		end

		M.state = {
			id = payload.id,
			name = payload.name,
		}

		print("Joined as " .. M.state.name)
		return
	end

	if event == "fs:list_res" then
		vim.schedule(function()
			if payload.files and #payload.files > 0 then
				-- If files in response open explorer with them
				browser.open_file_browser(payload.files, function(path)
					-- On select request for selected file
					M.send_event({
						e = "doc:open",
						p = {
							path = path,
						},
					})
				end)
			else
				print("No files received")
			end
		end)
		return
	end

	if event == "doc:open_res" then
		local content = payload.content
		local path = payload.path

		if not content then
			print("No content from " .. path)
		end

		-- Opens an empty buffer that mimics real file buffer
		browser.open_remote_file(path, content, function(buf)
			-- Attach listeners to it
			buffer.attach_buf_listener(buf, function(p, c)
				M.send_event({
					e = "doc:update",
					p = {
						path = p,
						changes = c,
					},
				})
			end)

			vim.api.nvim_create_autocmd("BufWriteCmd", {
				buffer = buf,
				callback = function()
					M.send_event({
						e = "doc:save",
						p = {
							path = path,
						},
					})
				end,
			})
		end)
		return
	end

	if event == "doc:update" then
		local path = payload.path
		local changes = payload.changes

		vim.schedule(function()
			local bufnr = utils.find_buffer_by_name(path)

			if
				bufnr
				and vim.api.nvim_buf_is_valid(bufnr)
				and vim.api.nvim_buf_is_loaded(bufnr)
			then
				buffer.apply_change(bufnr, changes)
			end
		end)
		return
	end

	if event == "cursor:move" then
		vim.schedule(function()
			cursor.handle_cursor_move(payload)
		end)
		return
	end

	if event == "cursor:leave" then
		vim.schedule(function()
			cursor.handle_cursor_leave(payload)
		end)
		return
	end

	if event == "user:join" then
		if not payload.name then
			return
		end

		print(payload.name .. " joined!")
		return
	end

	if event == "user:leave" then
		if not payload.name then
			return
		end

		print(payload.name .. " left :(")
		return
	end

	if event == "ping" then
		M.send_event({
			event = "pong",
		})
		return
	end

	if event == "server:error" then
		if not payload.message then
			return
		end

		print(payload.message)
		return
	end

	print("Not implemented :( " .. event)
end

return M
