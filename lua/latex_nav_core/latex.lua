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
---The resolved file is then walked up the `subfiles` chain: vimtex in local
---mode (|g:vimtex_subfile_start_local|) reports the subfile itself as the
---main file, and a book's main file may in turn be a subfile of a larger
---collection.  The project root is the top of that chain.
---
---@return string|nil  Absolute path to the root file, or nil if nothing is open.
M.get_root_file = function()
  local root

  -- vimtex stores project info in the buffer-local variable b:vimtex.
  -- pcall avoids errors when vimtex is not installed or the variable is unset.
  local ok, vimtex = pcall(function() return vim.b.vimtex end)
  if ok and type(vimtex) == "table" then
    local tex = vimtex.tex
    if type(tex) == "string" and tex ~= "" then
      root = vim.fn.fnamemodify(tex, ":p")
    end
  end

  if not root then
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return nil end
    root = vim.fn.fnamemodify(filepath, ":p")
  end

  local seen = {}
  while not seen[root] do
    seen[root] = true
    local parent = M.find_root_via_subfiles(root)
    if not parent then break end
    root = parent
  end
  return root
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

---Whether the `{` at `brace_pos` belongs to a command that points at a label
---rather than defining one. Every member of the family ends in "ref" (\ref,
---\cref, \Cref, \eqref, \autoref, \nameref, \pageref, \vref, \labelcref),
---which is cheaper and more complete than listing them.
---@param line      string
---@param brace_pos integer
---@return boolean
local function is_reference(line, brace_pos)
  local cmd = line:sub(1, brace_pos - 1):match("\\(%a+)%*?%s*$")
  return cmd ~= nil and cmd:lower():sub(-3) == "ref"
end

---How strongly `line` looks like the definition of `label_id`:
---  2    the id in full, as in `\label{th:snakeLem}`
---  1    the bare label a transformation prefixed, as in
---       `\begin{thm}{snakeLem}{Snake Lemma}` for id "th:snakeLem"
---  nil  no match, or matches only inside reference commands
---
---The two are worth telling apart because the bare form is ambiguous:
---`{snakeLem}` also appears in every `\cref{snakeLem}`.
---@param line     string
---@param label_id string
---@return integer|nil
local function label_match_quality(line, label_id)
  local function defines(needle)
    local init = 1
    while true do
      local s = line:find("{" .. needle .. "}", init, true)
      if not s then return false end
      if not is_reference(line, s) then return true end
      init = s + 1
    end
  end

  if defines(label_id) then return 2 end
  local suffix = label_id:match(":(.+)$")
  if suffix and defines(suffix) then return 1 end
  return nil
end

---Whether `candidate` is a better answer than `best`. A full-id match beats a
---bare one, and among equals the line nearest the cached position wins.
---
---Nearest, not first. The window is `window_size` lines on each side, and
---taking the first match while scanning from the top of it meant a `\cref`
---anywhere above the theorem won, so a cache stale by a single line sent `gd`
---to a citation instead of the definition.
local function better(candidate, best, target_line)
  if not best then return true end
  if candidate.quality ~= best.quality then
    return candidate.quality > best.quality
  end
  return math.abs(candidate.line - target_line) < math.abs(best.line - target_line)
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
  if exact and label_match_quality(exact, label_id) then
    return target_line
  end

  local start = math.max(1, target_line - window_size)
  local stop  = math.min(total, target_line + window_size)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start - 1, stop, false)
  local best
  for i, line in ipairs(lines) do
    local quality = label_match_quality(line, label_id)
    if quality then
      local candidate = { line = start + i - 1, quality = quality }
      if better(candidate, best, target_line) then best = candidate end
    end
  end
  return best and best.line or nil
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
  local lnum = 0
  local best

  for line in f:lines() do
    lnum = lnum + 1
    if lnum > search_end then break end
    if lnum >= search_start then
      local quality = label_match_quality(line, label_id)
      if quality then
        local candidate = { line = lnum, quality = quality }
        if better(candidate, best, target_line) then best = candidate end
      end
    end
  end

  f:close()
  return best and best.line or nil
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

---Find the line holding `heading_text` nearest to `target_line`, searching
---+/- `window_size` lines. Nearest wins so that repeated titles (two
---"Exercises" sections) resolve to the one that moved, not the first one.
---
---Used by cached-headings variants where the cache stores the full, trimmed
---line text of each heading (tex / markdown / org). Matching is exact after
---vim.trim.
---
---@param bufnr        integer
---@param target_line  integer  1-based
---@param heading_text string
---@param window_size  integer  lines to search on each side
---@return integer|nil
M.verify_or_find_heading = function(bufnr, target_line, heading_text, window_size)
  local total = vim.api.nvim_buf_line_count(bufnr)
  target_line = math.max(1, math.min(target_line, total))

  local start = math.max(1, target_line - window_size)
  local stop  = math.min(total, target_line + window_size)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start - 1, stop, false)
  local function matches(lnum)
    local line = lines[lnum - start + 1]
    return line ~= nil and vim.trim(line) == heading_text
  end

  -- Edits above a heading push it down, so below wins a tie.
  for d = 0, window_size do
    if matches(target_line + d) then return target_line + d end
    if d > 0 and target_line - d >= start and matches(target_line - d) then
      return target_line - d
    end
  end
  return nil
end

return M
