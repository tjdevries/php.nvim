-- This file updates the tree-sitter-blade repo
-- then downloads the queries into the right location for neovim runtime
--
-- This makes it so that you don't have to do anything on your own to get
-- blade working for yourself, you just install this plugin and then call setup
-- and it will have everything there.
local revision = require "php.treesitter".revision
local repo = "https://github.com/EmranMR/tree-sitter-blade"


vim.fn.mkdir("build", "p")
vim.fn.mkdir("queries/blade/", "p")

if 0 == vim.fn.isdirectory("build/tree-sitter-blade") then
  local job = vim.system({ "git", "clone", repo, "build/tree-sitter-blade" }):wait()
  print("clone", vim.inspect(job))
end

local checkout = vim.system({ "git", "checkout", revision }, { cwd = "build/tree-sitter-blade" }):wait()
print("checkout", vim.inspect(checkout))

local queries_to_copy = { "folds", "highlights", "injections" }

for _, path in ipairs(queries_to_copy) do
  local theirs = vim.fs.joinpath("build", "tree-sitter-blade", "queries", path .. ".scm")
  local mine = vim.fs.joinpath("queries", "blade", path .. ".scm")
  print(theirs, "->", mine, vim.uv.fs_copyfile(theirs, mine))
end
