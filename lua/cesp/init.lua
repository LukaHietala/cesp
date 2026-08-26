local browser = require("cesp.browser")
local network = require("cesp.network")

local M = {}

function M.setup(opts)
	local config_mod = require("cesp.config")
	config_mod.config =
		vim.tbl_deep_extend("force", config_mod.config, opts or {})

	vim.api.nvim_create_user_command("CespJoin", function(args)
		local ip = args.args ~= "" and args.args or "127.0.0.1"
		network.start_client(ip)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("CespLeave", function()
		if network.handle == nil then
			print("Not connected")
			return
		end

		network.stop()
	end, {})

	vim.api.nvim_create_user_command("CespExplore", function()
		browser.list_remote_files()
	end, {})

	vim.api.nvim_create_user_command("CespFollow", function(args)
		local cursor = require("cesp.cursor")
		local name = args.args
		if name == "" then
			print("Provide a name")
			return
		end
		cursor.follow(name)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("CespUnfollow", function()
		local cursor = require("cesp.cursor")
		cursor.follow("")
	end, {})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			network.stop()
		end,
	})
end

return M
