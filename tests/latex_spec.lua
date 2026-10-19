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
