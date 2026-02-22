-- font-scan.lua — Pandoc filter that walks the AST for content font references
--
-- Pre-scans chapter content for .font Div/Span elements with family= attributes,
-- collecting registry-valid font keys. Writes one key per line to the path in
-- KEYSTONE_FONT_SCAN_OUTPUT. An AST walk correctly ignores family= references
-- inside fenced code blocks, inline code, and prose — only actual .font elements
-- are detected.
--
-- This filter is format-agnostic. publish.sh invokes it on demand for formats
-- that need pre-Pandoc font knowledge (currently EPUB — for --epub-embed-font
-- flags). Formats like PDF don't pay the pre-scan cost.
--
-- Called by publish.sh as a Pandoc filter:
--   pandoc --lua-filter=.pandoc/filters/font-scan.lua chapters... --to=native -o /dev/null
--
-- Environment (set by publish.sh):
--   KEYSTONE_FONT_SCAN_OUTPUT — output path for the content font keys file

local path = pandoc.path

local script_dir = path.directory(PANDOC_SCRIPT_FILE)
local registry = dofile(path.join({ script_dir, "lib", "font-registry.lua" }))
local env_io = dofile(path.join({ script_dir, "lib", "env-io.lua" }))

local used = {}

local function collect_font(el)
  if el.classes:includes("font") and el.attributes["family"] then
    local key = el.attributes["family"]:lower()
    if registry.fonts[key] then
      used[key] = true
    end
  end
end

function Div(el)
  collect_font(el)
end

function Span(el)
  collect_font(el)
end

function Meta()
  local keys = {}
  for key in pairs(used) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  if #keys > 0 then
    env_io.write_file("KEYSTONE_FONT_SCAN_OUTPUT",
      table.concat(keys, "\n") .. "\n")
  end
end
