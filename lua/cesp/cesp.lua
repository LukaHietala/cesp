local uv = vim.uv or vim.loop

local M = {}

-- Current libuv uv_tcp_t handle
M.handle = nil

local function decode_json(str)
	local ok, res = pcall(vim.json.decode, str)
	return ok and res or nil
end

local function encode_json(json)
	local ok, res = pcall(vim.json.encode, json)
	return ok and res or nil
end

-- Returns list of files relative to root_path. Uses depth-first search
function list_files(root_path)
	root_path = root_path or "."
	local files = {}
	local ignore_patterns =
		{ "%.git", "node_modules", "%.venv", "build", "%.env" }

	local stack = { root_path }

	local function is_ignored(path)
		for _, pattern in ipairs(ignore_patterns) do
			if path:match(pattern) then
				return true
			end
		end
		return false
	end

	while #stack > 0 do
		local current_dir = table.remove(stack)
		local scanner = uv.fs_scandir(current_dir)

		if scanner then
			for name, type in
				function()
					return uv.fs_scandir_next(scanner)
				end
			do
				-- Construct clean path
				local rel_path = current_dir == "." and name
					or (current_dir .. "/" .. name)

				if not is_ignored(rel_path) then
					if type == "directory" then
						table.insert(stack, rel_path)
					elseif type == "file" or type == "link" then
						table.insert(files, rel_path)
					end
				end
			end
		end
	end

	return files
end

local function send_event(event_table)
	if not M.handle or M.handle:is_closing() then
		print("Unable to send the event")
		return
	end

	local event_str = encode_json(event_table)
	if event_str then
		M.handle:write(event_str .. "\n")
	end
end

local function handle_event(json_str)
	local payload = decode_json(json_str)
	if not payload or not payload.event then
		return
	end

	if payload.event == "request_files" then
		local file_list = list_files(".")

		send_event({
			event = "response_files",
			files = file_list,
			request_id = payload.request_id,
		})
		return
	end

	if payload.event == "response_files" then
	end

	print("Not implemented " .. payload.event)
end

local function start_client()
	M.handle = uv.new_tcp()
	local chunks = {}

	M.handle:connect("127.0.0.1", 8080, function(err)
		if err then
			return print(err)
		end

		-- Handshake
		local handshake_event = {
			event = "handshake",
			name = "lentava_pomeranian",
		}
		send_event(handshake_event)

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

start_client()
