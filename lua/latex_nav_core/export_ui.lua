local M = {}

local FORMAT_CHOICES = { "JSON", "CSV", "TSV", "Plain Text" }
local FORMAT_MAP = {
  ["JSON"]       = "json",
  ["CSV"]        = "csv",
  ["TSV"]        = "tsv",
  ["Plain Text"] = "txt",
}

---Open the interactive label-export UI.
---
---Walks the user through three sequential prompts using native Neovim APIs:
---  1. Format selection  (vim.ui.select)
---  2. Output path       (vim.ui.input, pre-filled with a sensible default)
---  3. Path style        (vim.ui.select: absolute vs. relative)
---
---After confirmation the file is written and the result is reported via vim.notify.
---The user can cancel at any step by pressing <Esc> or leaving the input empty.
---
---@param entries   table   List of { line, id, context, filename }
---@param root_path string  Absolute path to the root .tex file.
---@param opts      table|nil  {
---  include_line       = true,   -- include line numbers in exported records
---  include_title      = true,   -- include label titles / context strings
---  include_file       = true,   -- include file paths in exported records
---  exclude_files      = {},     -- Lua patterns matched against entry.filename
---}
M.open = function(entries, root_path, opts)
  opts = opts or {}
  local export = require("latex_nav_core.export")

  -- Step 1: Format ─────────────────────────────────────────────────────────
  vim.ui.select(FORMAT_CHOICES, {
    prompt = "Export labels — choose format:",
  }, function(choice)
    if not choice then return end
    local format = FORMAT_MAP[choice]

    -- Step 2: Output path ──────────────────────────────────────────────────
    local root_dir     = vim.fn.fnamemodify(root_path, ":h")
    local default_path = root_dir .. "/" .. export.default_filename(format)

    vim.ui.input({
      prompt  = "Export to: ",
      default = default_path,
    }, function(path)
      if not path or path == "" then return end
      path = vim.fn.expand(path)  -- expand ~ and environment variables

      -- Step 3: Path style ─────────────────────────────────────────────────
      vim.ui.select({ "Absolute Paths", "Relative Paths" }, {
        prompt = "Path style:",
      }, function(path_style)
        if not path_style then return end
        local use_relative = (path_style == "Relative Paths")

        local export_opts = {
          use_relative_paths = use_relative,
          include_line       = opts.include_line  ~= false,
          include_title      = opts.include_title ~= false,
          include_file       = opts.include_file  ~= false,
          exclude_files      = opts.exclude_files or {},
        }

        -- Format content ───────────────────────────────────────────────────
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

        -- Write and notify ─────────────────────────────────────────────────
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
      end)
    end)
  end)
end

return M
