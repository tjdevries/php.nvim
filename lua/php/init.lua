local M = {}

M.setup = function(opts)
  require "php.treesitter".setup(opts)
  require "php.lsp".setup(opts)
end

return M
