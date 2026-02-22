-- epub-font-paths.lua — Print font paths for EPUB embedding (content-aware)
--
-- Reads metadata and pre-scanned content font keys to determine which registry
-- fonts are actually used, then prints one absolute path per line for each font
-- variant. System fonts (no path) are skipped — they use CSS fallback only.
--
-- Content font keys come from the file at KEYSTONE_FONT_SCAN_OUTPUT, written
-- by the font-scan.lua Pandoc filter (AST walk for .font Div/Span elements).
-- publish.sh owns the temp file path — both scripts read it from the environment.
-- This replaced raw text pattern matching on chapter files — the AST walk
-- correctly ignores family= references inside code blocks and prose.
--
-- Called by publish.sh to generate --epub-embed-font flags. This keeps the
-- registry as the single source of truth for font paths.
--
-- IMPORTANT: This script uses only standard Lua — no pandoc module. publish.sh
-- invokes it via `pandoc lua` (as a convenient Lua interpreter), but busted
-- tests run it with plain `lua` (the interpreter available in ci-tools). Do not
-- add pandoc API calls here; they will break the busted tests.
--
-- Environment (set by publish.sh):
--   KEYSTONE_FONT_SCAN_OUTPUT — path to the content font keys file
--
-- Usage (production): pandoc lua filters/lib/epub-font-paths.lua <metadata-yaml>
-- Usage (test):       lua src/runtime/.pandoc/filters/lib/epub-font-paths.lua <metadata-yaml>

local script_dir = arg[0]:match("(.*/)")
local registry = dofile(script_dir .. "font-registry.lua")
local env_io = dofile(script_dir .. "env-io.lua")

-- Collect used font-family keys from inputs.
local used = {}

-- 1. Read fontfamily from metadata YAML (simple pattern match on well-structured YAML).
local metadata_path = arg[1]
if metadata_path then
  local f = io.open(metadata_path, "r")
  if f then
    local text = f:read("*a")
    f:close()
    local fontfamily = text:match("\nfontfamily:%s*([%w%-]+)")
        or text:match("^fontfamily:%s*([%w%-]+)")
    if fontfamily then
      fontfamily = fontfamily:lower()
      if registry.fonts[fontfamily] then
        used[fontfamily] = true
        -- Expand sans companion
        local companion = registry.fonts[fontfamily].sans
        if companion and registry.fonts[companion] then
          used[companion] = true
        end
      end
    end
  end
end

-- 2. Read content font keys from pre-scan temp file (written by font-scan.lua).
local content_keys_path = env_io.require_env("KEYSTONE_FONT_SCAN_OUTPUT")
local cf = io.open(content_keys_path, "r")
if cf then
  for line in cf:lines() do
    local key = line:match("^%s*(.-)%s*$")
    if key and key ~= "" and registry.fonts[key] then
      used[key] = true
    end
  end
  cf:close()
end

-- 3. Output absolute paths for all variants of each used font.
for key in pairs(used) do
  local main = registry.fonts[key].main
  if main.path then
    print(main.path .. main.file)
    if main.bold then print(main.path .. main.bold) end
    if main.italic then print(main.path .. main.italic) end
    if main.bold_italic then print(main.path .. main.bold_italic) end
  end
end
