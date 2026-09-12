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

-- Converts number to uint32 (bigendian)
function M.to_bigendian_uint32(n)
	local l1 = bit.band(bit.rshift(n, 24), 0xFF)
	local l2 = bit.band(bit.rshift(n, 16), 0xFF)
	local l3 = bit.band(bit.rshift(n, 8), 0xFF)
	local l4 = bit.band(n, 0xFF)

	return l1, l2, l3, l4
end

-- Converts bigendian uint32 to number
function M.parse_bigendian_uint32(s, i, j)
	local l1, l2, l3, l4 = string.byte(s, i, j)
	return bit.tobit(
		bit.bor(bit.lshift(l1, 24), bit.lshift(l2, 16), bit.lshift(l3, 8), l4)
	) % 4294967296 -- 2^32
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
