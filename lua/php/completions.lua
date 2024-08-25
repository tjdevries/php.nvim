local M = {}

--- Complete a livewire component name
--- (requires ripgrep)
M.complete_livewire_components = function()
  local results = vim.system({ "rg", "--files", "resources/views/livewire/" }):wait()
  if results.code ~= 0 then
    return
  end

  local files = vim.split(results.stdout, "\n")
  local options = vim.tbl_map(function(file)
    local split = vim.split(file, "/")
    split[#split] = split[#split]:gsub(".blade.php", "")
    return table.concat(vim.list_slice(split, 4), ".")
  end, files)

  -- vim.print(options)
  vim.fn.complete(vim.fn.col ".", options)
end

return M
