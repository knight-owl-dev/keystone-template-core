-- loader.lua — Memoized module loader for Keystone Lua filters
--
-- dofile() re-parses and re-executes its target on every call; a filter that
-- loads a lib from a dozen handlers would parse it a dozen times per process.
-- This installs a single global ks_require(name) that resolves a logical
-- module name to a file under filters/lib and caches the result, so each
-- module is parsed once per filter process regardless of consumer count.
--
-- Name resolution: dots map to directories.
--   "ast"             → lib/ast/init.lua (if present) else lib/ast.lua
--   "ast.latex"       → lib/ast/latex.lua
--   "format-registry" → lib/format-registry.lua
--
-- Caching is safe: lib modules are stateless wrappers over the global
-- `pandoc`, which they resolve lazily at call time. The cache holds the
-- module table, never the `pandoc` table — so a cached module still honors a
-- `pandoc` swapped onto _G between test cases.
--
-- Installed as a global so handlers dofile'd into the same Lua state, and
-- submodules, call it without re-importing. Idempotent: a second install in
-- the same state reuses the existing loader and its cache.

return function(filters_dir)
  if _G.ks_require then return _G.ks_require end

  -- Capturing pandoc.path.join at install time is the one deliberate
  -- exception to the call-time-resolution rule that KAST's AST wrappers
  -- follow: this is path resolution, not AST construction, so it needn't stay
  -- transparent to a swapped _G.pandoc — and install always runs after pandoc
  -- (real or mock) is in place.
  local join = pandoc.path.join
  local lib_dir = join({ filters_dir, "lib" })
  local cache = {}

  --- Resolve a logical module name to a file path. A package directory
  --- (with init.lua) takes precedence over a same-named flat file.
  local function resolve(name)
    local rel = name:gsub("%.", "/")
    local pkg_init = join({ lib_dir, rel, "init.lua" })
    local probe = io.open(pkg_init, "r")
    if probe then
      probe:close()
      return pkg_init
    end
    return join({ lib_dir, rel .. ".lua" })
  end

  local function ks_require(name)
    if cache[name] == nil then
      cache[name] = dofile(resolve(name))
    end
    return cache[name]
  end

  _G.ks_require = ks_require
  return ks_require
end
