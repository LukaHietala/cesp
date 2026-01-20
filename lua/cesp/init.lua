local session = require("cesp.session")
local M = {}

function M.setup(opts)
	session.config = vim.tbl_deep_extend("force", session.config, opts or {})

	vim.api.nvim_create_user_command("CespJoin", function(args)
		local ip = args.args ~= "" and args.args or "127.0.0.1"
		session.start_client(ip)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("CespExplore", function()
		session.list_remote_files()
	end, {})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			session.stop()
		end,
	})
end

return M
