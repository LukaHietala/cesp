local M = {}

function M.list_remote_files()
	local events = require("cesp.events")
	events.send_event({
		e = "fs:list",
	})
end

function M.open_file_browser(files, on_select)
	if #files == 0 then
		print("No remote files found")
		return
	end

	vim.ui.select(files, {
		prompt = "Select remote file:",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice then
			on_select(choice)
		end
	end)
end

function M.open_remote_file(name, content, on_complete)
	local utils = require("cesp.utils")

	vim.schedule(function()
		local buf = utils.find_buffer_by_name(name)

		if not buf then
			buf = vim.api.nvim_create_buf(true, true)
			pcall(vim.api.nvim_buf_set_name, buf, name)

			vim.bo[buf].buftype = "acwrite"
			vim.bo[buf].swapfile = false
			vim.bo[buf].bufhidden = "hide"

			local ft = vim.filetype.match({ filename = name })
			if ft then
				vim.bo[buf].filetype = ft
			end

			vim.api.nvim_create_autocmd("BufWriteCmd", {
				buffer = buf,
				callback = function()
					vim.bo[buf].modified = false
				end,
			})
		end

		local lines = vim.split(content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modified = false
		vim.api.nvim_set_current_buf(buf)

		if on_complete then
			on_complete(buf)
		end
	end)
end

return M
