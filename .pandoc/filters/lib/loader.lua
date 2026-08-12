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

  -- Plain "/"-join rather than pandoc.path.join, so a standalone script with no
  -- pandoc in scope can bootstrap the loader too: epub-font-paths.lua runs under
  -- `lua` (busted) / `pandoc lua` (publish.sh) and must ks_require the registry
  -- like any filter. Module paths are simple relatives and filters_dir arrives
  -- without a trailing slash (pandoc.path.directory and the test harness both
  -- supply it that way), so string concatenation is exact here.
  local function join(parts) return table.concat(parts, "/") end
  local lib_dir = join({ filters_dir, "lib" })
  local cache = {}

  -- Sentinel parked in the cache while a module is mid-load. The cache entry is
  -- assigned only after dofile returns, so without this a module that requires
  -- itself (directly or through a cycle) would miss the cache and reload
  -- endlessly → stack overflow. Seams are acyclic leaves in practice; this turns
  -- an accidental cycle into a named error instead of a bare overflow.
  local LOADING = {}

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
    if cache[name] == LOADING then
      error("ks_require: circular dependency loading '" .. name .. "'", 0)
    end
    if cache[name] == nil then
      cache[name] = LOADING
      cache[name] = dofile(resolve(name))
    end
    return cache[name]
  end

  _G.ks_require = ks_require
  return ks_require
end
