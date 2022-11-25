# nvim-type-fmt

LSP handler of `textDocument/onTypeFormatting` for nvim.

https://user-images.githubusercontent.com/65551246/203911852-4d8cc381-7768-4ef1-bd89-6e233dc25b35.mp4

Powered by [on-typing-assists of rust-analyzer](https://rust-analyzer.github.io/manual.html#on-typing-assists).

## Usage

Just install it by any plugin manager, and the plugin will automatically setup the handler for it. The plugin is lazy loaded by default, usually you do not need to add any other lazy loading logic by plugin manger.

```vim
lua<< EOF
-- packer.nvim
use({ "yioneko/nvim-type-fmt" })

EOF

" vim-plug
Plug "yioneko/nvim-type-fmt"
```

To disable auto setup of the plugin, put this before the loading of plugins:

```vim
g:type_fmt_loaded = v:true

lua<< EOF
-- or in lua
vim.g.type_fmt_loaded = true

EOF
```

## Config

The configuration is optional.

```lua
require("nvim-type-fmt").setup({
    -- In case if you only want to enable this for limited buffers
    -- We already filter it by checking capabilities of attached lsp client
    buf_filter = function(bufnr)
        return true
    end,
    -- If multiple clients are capable of onTypeFormatting, we use this to determine which will win
    -- This is a rare situation but we still provide it for the correctness of lsp client handling
    prefer_client = function(client_a, client_b)
        return client_a or client_b
    end,
})
```
