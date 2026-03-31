local M = {}

local FORMAT_CHOICES = { "JSON", "CSV", "TSV", "Plain Text" }
local FORMAT_MAP = {
  ["JSON"]       = "json",
  ["CSV"]        = "csv",
  ["TSV"]        = "tsv",
  ["Plain Text"] = "txt",
}

---Open the label-export UI.
---
---Each of the three interactive prompts (format, path, path-style) is skipped
---when the corresponding key is present in `pre_filled`. If all three are
---provided the export runs immediately with no UI at all.
---
---Inclusion/exclusion overrides in `pre_filled` (line, title, file,
---exclude_files) always apply silently, replacing the values in `opts`.
---
---@param entries    table      List of { line, id, context, filename }
---@param root_path  string     Absolute path to the root .tex file.
---@param opts       table|nil  Config-level defaults:  {
---  include_line       = true,
---  include_title      = true,
---  include_file       = true,
---  exclude_files      = {},
---}
---@param pre_filled table|nil  Per-invocation overrides:  {
---  format        = "json"|"csv"|"tsv"|"txt",
---  path          = string,     -- already shell-expanded
---  relative      = boolean,
---  line          = boolean,    -- overrides opts.include_line
---  title         = boolean,    -- overrides opts.include_title
---  file          = boolean,    -- overrides opts.include_file
---  exclude_files = string[],   -- overrides opts.exclude_files
---}
M.open = function(entries, root_path, opts, pre_filled)
  opts      = opts      or {}
  pre_filled = pre_filled or {}

  local export = require("latex_nav_core.export")

  -- Resolve inclusion/exclusion opts, with pre_filled taking priority ----------
  local inc_line  = pre_filled.line  ~= nil and pre_filled.line  or (opts.include_line  ~= false)
  local inc_title = pre_filled.title ~= nil and pre_filled.title or (opts.include_title ~= false)
  local inc_file  = pre_filled.file  ~= nil and pre_filled.file  or (opts.include_file  ~= false)
  local exc_files = pre_filled.exclude_files or opts.exclude_files or {}

  -- ── Inner helpers (defined bottom-up so each can call the next) ───────────

  local function do_export(format, path, use_relative)
    local export_opts = {
      use_relative_paths = use_relative,
      include_line       = inc_line,
      include_title      = inc_title,
      include_file       = inc_file,
      exclude_files      = exc_files,
    }

    local content
    if format == "json" then
      content = export.format_json(entries, root_path, export_opts)
    elseif format == "csv" then
      content = export.format_csv(entries, root_path, export_opts)
    elseif format == "tsv" then
      content = export.format_tsv(entries, root_path, export_opts)
    else
      content = export.format_txt(entries, export_opts)
    end

    local ok, err = export.write_export(path, content)
    if ok then
      vim.notify(
        string.format("[latex_labels] Exported %d labels to %s", #entries, path),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        "[latex_labels] Export failed: " .. (err or "unknown error"),
        vim.log.levels.ERROR
      )
    end
  end

  -- Step 3: path style ────────────────────────────────────────────────────────
  local function step_3(format, path)
    if pre_filled.relative ~= nil then
      do_export(format, path, pre_filled.relative)
    else
      vim.ui.select({ "Absolute Paths", "Relative Paths" }, {
        prompt = "Path style:",
      }, function(path_style)
        if not path_style then return end
        do_export(format, path, path_style == "Relative Paths")
      end)
    end
  end

  -- Step 2: output path ───────────────────────────────────────────────────────
  local function step_2(format)
    if pre_filled.path then
      step_3(format, pre_filled.path)
    else
      local root_dir     = vim.fn.fnamemodify(root_path, ":h")
      local default_path = root_dir .. "/" .. export.default_filename(format)
      vim.ui.input({
        prompt  = "Export to: ",
        default = default_path,
      }, function(path)
        if not path or path == "" then return end
        step_3(format, vim.fn.expand(path))
      end)
    end
  end

  -- Step 1: format ────────────────────────────────────────────────────────────
  if pre_filled.format then
    step_2(pre_filled.format)
  else
    vim.ui.select(FORMAT_CHOICES, {
      prompt = "Export labels — choose format:",
    }, function(choice)
      if not choice then return end
      step_2(FORMAT_MAP[choice])
    end)
  end
end

return M
