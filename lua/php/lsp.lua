local lspconfig = require 'lspconfig'
local configs = require 'lspconfig.configs'

local M = {}

local find_rust_bin = function()
  return "/home/tjdevries/plugins/php.nvim/lsp/target/debug/php-nvim-lsp"
end


M.start = function()
  vim.lsp.start({
    name = 'php-nvim-lsp',
    cmd = { find_rust_bin() },
    root_dir = vim.fs.dirname(vim.fs.find({ 'composer.json', }, { upward = true })[1]),
  })
end

local enable_php_nvim_lsp = false

local group = vim.api.nvim_create_namespace("php-nvim-lsp")
M.setup = function(opts)
  opts = opts or {}

  if enable_php_nvim_lsp then
    -- TODO: Probably need to pass an attach function here, or instruct people
    -- to use LspAttach method, which also works fine :)
    vim.api.nvim_clear_autocmds({ group = group })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = { "blade", "php" },
      callback = M.start,
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      group = group,
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= "php-nvim-lsp" then
          return
        end

        require "tj.lsp".on_attach(client)
      end,
    })
  end

  -- Enable laravel dev tools, if found in runtime
  if 1 == vim.fn.executable("laravel-dev-tools") then
    configs.blade = {
      default_config = {
        -- Path to the executable: laravel-dev-tools
        cmd = { "laravel-dev-tools", "lsp" },
        filetypes = { 'blade' },
        root_dir = function(fname)
          return lspconfig.util.find_git_ancestor(fname)
        end,
        settings = {},
      },
    }

    -- Set it up
    lspconfig.blade.setup(opts.lsp)
  end
end


return M
