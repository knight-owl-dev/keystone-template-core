---@diagnostic disable: undefined-global
-- divs.lua — Single-pass dispatcher for fenced-div Lua handlers
--
-- Replaces separate div-*.lua filters with one AST traversal.
-- Each subdirectory in divs/ represents one div type. The directory
-- name is the CSS class name. Well-known filenames inside each:
--
--   handler.lua   (required) — must return a function(el)
--   macros.tex    (optional) — LaTeX preamble injected via header-includes
--   style.css     (optional) — CSS injected via header-includes
--
-- The dispatcher auto-discovers subdirectories at startup, loads
-- handlers, and routes Div elements by matching CSS class names.
--
-- Adding a new div type: create divs/<class-name>/ with handler.lua
-- and optional macros.tex / style.css. No registration needed.

local path = pandoc.path

-- Locate the divs/ directory relative to this script.
-- PANDOC_SCRIPT_FILE may be a bare filename (when resolved via --data-dir)
-- or an absolute/relative path. Handle both cases.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end
local divs_dir = path.join({ script_dir, "divs" })

-- Discover handler subdirectories and their co-located style files.
-- A subdirectory is recognized as a div type only when it contains handler.lua.
-- This cleanly skips stray files (.DS_Store, READMEs, etc.).
local handlers = {}
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
    local handler = dofile(handler_path)
    if type(handler) ~= "function" then
      error("divs/" .. entry .. "/handler.lua must return a function, got " .. type(handler))
    end
    handlers[class_name] = handler

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
-- Pandoc processes Meta before Div within a single filter, so styles
-- are available before any div routing happens.
function Meta(meta)
  if #tex_blocks == 0 and #css_blocks == 0 then return end

  meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}

  for _, tex in ipairs(tex_blocks) do
    table.insert(meta["header-includes"], pandoc.RawBlock("latex", tex))
  end

  for _, css in ipairs(css_blocks) do
    table.insert(meta["header-includes"],
      pandoc.RawBlock("html", "<style>\n" .. css .. "</style>"))
  end

  return meta
end

-- Route each Div to the first matching handler.
function Div(el)
  for _, class in ipairs(el.classes) do
    local handler = handlers[class]
    if handler then
      return handler(el)
    end
  end
end
