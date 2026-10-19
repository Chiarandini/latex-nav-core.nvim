-- On-disk heading cache. Format:
--
--   # v3
--   # sig:<parser.signature of the scan options>
--   # dep:<path relative to the root's directory>=<mtime>
--   <source_file>|<line>|<level>|<kind>|<starred 0/1>|<title, %XX-escaped>|<text>
--
-- `text` is last so it may contain `|`; `title` is escaped for the same reason.

local M = {}

local VERSION = "# v3"

---@class LatexNavCore.HeadingsCacheMeta
---@field sig  string                  Signature the entries were scanned with.
---@field deps table<string, integer>  Included file (relative to the root's directory) -> mtime.

local function escape(s)
  return (s:gsub("[%%|\n]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unescape(s)
  return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

---Return the path where the cache file for `filepath` should be stored.
---
---  "local"  -> same directory as the file, hidden: .filename.ext.headings
---  "global" -> stdpath("data")/cached_headings/<sha256>.headings
---
---@param filepath string  Absolute path to the source file.
---@param strategy string  "local" | "global"
---@return string
M.get_cache_path = function(filepath, strategy)
  return require("latex_nav_core.cache").get_cache_path(filepath, strategy, "cached_headings", ".headings")
end

---Read a cache file. Returns nil when the file is missing, was written by an
---older format, was scanned with a different signature, or when an included
---file has changed on disk since.
---@param cache_path string
---@param sig        string  Expected signature (`parser.signature(opts)`).
---@param root_dir   string  Directory the `dep:` paths are relative to.
---@return LatexNavCore.Heading[]|nil
---@return LatexNavCore.HeadingsCacheMeta|nil
M.read_cache = function(cache_path, sig, root_dir)
  local file = io.open(cache_path, "r")
  if not file then return nil end
  if file:read("*l") ~= VERSION then
    file:close()
    return nil
  end

  local meta    = { sig = nil, deps = {} }
  local entries = {}
  for raw in file:lines() do
    if vim.startswith(raw, "# sig:") then
      meta.sig = raw:sub(7)
    elseif vim.startswith(raw, "# dep:") then
      local rel_path, mtime = raw:sub(7):match("^(.+)=(%-?%d+)$")
      if rel_path then meta.deps[rel_path] = tonumber(mtime) end
    else
      local source, line, level, kind, starred, title, text =
        raw:match("^(.-)|(%d+)|(%d+)|(%w+)|([01])|(.-)|(.+)$")
      if line then
        table.insert(entries, {
          source_file = source,
          line        = tonumber(line),
          level       = tonumber(level),
          kind        = kind,
          starred     = starred == "1",
          title       = unescape(title),
          text        = text,
        })
      end
    end
  end
  file:close()

  if meta.sig ~= sig then return nil end
  for rel_path, mtime in pairs(meta.deps) do
    if vim.fn.getftime(root_dir .. "/" .. rel_path) ~= mtime then return nil end
  end
  return entries, meta
end

---Write heading entries and their metadata to a cache file.
---@param cache_path string
---@param entries    LatexNavCore.Heading[]
---@param meta       LatexNavCore.HeadingsCacheMeta
---@return boolean ok
---@return string|nil err
M.write_cache = function(cache_path, entries, meta)
  -- Built before opening so a bad entry raises without truncating the cache.
  local out = { VERSION, "# sig:" .. meta.sig }
  for rel_path, mtime in pairs(meta.deps) do
    table.insert(out, string.format("# dep:%s=%d", rel_path, mtime))
  end
  for _, e in ipairs(entries) do
    table.insert(out, string.format("%s|%d|%d|%s|%d|%s|%s",
      e.source_file or "", e.line, e.level, e.kind, e.starred and 1 or 0, escape(e.title), e.text))
  end

  local file = io.open(cache_path, "w")
  if not file then
    return false, "Could not open cache file for writing: " .. cache_path
  end
  file:write(table.concat(out, "\n"), "\n")
  file:close()
  return true, nil
end

---Delete all cache files managed by this plugin.
---
---For the "global" strategy every *.headings file inside the cache directory
---is removed. For "local" the files are scattered next to source files, so
---enumeration is not feasible; the function returns an explanatory message.
---
---@param strategy string  "local" | "global"
---@return integer count  Number of files deleted.
---@return string|nil err
M.wipe_all_caches = function(strategy)
  return require("latex_nav_core.cache").wipe_all_caches(strategy, "cached_headings", ".headings")
end

return M
