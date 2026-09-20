-- list-builtin-fonts.lua — Print the built-in font files the runtime image ships
--
-- Emits one path per line, relative to the registry's FONTS_ROOT, for every
-- built-in font variant. The Docker font-extractor consumes this list (see
-- .docker/fonts/extract-fonts.sh), keeping font-registry.lua the single source
-- of truth for which fonts ship.
--
-- IMPORTANT: This script uses only standard Lua — no pandoc module. The
-- extractor invokes it via `pandoc lua` (as a convenient Lua interpreter), but
-- busted tests run it with plain `lua`. Do not add pandoc API calls here; they
-- would break the tests. (Same contract as epub-font-paths.lua.)
--
-- Usage (build): pandoc lua .pandoc/filters/lib/list-builtin-fonts.lua
-- Usage (test):  lua .pandoc/filters/lib/list-builtin-fonts.lua

local script_dir = arg[0]:match("(.*/)")
-- Bootstrap the loader (pandoc-free) so font-registry acquires its deps via
-- ks_require exactly as inside a filter. filters_dir is the parent of lib/,
-- without a trailing slash (the loader's join expects that).
local filters_dir = arg[0]:match("(.*)/lib/[^/]*$")
dofile(script_dir .. "loader.lua")(filters_dir)
local registry = ks_require("font-registry")

for _, rel in ipairs(registry.builtin_font_files()) do
  print(rel)
end
