-- Load-or-scan entry point shared by the snacks and telescope heading pickers.

local M = {}

---Heading entries for `filepath`: from the cache when it is fresh for `opts`,
---otherwise by rescanning and rewriting it.
---@param filepath string  Absolute path of the file whose headings are wanted.
---@param filetype string
---@param opts     LatexNavCore.HeadingsScanOpts
---@param strategy "local"|"global"
---@return LatexNavCore.Heading[] entries
---@return string cache_path
---@return LatexNavCore.HeadingsCacheMeta meta
---@return string|nil err  Set when a rescan could not write the cache.
function M.load(filepath, filetype, opts, strategy)
  local cache = require("latex_nav_core.cached_headings.cache")
  local cache_path = cache.get_cache_path(filepath, strategy)
  local sig = require("latex_nav_core.cached_headings.parser").signature(opts)
  local entries, meta = cache.read_cache(cache_path, sig, vim.fn.fnamemodify(filepath, ":h"))
  if entries and meta then
    return entries, cache_path, meta
  end
  return M.refresh(filepath, filetype, opts, strategy)
end

---Rescan `filepath` and overwrite its cache.
---@param filepath string
---@param filetype string
---@param opts     LatexNavCore.HeadingsScanOpts
---@param strategy "local"|"global"
---@return LatexNavCore.Heading[] entries
---@return string cache_path
---@return LatexNavCore.HeadingsCacheMeta meta
---@return string|nil err  Set when the cache could not be written.
function M.refresh(filepath, filetype, opts, strategy)
  local cache  = require("latex_nav_core.cached_headings.cache")
  local parser = require("latex_nav_core.cached_headings.parser")
  local cache_path = cache.get_cache_path(filepath, strategy)
  local entries, deps = parser.scan_file(filepath, filetype, opts)
  local meta = { sig = parser.signature(opts), deps = deps }
  local _, err = cache.write_cache(cache_path, entries, meta)
  return entries, cache_path, meta, err
end

return M
