-- epub-font-paths.lua — Record what an EPUB embeds (content-aware)
--
-- Determines which registry fonts are actually used — the document body and
-- code fonts plus any referenced in content — then writes one row per file the
-- archive carries: the font variants, and the terms each of them travels under.
--
-- A row is `<source-path>\t<archive-name>`, written to the file at
-- KEYSTONE_EPUB_EMBED_ROWS. publish.sh stages each source under the name given
-- and embeds the staged file, so the name a font's license takes in the flat
-- archive is decided here, beside the registry that knows it. A file rather than
-- stdout, because publish.sh runs this as a named build stage and the stage
-- line is itself written to stdout.
--
-- Nothing here judges a declaration. Whether a font declared its terms, whether
-- the declaration is well formed, and whether two of its names could be told
-- apart are properties of the entry rather than of a build, so the registry
-- settles them once for every format. Whether the file a name points at is
-- really there is the registry's too for an author's font; for a built-in the
-- image build owns it, against the tree it staged. This pass reads what
-- survived and says where it goes.
--
-- Inputs come from the environment: this pre-scan runs before the main Pandoc
-- pass, so it has no parsed document metadata. The body font arrives via
-- KEYSTONE_FONTFAMILY, the code font via KEYSTONE_MONOFONT; content font keys
-- via the file at KEYSTONE_FONT_SCAN_OUTPUT (written by font-scan.lua, which
-- ignores family= in code and prose). publish.sh owns these env vars. This
-- keeps the registry the single source of truth for font paths.
--
-- IMPORTANT: This script uses only standard Lua — no pandoc module. publish.sh
-- invokes it via `pandoc lua` (as a convenient Lua interpreter), but busted
-- tests run it with plain `lua` (the interpreter available in ci-tools). Do not
-- add pandoc API calls here; they will break the busted tests.
--
-- Environment (set by publish.sh):
--   KEYSTONE_FONTFAMILY       — document body font value (empty when unset)
--   KEYSTONE_MONOFONT         — document code font value (empty when unset)
--   KEYSTONE_FONT_SCAN_OUTPUT — path to the content font keys file
--   KEYSTONE_EPUB_EMBED_ROWS  — path to write the rows to
--
-- Usage (production): pandoc lua .pandoc/filters/lib/epub-font-paths.lua
-- Usage (test):       lua .pandoc/filters/lib/epub-font-paths.lua

local script_dir = arg[0]:match("(.*/)")
-- Bootstrap the loader (pandoc-free) so libs acquire their deps via ks_require
-- exactly as they do inside a filter — font-registry ks_requires the errors
-- lib, so it can't be loaded by a bare dofile. filters_dir is the parent of
-- lib/, without a trailing slash (the loader's join expects that).
local filters_dir = arg[0]:match("(.*)/lib/[^/]*$")
dofile(script_dir .. "loader.lua")(filters_dir)
local registry = ks_require("font-registry")
local env_io = ks_require("env-io")
local text = ks_require("text")
local collections = ks_require("collections")

-- Collect used font-family keys from inputs.
local used = {}

-- 1. Resolve the document font from KEYSTONE_FONTFAMILY (empty/unset → owned
-- default) through the shared registry rule. optional_env, since unset is a
-- valid state here that resolves to the default; require_env would reject it.
local family_key = registry.resolve_family(env_io.optional_env("KEYSTONE_FONTFAMILY"))
used[family_key] = true
-- Expand sans companion
local companion = registry.fonts[family_key].sans
if companion and registry.fonts[companion] then
  used[companion] = true
end

-- Code font from KEYSTONE_MONOFONT (empty/unset → owned mono default), through
-- the same registry rule.
local mono_key = registry.resolve_family(
  env_io.optional_env("KEYSTONE_MONOFONT"), registry.mono_default)
used[mono_key] = true

-- 2. Read content font keys from pre-scan temp file (written by font-scan.lua).
local content_keys_path = env_io.require_env("KEYSTONE_FONT_SCAN_OUTPUT")
local cf = io.open(content_keys_path, "r")
if cf then
  for line in cf:lines() do
    local key = text.trim(line)
    if key and key ~= "" and registry.fonts[key] then
      used[key] = true
    end
  end
  cf:close()
end

-- 3. A row per embedded file, in sorted key order so the emitted
-- --epub-embed-font list is deterministic across runs. A font keeps its own
-- basename; its license takes a name derived from it, and every variant
-- carries its own copy, so nothing has to work out which text covers which
-- file. Why the terms have to travel at all is at
-- https://keystone.knight-owl.dev/errors/missing-font-license/
local rows = {}

for key in collections.sorted_pairs(used) do
  local main = registry.fonts[key].main

  for _, declared in ipairs(registry.variant_files(main)) do
    rows[#rows + 1] = main.path .. declared.file .. "\t" .. declared.file
    for _, license in ipairs(registry.license_files(main)) do
      rows[#rows + 1] = main.path .. license .. "\t"
        .. registry.license_archive_name(declared.file, license)
    end
  end
end

env_io.write_file("KEYSTONE_EPUB_EMBED_ROWS", table.concat(rows, "\n") .. "\n")

