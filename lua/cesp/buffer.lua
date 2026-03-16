local M = {}

-- List of buffer that have nvim_buf listener
M.attached = {}
-- Apply locks
M.is_applying = {}

local utils = require("cesp.utils")

-- Applies a single change to a buffer
function M.apply_change(buf, change)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end

	M.is_applying[buf] = true
	local ok, err = pcall(
		vim.api.nvim_buf_set_lines,
		buf,
		change.first,
		change.old_last,
		false,
		change.lines
	)
	M.is_applying[buf] = false

	if not ok then
		print("Error applying change: " .. tostring(err))
	end
end

-- Listen for buffer line changes
function M.attach_buf_listener(buf, on_change)
	if M.attached[buf] then
		return
	end

	local path = utils.get_rel_path(buf)
	if not path then
		print("Buffer outside project root, not applying listener")
		return
	end

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, first, old_last, new_last)
			if M.is_applying[buf] then
				return
			end

			local lines =
				vim.api.nvim_buf_get_lines(buf, first, new_last, false)
			on_change(path, {
				-- First line number where change started
				first = first,
				-- Last line number where change ended
				old_last = old_last,
				-- Content in between
				lines = lines,
			})
		end,
		on_detach = function()
			M.attached[buf] = nil
		end,
	})
	M.attached[buf] = true
end

return M
