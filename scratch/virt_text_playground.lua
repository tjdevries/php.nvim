local a = vim.api

local bufnr = 192
local ns = a.nvim_create_namespace('artisan-virtext')

local title = "title"
local width = 40
local height = 15
local col = math.floor((vim.o.columns - width) / 2)
local row = math.floor((vim.o.lines - height) / 2)
local win = a.nvim_open_win(bufnr, true, {
  relative = "editor",
  style = "minimal",
  border = "single",
  title = title,
  width = width,
  height = height,
  row = row,
  col = col,
})

a.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

local arguments = { "name", "location" }
for line, value in ipairs(arguments) do
  a.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
    virt_text = { { string.format("%10s: ", value), "NonText" } },
    virt_text_pos = "inline",
  })
end
