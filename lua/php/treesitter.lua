local parsers = require('nvim-treesitter.parsers')
local parser_configs = parsers.get_parser_configs()

local M = {}

M.revision = "01e5550cb60ef3532ace0c6df0480f6f406113ff"

M.add_parser = function()
  ---@diagnostic disable-next-line: inject-field
  parser_configs.blade = {
    install_info = {
      url = "https://github.com/EmranMR/tree-sitter-blade",
      files = { "src/parser.c" },
      branch = "main",
      revision = M.revision,
    },
    filetype = "blade",
  }
end

M.setup = function()
  M.add_parser()

  -- TODO: This seems like a bad plan...?
  if not parsers.has_parser('blade') then
    vim.cmd.TSInstall('blade')
  end
end

return M
