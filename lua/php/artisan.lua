local a = vim.api
local ns = a.nvim_create_namespace('artisan-virtext')

local M = {}

local artisan = function(...)
  return vim.system({ "php", "artisan", ... }, { text = true }):wait()
end

local prompted = function(prompt)
  return function()
    local name = vim.fn.input(prompt)
    if not name or name == "" then
      vim.notify "#cancelled"
      return
    end
    local job = artisan("make:livewire", name)
    vim.notify(job.stdout)
  end
end

local actions = {
  -- ["serve"] = function() end,

  ["livewire make (make:livewire)"] = prompted "livewire component: ",
  ["migrate fresh (migrate:fresh)"] = function()
    local confirm = vim.fn.input "Are you sure? "
    if not confirm or confirm == "" then
      vim.notify "Did not reset database :)"
      return
    end

    vim.notify(artisan("migrate:fresh").stdout)
  end,

  ["migrate fresh --seed (migrate:fresh)"] = function()
    local confirm = vim.fn.input "Are you sure? "
    if not confirm or confirm == "" then
      vim.notify "Did not reset database :)"
      return
    end

    vim.notify(artisan("migrate:fresh", "--seed").stdout)
  end,
}

M.artisan = function()
  local keys = vim.tbl_keys(actions)
  table.sort(keys)

  vim.ui.select(keys, {
    prompt = "PHP",
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if not choice then
      return
    end

    local result = actions[choice]
    if result then
      pcall(result)
    else
      vim.notify "weird..."
    end
  end)
end

ARTISAN_CACHE = ARTISAN_CACHE or nil
local get_artisan_result = function(opts)
  opts = opts or {}

  if not ARTISAN_CACHE or opts.force then
    local artisan_result = vim.system({ "php", "artisan", "--format=json" }):wait()
    local ok, parsed = pcall(vim.json.decode, artisan_result.stdout)
    if not ok then
      vim.notify(string.format("[php.nvim] Failed to parse artisan:\n%s\n%s", parsed, vim.inspect(artisan_result)))
      return
    end

    ARTISAN_CACHE = parsed
  end

  return ARTISAN_CACHE
end

M.ui_select_artisan = function(opts)
  opts = opts or {}

  local result = get_artisan_result(opts)
  local commands = vim.tbl_filter(function(cmd) return not cmd.hidden end, result.commands)
  vim.ui.select(commands, {
    format_item = function(item)
      return string.format("%s [%s]", item.name, item.description)
    end
  }, function(item)
    -- vim.print(item)
  end)
end

local get_options = function(value)
  local options_to_skip = {
    ["--ansi"] = true,
    ["--no-ansi"] = true,
    ["--no-interaction"] = true,
    ["--verbose"] = true,
    ["--version"] = true,
    ["--help"] = true,
    ["--quiet"] = true,
    ["--env"] = true,
  }

  local options = vim.tbl_get(value, "definition", "options")
  if not options then
    return nil
  end

  options = vim.tbl_values(options)

  table.sort(options, function(a, b)
    return a.name < b.name
  end)

  return vim.tbl_filter(function(option)
    if options_to_skip[option.name] then
      return false
    end

    if option.default == vim.NIL then
      option.default = nil
    end

    if type(option.default) == "table" and vim.tbl_isempty(option.default) then
      option.default = nil
    end

    return true
  end, options)
end


local execute_artisan_command = function(value)
  local arguments = vim.tbl_values(vim.tbl_get(value, "definition", "arguments"))
  local options = get_options(value) or {}

  local bufnr = a.nvim_create_buf(false, true)

  -- TODO: Configurable
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.max(15, #arguments + #options)

  local title = value.name
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
  local append = function(text)
    if type(text) == "table" and vim.tbl_isempty(text) then
      text = ""
    end

    a.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(text, "\n"))
  end

  local longest_name = 10
  for _, val in pairs(arguments) do
    longest_name = math.max(#val.name, longest_name)
  end
  for _, val in pairs(options) do
    longest_name = math.max(#val.name, longest_name)
  end

  local add_extmark = function(line, required, text, docs)
    local hl = required and "Error" or "NonText"

    a.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      right_gravity = false,
      end_right_gravity = true,
      end_row = line,
      end_col = 0,
      virt_text = { { string.format("%" .. tostring(longest_name) .. "s: ", text), hl } },
      virt_text_pos = "inline",
    })

    if docs then
      if #docs > 50 then
        docs = string.sub(docs, 1, 50) .. "..."
      end

      a.nvim_buf_set_extmark(bufnr, ns, line, 0, {
        right_gravity = false,
        end_right_gravity = true,
        end_row = line,
        end_col = 0,
        virt_text = { { docs, "NonText" } },
        virt_text_pos = "right_align",
      })
    end
  end

  local line = 0
  for _, argument in ipairs(arguments) do
    add_extmark(line, argument.is_required, argument.name, argument.description)
    line = line + 1

    append("")
  end

  for _, option in ipairs(options) do
    if option.default ~= nil then
      a.nvim_buf_set_lines(bufnr, line, line + 1, false, { tostring(option.default) })
    end

    add_extmark(line, false, option.name, option.description)
    line = line + 1

    append("")
  end

  vim.cmd.startinsert()

  vim.keymap.set({ "i", "n" }, "<tab>", function()
    local cursor = a.nvim_win_get_cursor(win)
    local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
    if line == "false" then
      vim.api.nvim_buf_set_text(bufnr, cursor[1] - 1, 0, cursor[1] - 1, -1, { "true" })
    elseif line == "true" then
      vim.api.nvim_buf_set_text(bufnr, cursor[1] - 1, 0, cursor[1] - 1, -1, { "false" })
    end
  end, { buffer = bufnr })

  local close = function()
    if a.nvim_win_is_valid(win) then
      a.nvim_win_close(win, true)
    end

    if a.nvim_buf_is_valid(bufnr) then
      a.nvim_buf_delete(bufnr, { force = true })
    end
  end

  local execute = function()
    vim.cmd.stopinsert()

    local lines = vim.tbl_map(vim.trim, a.nvim_buf_get_lines(bufnr, 0, #arguments + #options, false))
    local argument_lines = vim.list_slice(lines, 1, #arguments)
    local option_lines = vim.list_slice(lines, #arguments + 1)

    local command = { "php", "artisan", value.name }
    for _, argument in ipairs(argument_lines) do
      table.insert(command, argument)
    end

    local add_option = function(idx, option_value)
      if option_value == "" then
        return
      end

      if option_value == "false" then
        return
      end

      if option_value == "true" then
        local option = assert(options[idx], "option")
        table.insert(command, option.name)
      else
        local option = assert(options[idx], "option")
        table.insert(command, string.format("%s=%s", option.name, option_value))
      end
    end

    for idx, option_value in ipairs(option_lines) do
      add_option(idx, option_value)
    end

    print("Command to execute: ", table.concat(command, " "))
    close()

    vim.cmd.split()
    vim.cmd.term(table.concat(command, " "))
  end

  local move = function(direction)
    return function()
      local cursor = a.nvim_win_get_cursor(win)
      cursor[1] = cursor[1] + direction
      cursor[2] = 0

      if cursor[1] == line + 1 then
        return execute()
      end

      a.nvim_win_set_cursor(win, cursor)
    end
  end

  vim.keymap.set({ "i", "n" }, "<CR>", move(1), { buffer = bufnr })
  vim.keymap.set({ "i", "n" }, "<S-CR>", move(-1), { buffer = bufnr })
  vim.keymap.set({ "i", "n" }, "<C-CR>", execute, { buffer = bufnr })
  vim.keymap.set({ "i", "n" }, "<C-C>", close, { buffer = bufnr })
end

M.telescope_select_artisan = function(opts)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local conf = require("telescope.config").values
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local entry_display = require "telescope.pickers.entry_display"
  local previewers = require "telescope.previewers"

  opts = opts or {}

  local result = get_artisan_result(opts)
  local commands = vim.tbl_filter(function(cmd) return not cmd.hidden end, result.commands)

  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 30 },
      { remaining = true },
    },
  }

  local make_display = function(entry)
    return displayer {
      entry.value.name,
      { entry.value.description, "NonText" },
    }
  end

  pickers
      .new(opts, {
        prompt_title = "PHP Artisan",
        finder = finders.new_table({
          results = commands,
          entry_maker = function(item)
            return {
              value = item,
              display = make_display,
              ordinal = item.name .. item.description,
            }
          end
        }),
        previewer = previewers.new {
          preview_fn = function(_, entry, status)
            if not status.preview_win then
              return
            end

            local bufnr = a.nvim_win_get_buf(status.preview_win)
            local append = function(text)
              a.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(text, "\n"))
            end

            vim.bo[bufnr].filetype = 'markdown'

            local value = entry.value
            a.nvim_buf_set_lines(bufnr, 0, -1, false, { "# " .. value.name })
            append("")
            append("`" .. table.concat(value.usage, "\n") .. "`")
            append("")
            append(value.description)
            append('')
            -- append(vim.inspect(value))

            local arguments = vim.tbl_get(value, "definition", "arguments")
            if arguments and not vim.tbl_isempty(arguments) then
              append("## Arguments")
              for _, argument in pairs(arguments) do
                append(string.format("[%s] %s", argument.name, argument.description))
              end
              append("")
            end

            local options = get_options(value)
            if options and not vim.tbl_isempty(options) then
              append("## Options")
              for _, option in ipairs(options) do
                append(string.format("[%s] %s", option.name, option.description))
              end
              append("")
            end
          end,
        },
        sorter = conf.file_sorter(opts),
        attach_mappings = function()
          -- TODO: Add better execution, probably put it somewhere not just in a temp command thing
          -- TODO: Add options and option selecting
          actions.select_default:replace(function(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)

            vim.schedule(function()
              -- local input = vim.fn.input({
              --   prompt = "command to execute > ",
              --   default = "php artisan " .. selection.value.name .. " "
              -- })
              --
              -- vim.cmd.split()
              -- vim.cmd.term(input)

              execute_artisan_command(selection.value)
            end)
          end)
          return true
        end,
      }):find()
end

return M
