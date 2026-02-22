---@diagnostic disable: undefined-global
-- divs.lua — Single-pass dispatcher for fenced-div and span Lua handlers
--
-- Replaces separate div-*.lua filters with one AST traversal.
-- Each subdirectory in divs/ represents one handler type. The directory
-- name is the CSS class name. Well-known filenames inside each:
--
--   handler.lua   (required) — returns a function or table (see below)
--   macros.tex    (optional) — LaTeX preamble injected via header-includes
--   style.css     (optional) — CSS linked via meta.css (all EPUB/HTML pages)
--
-- Handler contracts:
--   function(el)               — div handler only (backward compatible)
--   { div = fn, span = fn }    — div and/or span handlers
--
-- The dispatcher auto-discovers subdirectories at startup, loads
-- handlers, and routes Div and Span elements by matching CSS class names.
--
-- Adding a new handler: create divs/<class-name>/ with handler.lua
-- and optional macros.tex / style.css. No registration needed.
--
-- Environment (set by publish.sh):
--   KEYSTONE_CSS_DIVS — path for the combined handler CSS stylesheet

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration.md § Path Resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end
local divs_dir = path.join({ script_dir, "divs" })

local env_io = dofile(path.join({ script_dir, "lib", "env-io.lua" }))

-- Expose to handlers loaded via dofile(). See docs/pandoc-integration.md § Path Resolution.
KEYSTONE_FILTERS_DIR = script_dir

-- Discover handler subdirectories and their co-located style files.
-- A subdirectory is recognized as a handler type only when it contains handler.lua.
-- This cleanly skips stray files (.DS_Store, READMEs, etc.).
local div_handlers = {}
local span_handlers = {}
local tex_blocks = {}
local css_blocks = {}

local entries = pandoc.system.list_directory(divs_dir)
table.sort(entries)

for _, entry in ipairs(entries) do
  local handler_path = path.join({ divs_dir, entry, "handler.lua" })
  local probe = io.open(handler_path, "r")
  if probe then
    probe:close()

    local class_name = entry
    local raw = dofile(handler_path)

    if type(raw) == "function" then
      -- Backward compatible: function → div handler only
      div_handlers[class_name] = raw
    elseif type(raw) == "table" then
      -- Dual contract: table with div and/or span handlers
      if raw.div then div_handlers[class_name] = raw.div end
      if raw.span then span_handlers[class_name] = raw.span end
    else
      error("divs/" .. entry .. "/handler.lua must return a function or table, got " .. type(raw))
    end

    local tex_path = path.join({ divs_dir, entry, "macros.tex" })
    local fh = io.open(tex_path, "r")
    if fh then
      table.insert(tex_blocks, fh:read("*a"))
      fh:close()
    end

    local css_path = path.join({ divs_dir, entry, "style.css" })
    fh = io.open(css_path, "r")
    if fh then
      table.insert(css_blocks, fh:read("*a"))
      fh:close()
    end
  end
end

-- Inject co-located styles into document metadata.
-- Pandoc processes Meta before Div/Span within a single filter, so styles
-- are available before any routing happens.
function Meta(meta)
  if #tex_blocks == 0 and #css_blocks == 0 then return end

  if #tex_blocks > 0 then
    meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}
    for _, tex in ipairs(tex_blocks) do
      table.insert(meta["header-includes"], pandoc.RawBlock("latex", tex))
    end
  end

  if #css_blocks > 0 then
    local combined = table.concat(css_blocks, "\n")
    local css_path = env_io.write_file("KEYSTONE_CSS_DIVS", combined)
    meta.css = meta.css or pandoc.MetaList{}
    table.insert(meta.css, pandoc.MetaString(css_path))
  end

  return meta
end

-- Route each Div to the first matching handler.
function Div(el)
  for _, class in ipairs(el.classes) do
    local handler = div_handlers[class]
    if handler then
      return handler(el)
    end
  end
end

-- Route each Span to the first matching handler.
function Span(el)
  for _, class in ipairs(el.classes) do
    local handler = span_handlers[class]
    if handler then
      return handler(el)
    end
  end
end
