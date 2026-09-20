-- list-builtin-font-licenses.lua — Print the license files the runtime image ships
--
-- Emits one path per line, relative to the registry's FONTS_ROOT, for the terms
-- every built-in font travels under. The counterpart to list-builtin-fonts.lua:
-- that one names the binaries, this one names what redistributing them requires.
-- .docker/fonts/licenses.copy.txt stages these paths; the image build reads
-- this list back against what landed and refuses both directions — a path
-- nothing staged, and a staged family this names no text for — so the two
-- declarations cannot drift apart unnoticed.
--
-- IMPORTANT: This script uses only standard Lua — no pandoc module. It is
-- invoked via `pandoc lua` (as a convenient Lua interpreter), but tests run it
-- with plain `lua`. Do not add pandoc API calls here; they would break the
-- tests. (Same contract as list-builtin-fonts.lua.)
--
-- Usage (build): pandoc lua .pandoc/filters/lib/list-builtin-font-licenses.lua
-- Usage (test):  lua .pandoc/filters/lib/list-builtin-font-licenses.lua

local script_dir = arg[0]:match("(.*/)")
-- Bootstrap the loader (pandoc-free) so font-registry acquires its deps via
-- ks_require exactly as inside a filter. filters_dir is the parent of lib/,
-- without a trailing slash (the loader's join expects that).
local filters_dir = arg[0]:match("(.*)/lib/[^/]*$")
dofile(script_dir .. "loader.lua")(filters_dir)
local registry = ks_require("font-registry")

for _, rel in ipairs(registry.builtin_license_files()) do
  print(rel)
end
