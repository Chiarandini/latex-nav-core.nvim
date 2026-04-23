-- latex_nav_core.latex
--
-- Shared LaTeX helpers used by telescope-latex-references, snacks-latex-labels,
-- telescope-cached-headings, snacks-cached-headings, and any future plugin in
-- the latex-nav-core family.
--
-- Root-file detection and smart-jump verification were previously duplicated
-- across those plugins' `utils.lua` files; lifting them here lets each plugin
-- (and downstream projects like NoetherVim) depend on one source of truth
-- without reaching into `telescope._extensions.*` paths.

local M = {}

-- ─── Root file detection ──────────────────────────────────────────────────────

---Determine the LaTeX project root file.
---
---Resolution order:
---  1. vimtex: `vim.b.vimtex.tex` (the main file vimtex has identified)
---  2. Current buffer's file     (fallback when vimtex is absent / not active)
---
---@return string|nil  Absolute path to the root file, or nil if nothing is open.
M.get_root_file = function()
  -- vimtex stores project info in the buffer-local variable b:vimtex.
  -- pcall avoids errors when vimtex is not installed or the variable is unset.
  local ok, vimtex = pcall(function() return vim.b.vimtex end)
  if ok and type(vimtex) == "table" then
    local tex = vimtex.tex
    if type(tex) == "string" and tex ~= "" then
      return vim.fn.fnamemodify(tex, ":p")
    end
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then return nil end
  return vim.fn.fnamemodify(filepath, ":p")
end

---Detect the root file of a LaTeX subfile by parsing
---`\documentclass[root.tex]{subfiles}` from the first 20 lines of `filepath`.
---Returns the absolute, normalised path to the root file, or nil.
---@param filepath string  Absolute path of the (possibly subfile) .tex file.
---@return string|nil
M.find_root_via_subfiles = function(filepath)
  local f = io.open(filepath, "r")
  if not f then return nil end
  local count = 0
  for line in f:lines() do
    count = count + 1
    if count > 20 then break end
    local rel = line:match("\\documentclass%[(.-)%]{subfiles}")
    if rel then
      f:close()
      local dir = vim.fn.fnamemodify(filepath, ":h")
      local abs = vim.fn.fnamemodify(dir .. "/" .. rel, ":p")
      -- :p may add a trailing slash for bare directory names; strip it
      if abs:sub(-1) == "/" then abs = abs:sub(1, -2) end
      if vim.fn.filereadable(abs) == 1 then return abs end
      return nil
    end
  end
  f:close()
  return nil
end

-- ─── Smart-jump verification ──────────────────────────────────────────────────

---Return true if `line` appears to define `label_id`.
---
---Two checks are tried in order:
---  1. `{label_id}` — catches `\label{q:sky}` when id = "q:sky", and
---     `\label{th:snakeLem}` when id = "th:snakeLem"
---  2. `{suffix}` — catches `\begin{thm}{...}{snakeLem}` when id = "th:snakeLem"
---     (the prefix was added by a latex-labels transformation; the raw label
---     in the file is just the part after the last colon)
---@param line     string
---@param label_id string
---@return boolean
local function line_has_label(line, label_id)
  if line:find("{" .. label_id .. "}", 1, true) then return true end
  local suffix = label_id:match(":(.+)$")
  if suffix and line:find("{" .. suffix .. "}", 1, true) then return true end
  return false
end

---Search for `label_id` near `target_line` using the Neovim buffer API.
---@param bufnr       integer
---@param target_line integer
---@param label_id    string
---@param window_size integer
---@return integer|nil
local function verify_label_in_buffer(bufnr, target_line, label_id, window_size)
  local total = vim.api.nvim_buf_line_count(bufnr)
  target_line = math.max(1, math.min(target_line, total))

  local exact = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
  if exact and line_has_label(exact, label_id) then
    return target_line
  end

  local start = math.max(1, target_line - window_size)
  local stop  = math.min(total, target_line + window_size)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start - 1, stop, false)
  for i, line in ipairs(lines) do
    if line_has_label(line, label_id) then
      return start + i - 1
    end
  end
  return nil
end

---Search for `label_id` near `target_line` by streaming the file from disk.
---Only reads lines inside [target_line - window_size, target_line + window_size].
---@param filepath    string
---@param target_line integer
---@param label_id    string
---@param window_size integer
---@return integer|nil
local function verify_label_in_file(filepath, target_line, label_id, window_size)
  local f = io.open(filepath, "r")
  if not f then return nil end

  local search_start = math.max(1, target_line - window_size)
  local search_end   = target_line + window_size
  local lnum  = 0
  local found = nil

  for line in f:lines() do
    lnum = lnum + 1
    if lnum > search_end then break end
    if lnum >= search_start and line_has_label(line, label_id) then
      found = lnum
      break
    end
  end

  f:close()
  return found
end

---Verify whether `label_id` is still at `target_line` in `filepath`.
---If not, search +/- `window_size` lines around that position.
---Uses the Neovim buffer API when the file is loaded (zero disk I/O);
---otherwise streams from disk.
---
---@param filepath    string   Absolute path to the file containing the label.
---@param target_line integer  1-based line number from the cache.
---@param label_id    string   The label id as stored in the cache.
---@param window_size integer  Lines to search on each side of the cached position.
---@return integer|nil  Verified/found line number, or nil if not found in window.
M.verify_or_find_label = function(filepath, target_line, label_id, window_size)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return verify_label_in_buffer(bufnr, target_line, label_id, window_size)
  end
  return verify_label_in_file(filepath, target_line, label_id, window_size)
end

---Verify whether `heading_text` is still at `target_line` in the buffer.
---If not, search +/- `window_size` lines around that position.
---
---Used by cached-headings variants where the cache stores the full, trimmed
---line text of each heading (tex / markdown / org). Matching is exact after
---vim.trim — any shift triggers the window search.
---
---@param bufnr        integer
---@param target_line  integer  1-based
---@param heading_text string
---@param window_size  integer  lines to search on each side
---@return integer|nil
M.verify_or_find_heading = function(bufnr, target_line, heading_text, window_size)
  local total = vim.api.nvim_buf_line_count(bufnr)
  target_line = math.max(1, math.min(target_line, total))

  local exact = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
  if exact and vim.trim(exact) == heading_text then
    return target_line
  end

  local start = math.max(1, target_line - window_size)
  local stop  = math.min(total, target_line + window_size)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start - 1, stop, false)
  for i, line in ipairs(lines) do
    if vim.trim(line) == heading_text then
      return start + i - 1
    end
  end
  return nil
end

return M
