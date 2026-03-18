local uv = vim.uv or vim.loop
local M = {}

-- Converts a project relative path to a absolute path
local function to_abs(path)
	return vim.fs.normalize(vim.fs.joinpath(M.get_project_root(), path))
end

-- Gets relative path against project root
local function to_rel(path)
	return vim.fs.relpath(M.get_project_root(), path)
end

-- Decodes json from a string
function M.decode_json(str)
	local ok, res = pcall(vim.json.decode, str)
	return ok and res or nil
end

-- Encodes table to json
function M.encode_json(ltable)
	local ok, res = pcall(vim.json.encode, ltable)
	return ok and res or nil
end

-- Gets project root by walking upwards until ".git" directory is found
-- or if one is not found it uses current working directory
function M.get_project_root()
	return vim.fs.root(0, { ".git" }) or uv.cwd()
end

-- Resolves buffer name (path) to root relative one
function M.get_rel_path(bufnr)
	-- TODO?, not sure if this works in every case, but sure seems like it
	local full_path = vim.api.nvim_buf_get_name(bufnr or 0)
	if full_path == "" then
		return nil
	end

	return to_rel(full_path)
end

-- Gets all files recursively from project root (max depth 100)
-- Ignores .git, node_modules, venv, build and .env
-- TODO: Custom rules
function M.get_files()
	local root = M.get_project_root()
	local files = {}
	local ignore_patterns =
		{ "%.git", "node_modules", "%.venv", "build", "%.env" }

	for name, type in vim.fs.dir(root, { depth = 100 }) do
		local is_ignored = vim.iter(ignore_patterns):any(function(p)
			return name:match(p)
		end)

		if not is_ignored and type == "file" then
			table.insert(files, name)
		end
	end
	return files
end

-- Reads file content
function M.read_file(path)
	local fd = uv.fs_open(path, "r", tonumber("644", 8))
	if not fd then
		return nil
	end

	local stat = uv.fs_fstat(fd)
	if not stat then
		uv.fs_close(fd)
		return nil
	end

	local ok, data = pcall(uv.fs_read, fd, stat.size, 0)
	uv.fs_close(fd)

	return ok and data or nil
end

-- Finds open buffer by project relative path
function M.find_buffer_by_rel_path(rel_path)
	return vim.iter(vim.api.nvim_list_bufs())
		:filter(vim.api.nvim_buf_is_valid)
		:find(function(buf)
			return M.get_rel_path(buf) == rel_path
		end)
end

-- Returns buffer or disk content of spesified path
-- First tries to get content from open buffer, if there
-- is no open buffer, then get latest content from disk
function M.get_file_content(path)
	local bufnr = M.find_buffer_by_rel_path(path)

	if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		return table.concat(lines, "\n")
	end

	return M.read_file(path)
end

-- Makes sure that wanted buffer exists, and if it doesn't
-- it creates new one
function M.ensure_host_buffer(rel_path)
	local bufnr = M.find_buffer_by_rel_path(rel_path)

	if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
		bufnr = vim.fn.bufadd(to_abs(rel_path))
		vim.bo[bufnr].buflisted = true

		-- Dirty local swap file suppression, shm-A
		vim.opt.shortmess:append("A")
		vim.fn.bufload(bufnr)
		vim.opt.shortmess:remove("A")
	end

	return bufnr
end

return M
