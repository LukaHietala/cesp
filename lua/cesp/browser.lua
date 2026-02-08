local M = {}

-- Sends request for host's filetree
function M.list_remote_files()
	local events = require("cesp.events")
	events.send_event({
		event = "request_files",
	})
end

-- Basic file picker. TODO: Add telescope picker that will be shown instead if
-- Telescope has been installed
function M.open_file_browser(files, on_select)
	vim.ui.input(
		{ prompt = "Filter files (leave empty for all): " },
		function(input)
			-- Escape
			if input == nil then
				return
			end

			-- Filter results
			local filtered = files
			if input ~= "" then
				filtered = vim.tbl_filter(function(file)
					-- Simple case-insensitive match
					return file:lower():find(input:lower(), 1, true) ~= nil
				end, files)
			end

			if #filtered == 0 then
				print("No matches found")
				return
			end

			-- Show the filtered list using builtin vim.ui.select (sanoinkuvaamattoman asiallista)
			-- If user has telescope-ui-select plugin or some other picker that takes this it will be used :D
			vim.ui.select(filtered, {
				prompt = "Select remote file:",
				kind = "file",
			}, function(choice)
				if choice then
					on_select(choice)
				end
			end)
		end
	)
end

function M.open_remote_file(path, content, on_complete)
	local utils = require("cesp.utils")

	vim.schedule(function()
		local target_rel_path = path

		-- Search for existing buffers
		local buf = utils.find_buffer_by_rel_path(path)

		-- If not found, create one
		if not buf then
			buf = vim.api.nvim_create_buf(true, true)
			pcall(vim.api.nvim_buf_set_name, buf, target_rel_path)

			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].swapfile = false
			vim.bo[buf].bufhidden = "hide"

			local ft = vim.filetype.match({ filename = target_rel_path })
			if ft then
				vim.bo[buf].filetype = ft
			end

			-- TODO: Try to forcibly attach lsp to the buffer
		end

		local lines = vim.split(content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_current_buf(buf)

		if on_complete then
			on_complete(buf)
		end
	end)
end

return M
