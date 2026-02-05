local utils = require("cesp.utils")

local M = {}

M.attached = {}
M.is_applying = false

-- Listen for buffer line changes
function M.attach_buf_listener(buf, on_change)
	-- Don't attach same buffer twice
	if M.attached[buf] then
		return
	end

	local path = utils.get_rel_path(buf)

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, first, old_last, new_last)
			if M.is_applying then
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
