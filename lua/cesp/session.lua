local uv = vim.uv or vim.loop
local browser = require("cesp.browser")
local utils = require("cesp.utils")

local M = {}

M.config = {
	port = 8080,
}
-- Current libuv uv_tcp_t handle
M.handle = nil

local function send_event(event_table)
	if not M.handle or M.handle:is_closing() then
		print("Unable to send the event")
		return
	end

	local event_str = utils.encode_json(event_table)
	if event_str then
		M.handle:write(event_str .. "\n")
	end
end

local function handle_event(json_str)
	local payload = utils.decode_json(json_str)
	if not payload or not payload.event then
		return
	end

	if payload.event == "request_files" then
		local file_list = utils.get_files(".")

		send_event({
			event = "response_files",
			files = file_list,
			request_id = payload.request_id,
		})
		return
	end

	if payload.event == "response_files" then
		vim.schedule(function()
			if payload.files and #payload.files > 0 then
				browser.open_file_browser(payload.files)
			else
				print("No files received")
			end
		end)
		return
	end

	print("Not implemented " .. payload.event)
end

function M.list_remote_files()
	send_event({
		event = "request_files",
	})
end

function M.start_client(ip)
	M.handle = uv.new_tcp()
	local chunks = {}

	M.handle:connect(ip, 8080, function(err)
		if err then
			return print(err)
		end

		send_event({
			event = "handshake",
			name = "lentava_pomeranian",
		})

		M.handle:read_start(function(err, chunk)
			if err or not chunk then
				return M.handle:close()
			end

			table.insert(chunks, chunk)

			-- Only process if we see a newline (the end of at least one message)
			if chunk:find("\n") then
				local raw_data = table.concat(chunks)
				chunks = {}

				-- Split data into lines
				local lines = vim.split(raw_data, "\n", { plain = true })

				-- Handle Fragmentation
				local leftover = table.remove(lines)
				if leftover ~= "" then
					table.insert(chunks, leftover)
				end

				-- Handle events
				for _, line in ipairs(lines) do
					if line ~= "" then
						vim.schedule(function()
							handle_event(line)
						end)
					end
				end
			end
		end)
	end)
end

function M.stop()
	if M.handle then
		M.handle:close()
	end
end

return M
