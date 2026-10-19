local M = {}

---@class LatexNavCore.Heading
---@field text        string   Trimmed source line; smart jump matches on it.
---@field title       string
---@field line        integer
---@field level       integer  Depth in the outline; 1 is outermost.
---@field kind        string   LaTeX command name, or "h<level>" for markdown and org.
---@field starred     boolean
---@field source_file string   Path relative to the root file's directory; "" for the root file.

---@class LatexNavCore.HeadingsScanOpts
---@field include_starred?        boolean
---@field scan_includes?          boolean  LaTeX only: follow \input, \include, \subfile.
---@field recursive_limit?        integer
---@field ignore_include_pattern? string   Lua pattern; matching include arguments are skipped.
---@field latex_headings?         table<string, integer|false>  Merged over the built-ins.

local DEFAULT_LATEX_HEADINGS = {
  part          = 1,
  chapter       = 2,
  section       = 3,
  subsection    = 4,
  subsubsection = 5,
}

-- Lua patterns have no alternation, so we keep three separate patterns.
local INCLUDE_PATTERNS = {
  "^%s*\\input%s*{(.-)}",
  "^%s*\\include%s*{(.-)}",
  "^%s*\\subfile%s*{(.-)}",
}

---Merge `overrides` over the built-in LaTeX headings. A `false` value
---removes the command.
---@param overrides table<string, integer|false>|nil
---@return table<string, integer>
M.resolve_latex_headings = function(overrides)
  local resolved = {}
  for name, level in pairs(vim.tbl_extend("force", DEFAULT_LATEX_HEADINGS, overrides or {})) do
    if level then resolved[name] = level end
  end
  return resolved
end

---Canonical string of every option that changes what a scan returns. The
---cache stores it and treats a mismatch as stale.
---@param opts LatexNavCore.HeadingsScanOpts|nil
---@return string
M.signature = function(opts)
  opts = opts or {}
  local headings = {}
  for name, level in pairs(M.resolve_latex_headings(opts.latex_headings)) do
    table.insert(headings, name .. ":" .. level)
  end
  table.sort(headings)
  return string.format("starred=%d;includes=%d;limit=%d;ignore=%s;tex=%s",
    opts.include_starred and 1 or 0,
    opts.scan_includes and 1 or 0,
    opts.recursive_limit or 5,
    opts.ignore_include_pattern or "",
    table.concat(headings, ","))
end

---Split a LaTeX command line into name, star, and the first mandatory
---argument, skipping one optional `[...]` argument. Braces in the argument
---may nest; an argument left open continues on the next line, and its first
---line is returned.
---@param line string
---@return string|nil name
---@return boolean starred
---@return string|nil arg
local function split_latex(line)
  local name, star, rest = line:match("^%s*\\(%a+)(%*?)%s*(.*)$")
  if not name then return nil, false, nil end
  -- Hide \{ and \} so %b{} balances only real groups.
  rest = rest:gsub("\\{", "\1"):gsub("\\}", "\2"):gsub("^%b[]%s*", "", 1)
  local braced = rest:match("^%b{}")
  local arg = braced and braced:sub(2, -2) or rest:match("^{(.*%S.*)$")
  if not arg then return name, star == "*", nil end
  arg = arg:gsub("\1", "\\{"):gsub("\2", "\\}")
  return name, star == "*", vim.trim(arg)
end

---@param line string
---@param line_num integer
---@param headings table<string, integer>
---@param include_starred boolean
---@return LatexNavCore.Heading|nil
local function parse_latex(line, line_num, headings, include_starred)
  local name, starred, title = split_latex(line)
  local level = name and headings[name]
  if not level or not title or (starred and not include_starred) then return nil end
  return {
    text = vim.trim(line), title = title, line = line_num, level = level,
    kind = name, starred = starred, source_file = "",
  }
end

---ATX markdown (`#` to `######`) and org (`*`, any depth) headings.
---@param line string
---@param line_num integer
---@param marker string  Lua pattern class for the heading marker.
---@param max_level integer
---@return LatexNavCore.Heading|nil
local function parse_marked(line, line_num, marker, max_level)
  local marks, title = line:match("^(" .. marker .. "+)%s+(.+)$")
  if not marks or #marks > max_level then return nil end
  return {
    text = vim.trim(line), title = vim.trim(title), line = line_num, level = #marks,
    kind = "h" .. #marks, starred = false, source_file = "",
  }
end

---@param line string
---@param line_num integer
---@param filetype string
---@param headings table<string, integer>
---@param include_starred boolean
---@return LatexNavCore.Heading|nil
local function parse_line(line, line_num, filetype, headings, include_starred)
  if filetype == "tex" then
    return parse_latex(line, line_num, headings, include_starred)
  elseif filetype == "markdown" then
    return parse_marked(line, line_num, "#", 6)
  elseif filetype == "org" then
    return parse_marked(line, line_num, "%*", math.huge)
  end
end

---Resolve a LaTeX include argument to an absolute path.
---Appends ".tex" if the bare path is not readable. Returns nil if not found.
---@param raw_path string  The argument from \input{...}, e.g. "chapters/intro"
---@param root_dir string  Absolute path of the project root directory.
---@return string|nil
local function resolve_include(raw_path, root_dir)
  raw_path = vim.trim(raw_path)
  if raw_path == "" then return nil end
  local abs = root_dir .. "/" .. raw_path
  if vim.fn.filereadable(abs) == 1 then return abs end
  local abs_tex = abs .. ".tex"
  if vim.fn.filereadable(abs_tex) == 1 then return abs_tex end
  return nil
end

---@class LatexNavCore.HeadingsScan
---@field root_dir string
---@field filetype string
---@field opts     LatexNavCore.HeadingsScanOpts
---@field headings table<string, integer>
---@field visited  table<string, boolean>  Cycle guard.
---@field results  LatexNavCore.Heading[]
---@field deps     table<string, integer>  Included file (relative to root_dir) -> mtime.

---Depth-first scan of `filepath`, recursing into includes where they occur
---so results stay in document order.
---@param scan       LatexNavCore.HeadingsScan
---@param filepath   string   Absolute path of the file to scan now.
---@param source_rel string   Path relative to root_dir ("" for the root file).
---@param depth      integer  Recursion depth; 0 for the root file.
local function scan_recursive(scan, filepath, source_rel, depth)
  local opts = scan.opts
  if depth > (opts.recursive_limit or 5) then return end
  if scan.visited[filepath] then return end
  scan.visited[filepath] = true

  -- The root file's staleness is user-managed; only includes are tracked.
  if source_rel ~= "" then
    scan.deps[source_rel] = vim.fn.getftime(filepath)
  end

  local file = io.open(filepath, "r")
  if not file then
    local level = source_rel == "" and vim.log.levels.ERROR or vim.log.levels.WARN
    vim.notify("[cached_headings] Could not open file: " .. filepath, level)
    return
  end
  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  local follow_includes = opts.scan_includes and scan.filetype == "tex"
  local ignore_pat      = opts.ignore_include_pattern

  for line_num, line in ipairs(lines) do
    local entry = parse_line(line, line_num, scan.filetype, scan.headings, opts.include_starred)
    if entry then
      entry.source_file = source_rel
      table.insert(scan.results, entry)
    elseif follow_includes then
      for _, inc_pat in ipairs(INCLUDE_PATTERNS) do
        local raw_path = line:match(inc_pat)
        if raw_path then
          local skip = ignore_pat and ignore_pat ~= "" and raw_path:find(ignore_pat)
          local abs_included = not skip and resolve_include(raw_path, scan.root_dir)
          if abs_included then
            -- resolve_include always prefixes root_dir, so this is the relative path.
            scan_recursive(scan, abs_included, abs_included:sub(#scan.root_dir + 2), depth + 1)
          end
          break
        end
      end
    end
  end
end

---Scan a file and return all heading entries in document order.
---
---With `opts.scan_includes` (LaTeX only), files referenced by \input,
---\include, and \subfile are scanned recursively where they occur.
---
---@param filepath string  Absolute path to the file on disk.
---@param filetype string  "tex", "markdown", or "org".
---@param opts LatexNavCore.HeadingsScanOpts|nil
---@return LatexNavCore.Heading[]
---@return table<string, integer> deps  Included file (relative to the root's directory) -> mtime.
M.scan_file = function(filepath, filetype, opts)
  opts = opts or {}
  local root_dir = vim.fn.fnamemodify(filepath, ":h"):gsub("/$", "")
  ---@type LatexNavCore.HeadingsScan
  local scan = {
    root_dir = root_dir,
    filetype = filetype,
    opts     = opts,
    headings = M.resolve_latex_headings(opts.latex_headings),
    visited  = {},
    results  = {},
    deps     = {},
  }
  scan_recursive(scan, filepath, "", 0)
  return scan.results, scan.deps
end

return M
