local M = {}

--- Return the path where a cache file for `filepath` should be stored.
---
---   "local"  -> same directory as the file, hidden: .filename.ext
---   "global" -> stdpath("data")/<subdir>/<sha256>.ext
---
---@param filepath string  Absolute path to the root/source file.
---@param strategy string  "local" | "global"
---@param subdir   string  Subdirectory name under stdpath("data") for "global".
---@param ext      string  File extension including the dot (e.g. ".labels").
---@return string
M.get_cache_path = function(filepath, strategy, subdir, ext)
  if strategy == "local" then
    local dir      = vim.fn.fnamemodify(filepath, ":h")
    local filename = vim.fn.fnamemodify(filepath, ":t")
    return dir .. "/." .. filename .. ext
  else
    local cache_dir = vim.fn.stdpath("data") .. "/" .. subdir
    vim.fn.mkdir(cache_dir, "p")
    local hash = vim.fn.sha256(filepath)
    return cache_dir .. "/" .. hash .. ext
  end
end

--- Delete all cache files managed by a plugin.
---
--- Only supported for the "global" strategy. With "local" the files are
--- scattered next to source files and cannot be enumerated without a project
--- walk; callers should inform the user to delete them manually.
---
---@param strategy string  "local" | "global"
---@param subdir   string  Subdirectory name under stdpath("data").
---@param ext      string  File extension including the dot (e.g. ".labels").
---@return integer, string|nil  number of files deleted, error message or nil
M.wipe_all_caches = function(strategy, subdir, ext)
  if strategy ~= "global" then
    return 0, "wipe_all is only supported for the 'global' cache strategy. "
      .. "Delete *" .. ext .. " files manually from your project directories."
  end

  local cache_dir = vim.fn.stdpath("data") .. "/" .. subdir
  local files     = vim.fn.glob(cache_dir .. "/*" .. ext, false, true)
  local count     = 0
  for _, f in ipairs(files) do
    if vim.fn.delete(f) == 0 then
      count = count + 1
    end
  end
  return count, nil
end

return M
