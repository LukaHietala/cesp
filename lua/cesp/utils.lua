local M = {}

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

-- Checks if buf is valid and loaded
function M.is_valid_buf(buf)
	return buf
		and vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_is_loaded(buf)
end

-- Gets path of buf that maps to server buf, "path/file.hs"
function M.get_buf_path(bufnr)
	local full_path = vim.api.nvim_buf_get_name(bufnr or 0)
	if full_path == "" then
		return nil
	end

	-- Vim tries to forcefully resolve it to local path so this prevents it
	local path = vim.fn.fnamemodify(full_path, ":.")

	return path
end

-- Finds buffer name by name/path on server
function M.find_buffer_by_name(name)
	-- DELICIOUS iterators
	return vim.iter(vim.api.nvim_list_bufs())
		:filter(vim.api.nvim_buf_is_valid)
		:find(function(buf)
			return M.get_buf_path(buf) == name
		end)
end

return M
