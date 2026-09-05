local uv = vim.uv or vim.loop
local bit = require("bit")
local cursor = require("cesp.cursor")
local events = require("cesp.events")

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

			-- Parse big-endian payload length using black magic
			-- Neovim uses luaJIT 5.1 so no builtin string pack/unpack or bitwise :(
			local l1, l2, l3, l4 = string.byte(buffer, 3, 6)
			local payload_len = bit.bor(
				bit.lshift(l1, 24),
				bit.lshift(l2, 16),
				bit.lshift(l3, 8),
				l4
			)

			-- Make sure it's unsigned 32-bit integer
			payload_len = bit.tobit(payload_len) % 4294967296 -- 2^32

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
			e = "auth:handshake",
			p = {
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
		events.send_event({ event = "cursor:leave" })

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
