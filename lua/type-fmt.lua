local M = {}

local notify = vim.schedule_wrap(vim.notify)

local group = vim.api.nvim_create_augroup("lsp_on_type_formatting", { clear = true })
local otf_buf_track = {}

local ON_TYPE_FORMATTING = "textDocument/onTypeFormatting"

local conf = {
	buf_filter = function(bufnr)
		return true
	end,
	prefer_client = function(client_a, client_b)
		return client_a or client_b
	end,
}

local function get_buf_version(bufnr)
	-- This is private ?
	return vim.lsp.util.buf_versions[bufnr]
end

local function is_support_on_type_fmt(client)
	return client.server_capabilities.documentOnTypeFormattingProvider ~= nil
end

local function get_otf_client(bufnr)
	local result
	for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
		if is_support_on_type_fmt(client) then
			if result then
				result = conf.prefer_client(result, client)
			else
				result = client
			end
		end
	end
	return result
end

function M.attach_buf(bufnr, client)
	otf_buf_track[bufnr] = otf_buf_track[bufnr] or {}
	if otf_buf_track[bufnr].client then
		otf_buf_track[bufnr].client = conf.prefer_client(client, otf_buf_track[bufnr].client)
	else
		otf_buf_track[bufnr].client = client
	end
end

function M.reset_buf(bufnr)
	if otf_buf_track[bufnr] then
		if otf_buf_track[bufnr].cancel then
			otf_buf_track[bufnr].cancel()
		end
		otf_buf_track[bufnr] = nil
	end
end

function M.handler(err, result, ctx, config)
	local client = vim.lsp.get_client_by_id(ctx.client_id)

	if err then
		return notify(err, vim.log.levels.WARN)
	end

	local prev_buf_version = ctx.params.textDocument.version
	if
		not client
		or not conf.buf_filter(ctx.bufnr)
		or not vim.api.nvim_buf_is_valid(ctx.bufnr)
		or (prev_buf_version ~= nil and get_buf_version(ctx.bufnr) ~= prev_buf_version)
	then
		return
	end

	if result and type(result) == "table" then
		vim.lsp.util.apply_text_edits(result, ctx.bufnr, client.offset_encoding)
	end
end

function M.request(winnr, key)
	winnr = winnr or vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winnr)

	local client = otf_buf_track[bufnr].client
	if not client or client.is_stopped() then
		return
	end

	-- vim reports "\r" as enter key, but lsp use "\n" as new line character instead
	if key == "\r" then
		key = "\n"
	end

	local provider = client.server_capabilities.documentOnTypeFormattingProvider
	if
		not (
			provider.firstTriggerCharacter == key
			or (provider.moreTriggerCharacter and vim.tbl_contains(provider.moreTriggerCharacter, key))
		)
	then
		return
	end

	local params = vim.lsp.util.make_position_params(winnr, client.offset_encoding)
	-- attach document version for compare in handler
	params.textDocument.version = get_buf_version(bufnr)

	local success, rq_id = client.request(
		ON_TYPE_FORMATTING,
		vim.tbl_extend("force", params, {
			ch = key,
			options = {
				tabSize = vim.lsp.util.get_effective_tabstop(bufnr),
				insertSpaces = vim.bo[bufnr].expandtab,
			},
		}),
		function(err, result, ctx, config)
			-- reset cancellation
			if otf_buf_track[ctx.bufnr] then
				otf_buf_track[ctx.bufnr].cancel = nil
			end
			local handler = client.handlers[ON_TYPE_FORMATTING] or vim.lsp.handlers[ON_TYPE_FORMATTING] or M.handler
			handler(err, result, ctx, config)
		end,
		bufnr
	)

	if success then
		otf_buf_track[bufnr].cancel = function()
			client.cancel_request(rq_id)
			otf_buf_track[bufnr].cancel = nil
		end
	end
end

local enabled = false

local listened = false

local function listen()
	if listened then
		return
	end

	local function listen_fn(key)
		local mode = vim.api.nvim_get_mode().mode
		if mode ~= "i" then
			return
		end
		local bufnr = vim.api.nvim_get_current_buf()
		if not otf_buf_track[bufnr] then
			return
		end

		if otf_buf_track[bufnr].cancel then
			otf_buf_track[bufnr].cancel()
		end

		local winnr = vim.api.nvim_get_current_win()
		-- schedule to wait key inserted
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(winnr) and conf.buf_filter(bufnr) then
				M.request(winnr, key)
			end
		end)
	end

	-- currently we do not have a reliable way to remove the listener
	-- so we must ensure this will not throw and forbid double listening
	vim.on_key(function(key)
		local success, err = pcall(listen_fn, key)
		if not success then
			-- disable at error
			M.disable()
			notify(tostring(err), vim.log.levels.ERROR)
		end
	end)

	listened = true
end

function M.enable()
	if enabled then
		return
	end
	enabled = true

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			if not conf.buf_filter(args.buf) then
				return
			end
			local client = get_otf_client(args.buf)
			if client then
				M.attach_buf(args.buf, client)
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(args)
			local client = get_otf_client(args.buf)
			-- no client available
			if not client then
				M.reset_buf(args.buf)
			end
		end,
	})

	-- otherwise there will be potential memory leak
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			M.reset_buf(args.buf)
		end,
	})

	listen()
end

function M.disable()
	enabled = false
	vim.api.nvim_clear_autocmds({ group = group })
	for k, _ in pairs(otf_buf_track) do
		M.reset_buf(k)
	end
end

function M.setup(o)
	o = o or {}
	if o.buf_filter then
		conf.buf_filter = o.buf_filter
	end
	if o.prefer_client then
		conf.prefer_client = o.prefer_client
	end

	M.enable()
end

-- set handler if possible
if not vim.lsp.handlers[ON_TYPE_FORMATTING] then
	vim.lsp.handlers[ON_TYPE_FORMATTING] = M.handler
end

return M
