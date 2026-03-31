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

### `latex_nav_core.export`

Pure formatting functions that convert a list of label cache entries into
JSON, CSV, TSV, or plain pipe-separated text. No UI, no side effects (except
`write_export`). All formatters share the same options table:

```lua
local export = require("latex_nav_core.export")

local opts = {
  use_relative_paths = false,  -- true → paths relative to root's directory
  include_line       = true,
  include_title      = true,
  include_file       = true,
  exclude_files      = {},     -- Lua patterns matched against entry.filename
}

-- entries: list of { line, id, context, filename }
-- root_path: absolute path to the root .tex file
local json = export.format_json(entries, root_path, opts)
local csv  = export.format_csv(entries,  root_path, opts)
local tsv  = export.format_tsv(entries,  root_path, opts)
local txt  = export.format_txt(entries,  opts)       -- no root_path needed

local ok, err = export.write_export("/tmp/labels.json", json)

-- Helpers also available individually:
local prefix   = export.get_prefix("df:zeroSet")          -- "df"
local rel      = export.relative_path("/proj/ch1.tex", "/proj/main.tex")
local parsed   = export.parse_entry(entry, root_path, use_relative)
local filename = export.default_filename("json")           -- "project_labels.json"
```

### `latex_nav_core.export_ui`

Sequential `vim.ui` prompts that guide the user through format → output path
→ path style, then delegate to `latex_nav_core.export`. Every prompt is
skipped when the corresponding key is present in `pre_filled`.

```lua
local export_ui = require("latex_nav_core.export_ui")

-- All prompts shown (fully interactive)
export_ui.open(entries, root_path, opts)

-- Partially pre-filled — only missing prompts are shown
export_ui.open(entries, root_path, opts, {
  format   = "json",
  path     = ".",         -- directories and relative paths are resolved
  relative = false,
})

-- Fully pre-filled — no UI at all, runs immediately
export_ui.open(entries, root_path, opts, {
  format   = "csv",
  path     = "~/labels.csv",
  relative = false,
})
```

`opts` keys: `include_line`, `include_title`, `include_file`, `exclude_files`.
`pre_filled` keys: `format`, `path`, `relative`, `line`, `title`, `file`,
`exclude_files`. `pre_filled` values take priority over `opts`.

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
