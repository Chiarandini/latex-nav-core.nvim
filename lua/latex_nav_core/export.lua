local M = {}

-- ── JSON helpers ──────────────────────────────────────────────────────────────

---Escape a value for use as a JSON string literal (including surrounding quotes).
---@param s any  Coerced to string.
---@return string
local function json_str(s)
  s = tostring(s or "")
  return '"'
    .. s:gsub('\\', '\\\\')
       :gsub('"',  '\\"')
       :gsub('\n', '\\n')
       :gsub('\r', '\\r')
       :gsub('\t', '\\t')
    .. '"'
end

-- ── CSV/TSV helpers ───────────────────────────────────────────────────────────

---Escape a value for a CSV field per RFC 4180.
---Wraps the field in double-quotes when it contains commas, quotes, or newlines.
---@param s any
---@return string
local function csv_field(s)
  s = tostring(s or "")
  if s:find('[,"\n\r]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

---Sanitise a value for a TSV field (tabs and newlines become spaces).
---gsub returns (string, count); we discard the count to avoid leaking it
---into callers that spread varargs (e.g. table.insert).
---@param s any
---@return string
local function tsv_field(s)
  local result = tostring(s or ""):gsub("[\t\n\r]", " ")
  return result
end

-- ── Entry filtering ───────────────────────────────────────────────────────────

---Remove entries whose `filename` matches any pattern in `exclude_files`.
---@param entries      table   List of { line, id, context, filename }
---@param exclude_files table  List of Lua patterns matched against entry.filename.
---@return table
local function apply_exclusions(entries, exclude_files)
  if not exclude_files or #exclude_files == 0 then return entries end
  local result = {}
  for _, e in ipairs(entries) do
    local skip = false
    for _, pat in ipairs(exclude_files) do
      if e.filename:match(pat) then skip = true; break end
    end
    if not skip then table.insert(result, e) end
  end
  return result
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Extract the label prefix (the part before the first colon).
---Returns an empty string when the id contains no colon.
---  "sec:foo"  →  "sec"
---  "label"    →  ""
---@param id string
---@return string
M.get_prefix = function(id)
  return id:match("^([^:]+):") or ""
end

---Return `file_path` relative to the directory that contains `root_path`.
---Falls back to the original absolute path when the file is not under that directory.
---@param file_path string  Absolute path to a .tex file.
---@param root_path string  Absolute path to the root .tex file.
---@return string
M.relative_path = function(file_path, root_path)
  local root_dir = vim.fn.fnamemodify(root_path, ":h")
  local prefix   = root_dir .. "/"
  if vim.startswith(file_path, prefix) then
    return file_path:sub(#prefix + 1)
  end
  return file_path
end

---Convert a raw cache entry into an enhanced export structure.
---@param entry        table   { line, id, context, filename }
---@param root_path    string  Absolute path to the root .tex file.
---@param use_relative boolean When true, `file` is relative to root's directory.
---@return table  { id, prefix, title, file, line }
M.parse_entry = function(entry, root_path, use_relative)
  return {
    id     = entry.id,
    prefix = M.get_prefix(entry.id),
    title  = entry.context,
    file   = use_relative
               and M.relative_path(entry.filename, root_path)
               or  entry.filename,
    line   = entry.line,
  }
end

---Return the default export filename for a given format key.
---@param format string  "json" | "csv" | "tsv" | "txt"
---@return string
M.default_filename = function(format)
  local ext = ({ json = ".json", csv = ".csv", tsv = ".tsv", txt = ".txt" })[format]
  return "project_labels" .. (ext or ".txt")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Formatters
--
-- All accept:
--   entries   table   List of { line, id, context, filename }
--   root_path string  Absolute path to the root .tex file (for metadata/paths)
--   opts      table   {
--     use_relative_paths = false,  -- false → absolute, true → relative to root dir
--     include_line       = true,
--     include_title      = true,
--     include_file       = true,
--     exclude_files      = {},     -- Lua patterns matched against entry.filename
--   }
-- ─────────────────────────────────────────────────────────────────────────────

---Format entries as a pretty-printed JSON document.
---Field order in each label object: id, type, [title], [file], [line]
---@param entries   table
---@param root_path string
---@param opts      table|nil
---@return string
M.format_json = function(entries, root_path, opts)
  opts = opts or {}
  local use_relative = opts.use_relative_paths or false
  local inc_line     = opts.include_line  ~= false
  local inc_title    = opts.include_title ~= false
  local inc_file     = opts.include_file  ~= false

  local filtered    = apply_exclusions(entries, opts.exclude_files)
  local root_dir    = vim.fn.fnamemodify(root_path, ":h")
  local export_date = os.date("!%Y-%m-%dT%H:%M:%SZ")

  -- Build one indented JSON object per label, preserving field order
  local label_parts = {}
  for i, e in ipairs(filtered) do
    local p       = M.parse_entry(e, root_path, use_relative)
    local is_last = (i == #filtered)

    local fields = {}
    table.insert(fields, '      "id": '   .. json_str(p.id))
    table.insert(fields, '      "type": ' .. json_str(p.prefix))
    if inc_title then
      table.insert(fields, '      "title": ' .. json_str(p.title))
    end
    if inc_file then
      table.insert(fields, '      "file": ' .. json_str(p.file))
    end
    if inc_line then
      table.insert(fields, '      "line": ' .. p.line)
    end

    local comma = is_last and "" or ","
    table.insert(label_parts,
      "    {\n"
      .. table.concat(fields, ",\n")
      .. "\n    }" .. comma
    )
  end

  local labels_section
  if #label_parts == 0 then
    labels_section = '  "labels": []'
  else
    labels_section = '  "labels": [\n'
      .. table.concat(label_parts, "\n")
      .. "\n  ]"
  end

  return table.concat({
    "{",
    '  "project_root": ' .. json_str(root_dir) .. ",",
    '  "export_date": '  .. json_str(export_date) .. ",",
    labels_section,
    "}",
  }, "\n")
end

---Format entries as CSV (RFC 4180 with header row).
---Columns: Label ID, Type, [Title], [File], [Line]
---@param entries   table
---@param root_path string
---@param opts      table|nil
---@return string
M.format_csv = function(entries, root_path, opts)
  opts = opts or {}
  local use_relative = opts.use_relative_paths or false
  local inc_line     = opts.include_line  ~= false
  local inc_title    = opts.include_title ~= false
  local inc_file     = opts.include_file  ~= false

  local filtered = apply_exclusions(entries, opts.exclude_files)

  local header = { "Label ID", "Type" }
  if inc_title then table.insert(header, "Title") end
  if inc_file  then table.insert(header, "File")  end
  if inc_line  then table.insert(header, "Line")  end

  local rows = { table.concat(header, ",") }

  for _, e in ipairs(filtered) do
    local p    = M.parse_entry(e, root_path, use_relative)
    local cols = { csv_field(p.id), csv_field(p.prefix) }
    if inc_title then table.insert(cols, csv_field(p.title))    end
    if inc_file  then table.insert(cols, csv_field(p.file))     end
    if inc_line  then table.insert(cols, tostring(p.line))      end
    table.insert(rows, table.concat(cols, ","))
  end

  return table.concat(rows, "\n")
end

---Format entries as TSV (tab-separated with header row).
---Columns: Label ID, Type, [Title], [File], [Line]
---@param entries   table
---@param root_path string
---@param opts      table|nil
---@return string
M.format_tsv = function(entries, root_path, opts)
  opts = opts or {}
  local use_relative = opts.use_relative_paths or false
  local inc_line     = opts.include_line  ~= false
  local inc_title    = opts.include_title ~= false
  local inc_file     = opts.include_file  ~= false

  local filtered = apply_exclusions(entries, opts.exclude_files)

  local header = { "Label ID", "Type" }
  if inc_title then table.insert(header, "Title") end
  if inc_file  then table.insert(header, "File")  end
  if inc_line  then table.insert(header, "Line")  end

  local rows = { table.concat(header, "\t") }

  for _, e in ipairs(filtered) do
    local p    = M.parse_entry(e, root_path, use_relative)
    local cols = { tsv_field(p.id), tsv_field(p.prefix) }
    if inc_title then table.insert(cols, tsv_field(p.title))    end
    if inc_file  then table.insert(cols, tsv_field(p.file))     end
    if inc_line  then table.insert(cols, tostring(p.line))      end
    table.insert(rows, table.concat(cols, "\t"))
  end

  return table.concat(rows, "\n")
end

---Format entries as plain pipe-separated text (mirrors the internal cache format).
---Only `exclude_files` from opts is honoured; field-inclusion flags are ignored
---because the pipe format has a fixed four-column schema.
---@param entries table
---@param opts    table|nil
---@return string
M.format_txt = function(entries, opts)
  opts = opts or {}
  local filtered = apply_exclusions(entries, opts.exclude_files)

  local rows = {}
  for _, e in ipairs(filtered) do
    table.insert(rows, string.format("%d|%s|%s|%s", e.line, e.id, e.context, e.filename))
  end
  return table.concat(rows, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────

---Write `content` to `output_path`.
---Returns false with an error message when the parent directory does not exist
---or the file cannot be opened for writing.
---@param output_path string
---@param content     string
---@return boolean  success
---@return string?  error_message
M.write_export = function(output_path, content)
  local dir = vim.fn.fnamemodify(output_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    return false, "Directory does not exist: " .. dir
  end
  local file = io.open(output_path, "w")
  if not file then
    return false, "Cannot write to: " .. output_path
  end
  file:write(content)
  file:close()
  return true, nil
end

return M
