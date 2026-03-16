local uv = vim.uv or vim.loop
local cursor = require("cesp.cursor")
local events = require("cesp.events")

local M = {}
M.handle = nil

local function on_read()
	local chunks = {}

	return function(err, chunk)
		if err or not chunk then
			vim.schedule(cursor.clear_all_remote_cursors)
			return M.handle:close()
		end

		table.insert(chunks, chunk)

		if chunk:find("\n") then
			local raw_data = table.concat(chunks)
			chunks = {}

			local lines = vim.split(raw_data, "\n", { plain = true })

			local leftover = table.remove(lines)
			if leftover ~= "" then
				table.insert(chunks, leftover)
			end

			for _, line in ipairs(lines) do
				if line ~= "" then
					vim.schedule(function()
						events.handle_event(line)
					end)
				end
			end
		end
	end
end

function M.start_client(ip, is_host)
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
			event = "handshake",
			name = config.name,
			host = is_host,
		})

		vim.schedule(function()
			cursor.start_cursor_tracker()
			local buffer = require("cesp.buffer")

			-- Attach listener to already open buffers
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if
					vim.api.nvim_buf_is_loaded(buf)
					and vim.api.nvim_buf_get_name(buf) ~= ""
				then
					buffer.attach_buf_listener(buf, function(path, changes)
						events.send_event({
							event = "update_content",
							path = path,
							changes = changes,
						})
					end)
				end
			end

			-- Share buf on open for future buffers
			vim.api.nvim_create_autocmd("BufReadPost", {
				callback = function(e)
					buffer.attach_buf_listener(e.buf, function(path, changes)
						events.send_event({
							event = "update_content",
							path = path,
							changes = changes,
						})
					end)
				end,
			})
		end)

		M.handle:read_start(on_read())
	end)
end

function M.stop()
	if M.handle then
		events.send_event({ event = "cursor_leave" })

		if not M.handle:is_closing() then
			M.handle:close()
		end
		M.handle = nil
	end

	vim.schedule(function()
		cursor.clear_all_remote_cursors()
		events.state.is_host = false
		events.state.client_id = nil
	end)

	print("Closed connection")
end

return M
