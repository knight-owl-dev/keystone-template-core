-- epub-font-paths.lua — Print font paths for EPUB embedding (content-aware)
--
-- Determines which registry fonts are actually used — the document body and
-- code fonts plus any referenced in content — then prints one absolute path per
-- line for each present variant.
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
--
-- Usage (production): pandoc lua filters/lib/epub-font-paths.lua
-- Usage (test):       lua src/runtime/.pandoc/filters/lib/epub-font-paths.lua

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

-- 3. Output absolute paths for all variants of each used font, in sorted key
-- order so the emitted --epub-embed-font list is deterministic across runs.
for key in collections.sorted_pairs(used) do
  local main = registry.fonts[key].main
  print(main.path .. main.file)
  if main.bold then print(main.path .. main.bold) end
  if main.italic then print(main.path .. main.italic) end
  if main.bold_italic then print(main.path .. main.bold_italic) end
end
