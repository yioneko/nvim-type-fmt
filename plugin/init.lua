if vim.g.type_fmt_loaded then
	return
end

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		if args.data and args.data.client_id ~= nil then
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client.server_capabilities.documentOnTypeFormattingProvider ~= nil then
				require("type-fmt").attach_buf(args.buf, client)
				require("type-fmt").setup()
			end
		end
	end,
})

vim.g.type_fmt_loaded = true
