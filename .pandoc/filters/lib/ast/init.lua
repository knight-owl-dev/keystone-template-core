-- ast/init.lua — KAST facade: the single seam over Pandoc AST construction,
-- serialization, and inspection. See docs/pandoc-integration/kast.md.
--
-- Submodules are acquired through the global ks_require (installed by
-- lib/loader.lua) so they are parsed once per filter process. This file owns
-- the public surface: flat constructors for lowest ceremony, namespaced
-- helpers (kast.latex.*, kast.meta.*) for discoverability.

local construct = ks_require("ast.construct")
local latex     = ks_require("ast.latex")
local math      = ks_require("ast.math")
local meta      = ks_require("ast.meta")
local inspect   = ks_require("ast.inspect")

local kast = {}

-- Constructors are flat — kast.RawBlock(...) reads almost like pandoc.RawBlock.
for name, fn in pairs(construct) do
  kast[name] = fn
end

-- Cohesive helpers are namespaced.
kast.latex = latex   -- inlines / blocks / env / escape_path / check_label
kast.math = math     -- unconvertible (per-target math convertibility probe)
kast.meta = meta     -- stringify / is_blank / add_header_include / add_css

-- Traversal and parsing live at the top level (single, deliberate entry each).
kast.read = inspect.read
kast.walk = inspect.walk
kast.blocks_to_inlines = inspect.blocks_to_inlines

return kast
