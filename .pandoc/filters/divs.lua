---@diagnostic disable: undefined-global
-- divs.lua — Single-pass dispatcher for fenced-div, span, and header Lua handlers
--
-- Replaces separate div-*.lua filters with one AST traversal.
-- Each subdirectory in divs/ represents one handler type. The directory
-- name is the CSS class name. Well-known filenames inside each:
--
--   handler.lua   (required) — returns a format-hook table (see below)
--   macros.tex    (optional) — LaTeX preamble injected via header-includes
--   style.css     (optional) — CSS linked via meta.css
--   (loaded only when the target format consumes them — see format-registry.lua)
--
-- Format-hook contract:
--   { div = { latex = fn, epub = fn } }  — format-keyed hook tables
--   { span = { latex = fn, html = fn, default = fn } }
--   { header = { latex = fn } }          — class-routed headings
--   { div = hooks, global = { Figure = { latex = fn, default = fn } } }
--
-- The dispatcher auto-discovers subdirectories at startup, loads handlers,
-- and routes Div, Span, and Header elements by matching CSS class names.
-- Header is the third element type this dispatcher routes by class (after
-- Div and Span): `# Foo {.unnumbered}` carries its class just like `::: foo`
-- does, so the same class→handler routing applies. This is distinct from
-- `global`, which intercepts an element type with no class to route on
-- (e.g. a plain-image Figure). Class-bearing semantic → route; classless
-- type-wide → global.
--
-- Adding a new handler: create divs/<class-name>/ with handler.lua
-- and optional macros.tex / style.css. No registration needed.
--
-- Environment (set by publish.sh):
--   KEYSTONE_CSS_DIVS — path for the combined handler CSS stylesheet

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration/README.md#path-resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end
local divs_dir = path.join({ script_dir, "divs" })

-- Install the memoized module loader first so this filter and the handlers it
-- loads (into the same Lua state) acquire libs via the global ks_require(...)
-- instead of re-dofile'ing them. The call's side effect is the point — it sets
-- _G.ks_require. See docs/pandoc-integration/kast.md.
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")

local env_io = ks_require("env-io")
local handler_classes_lib = ks_require("handler-classes")
local format_registry = ks_require("format-registry")
local ns = ks_require("handler-namespace")

-- Resolve FORMAT once at load time — all routing uses this canonical key
local FORMAT_KEY = format_registry.resolve_key(FORMAT)

-- Skip reading co-located style files the current writer ignores
local needs_tex = format_registry.uses_tex(FORMAT_KEY)
local needs_css = format_registry.uses_css(FORMAT_KEY)

-- Discover handler subdirectories and load their code + co-located style files.
local div_handlers = {}
local span_handlers = {}
local header_handlers = {}
local global_handlers = {}
local tex_blocks = {}
local css_blocks = {}

local discovered = handler_classes_lib.discover(
  divs_dir, pandoc.system.list_directory, path.join)

-- Sort for deterministic style concatenation order
local sorted_classes = {}
for class_name in pairs(discovered) do
  sorted_classes[#sorted_classes + 1] = class_name
end
table.sort(sorted_classes)

for _, class_name in ipairs(sorted_classes) do
  local handler_path = path.join({ divs_dir, class_name, "handler.lua" })
  local raw = dofile(handler_path)
  if type(raw) ~= "table" then
    error("divs/" .. class_name .. "/handler.lua must return a table, got " .. type(raw))
  end
  local entry = raw

  if entry.div then div_handlers[class_name] = entry.div end
  if entry.span then span_handlers[class_name] = entry.span end
  if entry.header then header_handlers[class_name] = entry.header end
  if entry.global then
    for element_type, hook_table in pairs(entry.global) do
      if not global_handlers[element_type] then
        global_handlers[element_type] = hook_table
      end
    end
  end

  if needs_tex then
    local tex_path = path.join({ divs_dir, class_name, "macros.tex" })
    local fh = io.open(tex_path, "r")
    if fh then
      table.insert(tex_blocks, fh:read("*a"))
      fh:close()
    end
  end

  if needs_css then
    local css_path = path.join({ divs_dir, class_name, "style.css" })
    local fh = io.open(css_path, "r")
    if fh then
      table.insert(css_blocks, fh:read("*a"))
      fh:close()
    end
  end
end

-- Wire global element handlers into Pandoc filter entry points.
-- First handler registered for a given element type wins (alphabetical order).
for element_type, hook_table in pairs(global_handlers) do
  _G[element_type] = function(el)
    local handler = format_registry.resolve_hook(hook_table, FORMAT_KEY)
    if handler then return handler(el) end
  end
end

-- Inject co-located styles into document metadata.
-- Styles were collected at module init (before callbacks), so Div/Span
-- routing already has handler tables populated regardless of call order.
function Meta(meta)
  if #tex_blocks == 0 and #css_blocks == 0 then return end

  if #tex_blocks > 0 then
    for _, tex in ipairs(tex_blocks) do
      kast.meta.add_header_include(meta, tex)
    end
  end

  if #css_blocks > 0 then
    local combined = table.concat(css_blocks, "\n")
    local css_path = env_io.write_file("KEYSTONE_CSS_DIVS", combined)
    kast.meta.add_css(meta, css_path)
  end

  return meta
end

-- Route an element to the first matching handler for the current format.
-- Single-dispatch: the first matching handler class is authoritative — it
-- owns the element. Remaining classes are not inspected and handlers do not
-- compose or aggregate. The ks- prefix is stripped so ks-font routes to the
-- font handler. When a prefix was stripped, the element is returned even if
-- the handler declines (returns nil) — otherwise the ks- class leaks into
-- output.
local function route(el, handlers)
  for i, class in ipairs(el.classes) do
    local canonical = ns.canonical(class)
    local hooks = handlers[canonical]
    if hooks then
      local stripped = canonical ~= class
      el.classes[i] = canonical
      local handler = format_registry.resolve_hook(hooks, FORMAT_KEY)
      if handler then
        local result = handler(el)
        if result then return result end
        if stripped then return el end
        return nil
      end
      if stripped then return el end
    end
  end
end

function Div(el)    return route(el, div_handlers) end
function Span(el)   return route(el, span_handlers) end
function Header(el) return route(el, header_handlers) end
