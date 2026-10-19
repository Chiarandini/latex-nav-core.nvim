-- Run with: tests/run.sh

local latex = require("latex_nav_core.latex")

local fixtures = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/fixtures"

describe("latex.find_root_via_subfiles", function()
  it("returns nil for a non-existent file", function()
    assert.is_nil(latex.find_root_via_subfiles("/tmp/__no_such_file__.tex"))
  end)

  it("returns nil for a file without \\documentclass[...]{subfiles}", function()
    assert.is_nil(latex.find_root_via_subfiles(fixtures .. "/chapters/chapter1.tex"))
  end)

  it("detects root path from \\documentclass[../main.tex]{subfiles}", function()
    local root = latex.find_root_via_subfiles(fixtures .. "/chapters/chapter1_subfile.tex")
    assert.is_not_nil(root, "should find root via subfiles package declaration")
    -- Root should resolve to the fixtures/main.tex absolute path
    assert.is_true(root:find("main.tex", 1, true) ~= nil)
    assert.equal(1, vim.fn.filereadable(root), "resolved root file should be readable")
  end)

  it("returns nil when the referenced root file does not exist", function()
    -- Create a temp file with a non-existent root ref
    local tmp = vim.fn.tempname() .. ".tex"
    local f = io.open(tmp, "w")
    f:write("\\documentclass[../nonexistent_root.tex]{subfiles}\n")
    f:close()
    local result = latex.find_root_via_subfiles(tmp)
    os.remove(tmp)
    assert.is_nil(result)
  end)
end)

describe("latex.verify_or_find_heading", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, 300 do lines[i] = "text " .. i end
    lines[110] = "\\section{Exercises}"
    lines[260] = "\\section{Exercises}"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)

  after_each(function() vim.api.nvim_buf_delete(buf, { force = true }) end)

  it("returns the cached line when the heading is still there", function()
    assert.equal(260, latex.verify_or_find_heading(buf, 260, "\\section{Exercises}", 200))
  end)

  it("finds the nearest copy of a repeated heading, not the first", function()
    assert.equal(260, latex.verify_or_find_heading(buf, 250, "\\section{Exercises}", 200))
    assert.equal(110, latex.verify_or_find_heading(buf, 100, "\\section{Exercises}", 200))
  end)

  it("returns nil when the heading is outside the window", function()
    assert.is_nil(latex.verify_or_find_heading(buf, 10, "\\section{Exercises}", 50))
  end)
end)
