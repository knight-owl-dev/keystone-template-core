-- font-scan.lua — Pandoc filter that walks the AST for content font references
--
-- Pre-scans chapter content for Div/Span elements whose class maps to a
-- font-family attribute, collecting registry-valid font keys. Writes one key
-- per line to the path in KEYSTONE_FONT_SCAN_OUTPUT. Which classes are scanned
-- (and which attribute each uses) is defined by lib/font-aware-classes.lua —
-- a shared map that keeps font-scan.lua and keystone.lua in sync. An AST walk
-- correctly ignores font references inside fenced code blocks, inline code,
-- and prose.
--
-- This filter is format-agnostic. publish.sh invokes it on demand for formats
-- that need pre-Pandoc font knowledge (currently EPUB — for --epub-embed-font
-- flags). Formats like PDF don't pay the pre-scan cost.
--
-- Called by publish.sh as a Pandoc filter:
--   pandoc --lua-filter=.pandoc/filters/font-scan.lua manuscript... --to=native -o /dev/null
--
-- Environment (set by publish.sh):
--   KEYSTONE_FONT_SCAN_OUTPUT — output path for the content font keys file

local path = pandoc.path

local script_dir = path.directory(PANDOC_SCRIPT_FILE)

-- Install the memoized module loader, then acquire libs via ks_require. See
-- docs/pandoc-integration/kast.md. (No KAST here — this filter constructs no
-- AST; it only reads .font Div/Span attributes.)
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)

local registry = ks_require("font-registry")
local env_io = ks_require("env-io")
local font_aware = ks_require("font-aware-classes")
local ns = ks_require("handler-namespace")

local used = {}

local function collect_font(el)
  local value = font_aware.family_value(el, ns)
  if value then
    local key = value:lower()
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
