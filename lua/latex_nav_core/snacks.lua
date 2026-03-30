local M = {}

--- Open a Snacks picker from a pre-computed item list.
---
--- Each item in `opts.items` must have at minimum a `text` field (used for
--- fuzzy filtering). Items that also carry `file` and `pos = {line, col}`
--- fields will be previewed automatically by Snacks.
---
---@param opts table {
---   title:         string
---   items:         table    list of Snacks items
---   format:        function function(item, picker) -> { {text, hl_group}, ... }
---   confirm:       function function(picker, item)
---   extra_actions: table|nil  map of action_name -> function(picker, item)
---   extra_keys:    table|nil  map of key -> { action_name, mode = {...} }
--- }
M.open = function(opts)
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    vim.notify(
      "[latex_nav_core] snacks.nvim is not available. Install folke/snacks.nvim.",
      vim.log.levels.ERROR
    )
    return
  end

  local actions = { confirm = opts.confirm }
  if opts.extra_actions then
    for name, fn in pairs(opts.extra_actions) do
      actions[name] = fn
    end
  end

  local keys = {}
  if opts.extra_keys then
    for key, binding in pairs(opts.extra_keys) do
      keys[key] = binding
    end
  end

  Snacks.picker({
    title   = opts.title,
    items   = opts.items,
    format  = opts.format,
    actions = actions,
    win     = {
      input = { keys = keys },
    },
  })
end

return M
