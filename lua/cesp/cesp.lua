local uv = vim.uv or vim.loop

local function start_client()
	-- Create scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.cmd("vsplit | b" .. buf)

	local client = uv.new_tcp()
	local chunks = {}

	client:connect("127.0.0.1", 8080, function(err)
		if err then
			return print(err)
		end

		-- Handshake
		client:write('{"event": "handshake", "name": "lentava_pomeranian"}\n')

		client:read_start(function(err, chunk)
			if err or not chunk then
				return client:close()
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

				-- Update scratch buf
				if #lines > 0 then
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(buf) then
							vim.api.nvim_buf_set_lines(
								buf,
								-1,
								-1,
								false,
								lines
							)
						end
					end)
				end
			end
		end)
	end)
end

start_client()
