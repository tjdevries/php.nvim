local parsers = require("nvim-treesitter.parsers")
parsers = parsers.get_parser_configs and parsers.get_parser_configs() or parsers

local M = {}

M.revision = "47baa7ba1f9d5f436c7a72b052d2dac2166abf92"

M.add_parser = function()
	---@diagnostic disable-next-line: inject-field
	parsers.blade = {
		tier = "community",
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
	-- vim.cmd.TSInstall("blade")
end

return M
