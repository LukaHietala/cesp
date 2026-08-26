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

function M.get_buf_path(bufnr)
	local full_path = vim.api.nvim_buf_get_name(bufnr or 0)
	if full_path == "" then
		return nil
	end

	-- Vim tries to forcefully resolve it to local path so this prevents it
	local path = vim.fn.fnamemodify(full_path, ":.")

	return path
end

function M.find_buffer_by_name(name)
	return vim.iter(vim.api.nvim_list_bufs())
		:filter(vim.api.nvim_buf_is_valid)
		:find(function(buf)
			return M.get_buf_path(buf) == name
		end)
end

return M
