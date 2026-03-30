# latex-nav-core.nvim

Shared backend library for
[telescope-latex-labels.nvim](https://github.com/Chiarandini/telescope-latex-reference.nvim)
and
[telescope-cached-headings.nvim](https://github.com/Chiarandini/telescope-cached-headings.nvim).

Not intended for direct use — install it as a dependency of those plugins.

## What it provides

### `latex_nav_core.cache`

Parameterised cache-path computation and bulk-delete utilities shared by both
plugins. Both plugins delegate their `get_cache_path` and `wipe_all_caches`
calls here; the only difference is the subdirectory name and file extension
passed as arguments.

```lua
local core = require("latex_nav_core.cache")

-- get_cache_path(filepath, strategy, subdir, ext) -> string
local path = core.get_cache_path("/path/to/root.tex", "global", "cached_labels", ".labels")

-- wipe_all_caches(strategy, subdir, ext) -> count, err
local count, err = core.wipe_all_caches("global", "cached_labels", ".labels")
```

### `latex_nav_core.snacks`

Generic [Snacks.nvim](https://github.com/folke/snacks.nvim) picker launcher
used by both plugins to open their Snacks pickers without duplicating the
availability check or keymap wiring.

```lua
local core = require("latex_nav_core.snacks")

core.open({
  title         = "My Picker",
  items         = items,          -- must have .text, optionally .file and .pos
  format        = format_fn,      -- function(item, picker) -> { {text, hl}, ... }
  confirm       = confirm_fn,     -- function(picker, item)
  extra_actions = { copy = fn },  -- additional named actions
  extra_keys    = {               -- keymap bindings for extra_actions
    ["<C-y>"] = { "copy", mode = { "i", "n" } },
  },
})
```

## Installation

Add as a dependency alongside the plugins that require it:

**lazy.nvim**

```lua
{
  "Chiarandini/telescope-latex-labels.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "Chiarandini/latex-nav-core.nvim",
  },
}
```
