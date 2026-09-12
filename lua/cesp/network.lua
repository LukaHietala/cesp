local uv = vim.uv or vim.loop
local cursor = require("cesp.cursor")
local events = require("cesp.events")
local utils = require("cesp.utils")

local M = {}
M.handle = nil

local function on_read()
	local buffer = ""

	return function(err, chunk)
		if err or not chunk then
			vim.schedule(cursor.clear_all_remote_cursors)
			if M.handle and not M.handle:is_closing() then
				M.handle:close()
			end
			return
		end

		buffer = buffer .. chunk

		while true do
			-- Header should have 6 bytes
			if #buffer < 6 then
				break
			end

			-- Magic bytes are C and E
			local m1, m2 = string.byte(buffer, 1, 2)
			if m1 ~= 0x0C or m2 ~= 0x0E then
				vim.schedule(function()
					print("Invalid magic bytes received, disconnecting")
				end)
				if M.handle and not M.handle:is_closing() then
					M.handle:close()
				end
				return
			end

			local payload_len = utils.parse_bigendian_uint32(buffer, 3, 6)
			-- Make sure everything made it
			if #buffer < 6 + payload_len then
				break
			end

			-- Take the json
			local payload = string.sub(buffer, 7, 6 + payload_len)

			-- Clean the buffer
			buffer = string.sub(buffer, 7 + payload_len)

			if payload ~= "" then
				vim.schedule(function()
					events.handle_event(payload)
				end)
			end
		end
	end
end

function M.start_client(ip)
	if M.handle then
		if not M.handle:is_closing() then
			print("Already connected, try again")
			return
		else
			M.handle = nil
		end
	end

	M.handle = uv.new_tcp()
	local config = require("cesp.config").config

	M.handle:connect(ip, config.port, function(err)
		if err then
			print(err)
			M.handle = nil
			return
		end

		events.send_event({
			event = "auth:handshake",
			payload = {
				name = config.name,
			},
		})

		vim.schedule(function()
			cursor.start_cursor_tracker()
		end)

		M.handle:read_start(on_read())
	end)
end

function M.stop()
	if M.handle then
		if not M.handle:is_closing() then
			M.handle:close()
		end
		M.handle = nil
	end

	vim.schedule(function()
		cursor.clear_all_remote_cursors()
	end)

	print("Closed connection")
end

return M
