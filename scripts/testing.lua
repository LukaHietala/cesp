vim.api.nvim_buf_attach(0, false, {
	on_lines = function(_, _, _, first, old_last, new_last)
		local lines = vim.api.nvim_buf_get_lines(0, first, new_last, false)

		print("First: " .. tostring(first) .. " Old-last: " .. tostring(old_last) .. " new_last: " .. tostring(new_last) ..
			" Lines: " .. table.concat(lines, "\\n"))
	end
})
