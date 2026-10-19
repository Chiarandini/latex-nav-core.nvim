-- Run with: tests/run.sh

local headings = require("latex_nav_core.cached_headings")

local dir, file

local function write(path, lines)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

describe("cached_headings", function()
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    file = dir .. "/doc.tex"
    write(file, { "\\section{Real}", "\\bonussection{Bonus}" })
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  local function titles(entries)
    return vim.tbl_map(function(e) return e.title end, entries)
  end

  describe("load", function()
    it("scans and writes the cache on a miss", function()
      local entries, cache_path = headings.load(file, "tex", {}, "local")
      assert.are.same({ "Real" }, titles(entries))
      assert.equal(1, vim.fn.filereadable(cache_path))
    end)

    it("serves the cache on a hit instead of rescanning", function()
      headings.load(file, "tex", {}, "local")
      write(file, { "\\section{Changed}" })
      assert.are.same({ "Real" }, titles(headings.load(file, "tex", {}, "local")))
    end)

    it("rescans when the heading table changes", function()
      headings.load(file, "tex", {}, "local")
      local entries = headings.load(file, "tex", { latex_headings = { bonussection = 3 } }, "local")
      assert.are.same({ "Real", "Bonus" }, titles(entries))
      assert.equal("bonussection", entries[2].kind)
    end)

    it("rescans when an included file changes on disk", function()
      local opts = { scan_includes = true }
      write(file, { "\\section{Root}", "\\input{child}" })
      local child = dir .. "/child.tex"
      write(child, { "\\section{Old}" })
      local past = os.time() - 60
      vim.uv.fs_utime(child, past, past)
      headings.load(file, "tex", opts, "local")
      write(child, { "\\section{New}" })
      assert.are.same({ "Root", "New" }, titles(headings.load(file, "tex", opts, "local")))
    end)

    it("keeps kind and starred across a cache hit", function()
      write(file, { "\\bonussection*{Starred}" })
      local opts = { latex_headings = { bonussection = 3 }, include_starred = true }
      headings.load(file, "tex", opts, "local")
      local e = headings.load(file, "tex", opts, "local")[1]
      assert.equal("bonussection", e.kind)
      assert.is_true(e.starred)
    end)
  end)

  describe("refresh", function()
    it("rescans even when the cache is fresh", function()
      headings.load(file, "tex", {}, "local")
      write(file, { "\\section{Changed}" })
      assert.are.same({ "Changed" }, titles(headings.refresh(file, "tex", {}, "local")))
    end)
  end)
end)
