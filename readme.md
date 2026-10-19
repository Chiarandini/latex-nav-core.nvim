# latex-nav-core.nvim

Shared backend library for the label and heading pickers:
[snacks-latex-labels.nvim](https://github.com/Chiarandini/snacks-latex-labels.nvim),
[snacks-cached-headings.nvim](https://github.com/Chiarandini/snacks-cached-headings.nvim),
[telescope-latex-references](https://github.com/Chiarandini/telescope-latex-references),
and
[telescope-cached-headings.nvim](https://github.com/Chiarandini/telescope-cached-headings.nvim).

Not intended for direct use; install it as a dependency of those plugins.

## What it provides

### `latex_nav_core.cached_headings`

Heading scanner and on-disk cache behind both heading pickers.

```lua
local headings = require("latex_nav_core.cached_headings")

local opts = {
  include_starred        = false,
  scan_includes          = false,  -- LaTeX only: follow \input, \include, \subfile
  recursive_limit        = 5,
  ignore_include_pattern = "",
  latex_headings         = { bonussection = 3, part = false },  -- merged over the built-ins
}

-- From the cache when it is fresh for `opts`; otherwise rescan and rewrite it.
-- `err` is set only when a rescan could not write the cache.
local entries, cache_path, meta, err = headings.load("/abs/main.tex", "tex", opts, "global")

-- Always rescan.
local entries, cache_path, meta, err = headings.refresh("/abs/main.tex", "tex", opts, "global")
```

Each entry is `{ text, title, line, level, kind, starred, source_file }`.
`kind` is the LaTeX command name, or `h<level>` for Markdown and Org.
`source_file` is relative to the root file's directory, `""` for the root.

The built-in LaTeX levels are `part` 1, `chapter` 2, `section` 3,
`subsection` 4, `subsubsection` 5. `latex_headings` maps a command name to
a level, or to `false` to drop a built-in. A heading's title is its first
mandatory argument; one optional `[...]` argument is skipped, nested and
escaped braces are kept, and a title that wraps onto the next line keeps its
first line.

A cache is stale when it was scanned with different `opts` (the signature
stored in its header differs) or when an included file's mtime changed.
Edits to the scanned file itself are not detected by `load`; call `refresh`
after them (the pickers do this on save with `auto_update`).
Lower-level pieces: `cached_headings.parser` (`scan_file`,
`resolve_latex_headings`, `signature`) and `cached_headings.cache`
(`get_cache_path`, `read_cache`, `write_cache`, `wipe_all_caches`).

### `latex_nav_core.cache`

Parameterized cache-path computation and bulk-delete utilities shared by the
label and heading caches. Each passes its own subdirectory name and file
extension.

```lua
local core = require("latex_nav_core.cache")

-- get_cache_path(filepath, strategy, subdir, ext) -> string
local path = core.get_cache_path("/path/to/root.tex", "global", "cached_labels", ".labels")

-- wipe_all_caches(strategy, subdir, ext) -> count, err
local count, err = core.wipe_all_caches("global", "cached_labels", ".labels")
```

### `latex_nav_core.snacks`

Generic [Snacks.nvim](https://github.com/folke/snacks.nvim) picker launcher
used by the Snacks pickers so they share the availability check and keymap
wiring.

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

-- Partially pre-filled: only missing prompts are shown
export_ui.open(entries, root_path, opts, {
  format   = "json",
  path     = ".",         -- directories and relative paths are resolved
  relative = false,
})

-- Fully pre-filled: no UI at all, runs immediately
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
  "Chiarandini/snacks-cached-headings.nvim",
  dependencies = {
    "folke/snacks.nvim",
    "Chiarandini/latex-nav-core.nvim",
  },
}
```
