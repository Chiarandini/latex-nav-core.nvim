-- Run with: tests/run.sh

local cache = require("latex_nav_core.cached_headings.cache")

local SIG = "test-sig"

local function tmp_path()
  return vim.fn.tempname() .. ".headings"
end

local function meta(deps)
  return { sig = SIG, deps = deps or {} }
end

local function heading(fields)
  return vim.tbl_extend("keep", fields, {
    source_file = "", line = 1, level = 3, kind = "section", starred = false,
    title = "T", text = "\\section{T}",
  })
end

local function first_line(path)
  local f = assert(io.open(path, "r"))
  local line = f:read("*l")
  f:close()
  return line
end

describe("cache.get_cache_path", function()
  it("local strategy: hidden file next to source", function()
    local p = cache.get_cache_path("/home/user/docs/thesis.tex", "local")
    assert.equal("/home/user/docs/.thesis.tex.headings", p)
  end)

  it("global strategy: path inside stdpath(data)", function()
    local p = cache.get_cache_path("/home/user/docs/thesis.tex", "global")
    assert.is_true(p:find(vim.fn.stdpath("data"), 1, true) == 1)
    assert.is_true(p:sub(-9) == ".headings")
  end)

  it("global strategy: two different files produce different paths", function()
    local p1 = cache.get_cache_path("/a/foo.tex", "global")
    local p2 = cache.get_cache_path("/b/foo.tex", "global")
    assert.are_not.equal(p1, p2)
  end)
end)

describe("cache round-trip", function()
  local path

  before_each(function() path = tmp_path() end)
  after_each(function() os.remove(path) end)

  it("preserves every entry field", function()
    local e = heading({
      source_file = "chapters/intro.tex", line = 42, level = 7, kind = "bonussection",
      starred = true, title = "Stone-\\v{C}ech", text = "\\bonussection*{Stone-\\v{C}ech}",
    })
    assert.is_true(cache.write_cache(path, { e }, meta()))
    local read = cache.read_cache(path, SIG, "/")
    assert.are.same({ e }, read)
  end)

  it("preserves `|` and `%` in title and text", function()
    local e = heading({ title = "$|x|$ at 50% off", text = "\\section{$|x|$ at 50% off}" })
    cache.write_cache(path, { e }, meta())
    local read = assert(cache.read_cache(path, SIG, "/"))
    assert.equal("$|x|$ at 50% off", read[1].title)
    assert.equal("\\section{$|x|$ at 50% off}", read[1].text)
  end)

  it("keeps markdown heading text that starts with #", function()
    local e = heading({ kind = "h1", level = 1, title = "Top", text = "# Top" })
    cache.write_cache(path, { e }, meta())
    assert.equal("# Top", cache.read_cache(path, SIG, "/")[1].text)
  end)

  it("preserves order across root and sub-file entries", function()
    local entries = {
      heading({ line = 1, title = "A" }),
      heading({ source_file = "ch1.tex", line = 3, title = "B" }),
      heading({ line = 10, title = "C" }),
    }
    cache.write_cache(path, entries, meta())
    assert.are.same(entries, cache.read_cache(path, SIG, "/"))
  end)

  it("returns an empty list and the metadata for an empty cache", function()
    cache.write_cache(path, {}, meta())
    local read, m = cache.read_cache(path, SIG, "/")
    assert.are.same({}, read)
    assert.equal(SIG, m.sig)
  end)

  it("writes the v3 header", function()
    cache.write_cache(path, {}, meta())
    assert.equal("# v3", first_line(path))
  end)

  it("write_cache returns false when path is unwritable", function()
    local ok, err = cache.write_cache("/no_permission_dir/__test__.headings", {}, meta())
    assert.is_false(ok)
    assert.is_string(err)
  end)
end)

describe("cache.read_cache staleness", function()
  local path

  before_each(function() path = tmp_path() end)
  after_each(function() os.remove(path) end)

  it("returns nil for a non-existent file", function()
    assert.is_nil(cache.read_cache("/tmp/__no_such_cache_file__.headings", SIG, "/"))
  end)

  it("returns nil when the signature differs", function()
    cache.write_cache(path, { heading({}) }, meta())
    assert.is_nil(cache.read_cache(path, "other-sig", "/"))
  end)

  it("returns nil for a cache written by an older format", function()
    local f = assert(io.open(path, "w"))
    f:write("# v2\n|5|1|\\part{Foundations}\n")
    f:close()
    assert.is_nil(cache.read_cache(path, SIG, "/"))
  end)
end)

describe("cache.read_cache dependency mtimes", function()
  local root_dir, dep_rel, dep_abs, path

  before_each(function()
    root_dir = vim.fn.tempname()
    vim.fn.mkdir(root_dir .. "/chapters", "p")
    dep_rel = "chapters/dep.tex"
    dep_abs = root_dir .. "/" .. dep_rel
    path = tmp_path()
    local f = assert(io.open(dep_abs, "w"))
    f:write("\\section{test}")
    f:close()
  end)

  after_each(function()
    vim.fn.delete(root_dir, "rf")
    os.remove(path)
  end)

  it("returns nil when a stored mtime is stale", function()
    local mtime = vim.fn.getftime(dep_abs)
    cache.write_cache(path, { heading({ source_file = dep_rel }) }, meta({ [dep_rel] = mtime - 1 }))
    assert.is_nil(cache.read_cache(path, SIG, root_dir))
  end)

  it("returns entries when every stored mtime is current", function()
    local mtime = vim.fn.getftime(dep_abs)
    cache.write_cache(path, { heading({ source_file = dep_rel }) }, meta({ [dep_rel] = mtime }))
    local read, m = cache.read_cache(path, SIG, root_dir)
    assert.equal(1, #read)
    assert.equal(mtime, m.deps[dep_rel])
  end)
end)
