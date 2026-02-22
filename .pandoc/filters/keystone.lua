---@diagnostic disable: undefined-global
-- keystone.lua
-- Validates and enriches metadata for the Keystone project
--
-- Environment (set by publish.sh):
--   KEYSTONE_CSS_FONTS — path for the generated font CSS stylesheet

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration.md § Path Resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

local font_registry = dofile(path.join({ script_dir, "lib", "font-registry.lua" }))
local env_io = dofile(path.join({ script_dir, "lib", "env-io.lua" }))

-- Selective EPUB embedding: only fonts actually referenced in the document
-- get @font-face CSS and --epub-embed-font flags. The Div/Span walkers
-- populate this set so inject_font_stylesheet() can build the used_fonts set.
--
-- Traversal order guarantee: Pandoc's default typewise traversal calls
-- Inline element functions, then Block element functions, then Meta.
-- Span and Div walkers always fire before Meta() within a single filter.
-- Reference: https://pandoc.org/lua-filters.html#traversal-order
local _used_font_families = {}

-- ── Local helpers ───────────────────────────────────────────────────

local function get_today()
  return os.date("%B %d, %Y")
end

local function get_date_as_MetaInlines()
  return pandoc.MetaInlines{pandoc.Str(get_today())}
end

local function get_keystonerights(meta)
  local val = pandoc.utils.stringify(meta["footer-copyright"] or "auto")

  if val == "disabled" then
    return "" -- disables the macro (renders nothing)
  end

  local text;
  if val == "auto" then
    local author = meta.author and pandoc.utils.stringify(meta.author) or "Unknown"
    local year = os.date("%Y")

    text = string.format("© %s %s. All rights reserved.", year, author)
  else
    text = val
  end

  return pandoc.write(pandoc.Pandoc({pandoc.Plain{pandoc.Str(text)}}), "latex")
end

-- ── Meta step functions ─────────────────────────────────────────────

-- Validate that all required metadata fields are present.
-- Halts with an error listing missing fields.
local function validate_required_fields(meta)
  local required_fields = {
    common = {
      "title",
      "author",
    },
    book = {
      "description",
    }
  }

  local missing = {}

  local required = {}
  for _, key in ipairs(required_fields.common) do
    table.insert(required, key)
  end

  local docclass = meta["documentclass"] and pandoc.utils.stringify(meta["documentclass"]) or "book"
  if required_fields[docclass] then
    for _, key in ipairs(required_fields[docclass]) do
      table.insert(required, key)
    end
  end

  for _, key in ipairs(required) do
    if not meta[key] then
      table.insert(missing, key .. (docclass ~= "common" and " (required for " .. docclass .. ")" or ""))
    end
  end

  if #missing > 0 then
    io.stderr:write("ERROR: Missing required metadata fields:\n")
    for _, key in ipairs(missing) do
      io.stderr:write("  - " .. key .. "\n")
    end

    error("missing required metadata fields")
  end
end

-- Inject the current date if "auto" is specified,
-- or remove the date metadata if set to "disabled".
local function enrich_date(meta)
  if meta.date then
    local date_value = pandoc.utils.stringify(meta.date)
    if date_value == "auto" then
      meta.date = get_date_as_MetaInlines()
    elseif date_value == "disabled" then
      meta.date = nil
    end
  end
end

-- Strip empty cover-image to prevent Pandoc EPUB crash.
-- An empty string or YAML null (including ~) causes Pandoc to error when
-- building EPUB. Whitespace-only values are trimmed as a precaution.
-- Removing the field entirely lets the build proceed without a cover.
local function sanitize_cover_image(meta)
  if meta["cover-image"] then
    local val = pandoc.utils.stringify(meta["cover-image"]):match("^%s*(.-)%s*$")
    if val == "" then
      meta["cover-image"] = nil
    end
  end
end

-- Inject font preamble into header-includes via font_registry.latex_preamble().
-- If fontfamily is a registry key, nils out meta.fontfamily so the Pandoc
-- template doesn't emit \usepackage{} (backward compatible).
-- Returns the original fontfamily string for downstream use.
local function inject_latex_font_preamble(meta)
  local fontfamily = meta.fontfamily and pandoc.utils.stringify(meta.fontfamily) or nil

  local preamble, consumed = font_registry.latex_preamble(fontfamily)
  if consumed then
    meta.fontfamily = nil
  end

  meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}

  if preamble ~= "" then
    table.insert(meta["header-includes"],
      pandoc.RawBlock("latex", preamble))
  end

  return fontfamily
end

-- Inject \keystonerights macro into header-includes for footer use.
local function inject_latex_footer_rights(meta)
  table.insert(meta["header-includes"],
    pandoc.RawBlock("latex", "\\newcommand{\\keystonerights}{" .. get_keystonerights(meta) .. "}"))
end

-- Generate CSS stylesheet for EPUB/HTML and add it to the css metadata
-- list so Pandoc links it from every XHTML page. header-includes only
-- reaches the title page in EPUB — the css list (see book.yaml) is the
-- correct injection point for styles that must apply to chapter content.
local function inject_font_stylesheet(meta, fontfamily)
  local used_fonts = font_registry.build_used_fonts(fontfamily, _used_font_families)

  local css_text = font_registry.css_stylesheet(fontfamily, FORMAT, used_fonts)
  if css_text then
    local css_path = env_io.write_file("KEYSTONE_CSS_FONTS", css_text)
    meta.css = meta.css or pandoc.MetaList{}
    table.insert(meta.css, pandoc.MetaString(css_path))
  end
end

-- ── Pandoc filter entry points ──────────────────────────────────────

function Div(el)
  if el.classes:includes("font") and el.attributes["family"] then
    _used_font_families[el.attributes["family"]:lower()] = true
  end
end

function Span(el)
  if el.classes:includes("font") and el.attributes["family"] then
    _used_font_families[el.attributes["family"]:lower()] = true
  end
end

function Meta(meta)
  -- All formats: metadata enrichment
  validate_required_fields(meta)
  enrich_date(meta)
  sanitize_cover_image(meta)

  -- LaTeX preamble (consumed by all formats)
  local fontfamily = inject_latex_font_preamble(meta)
  inject_latex_footer_rights(meta)

  -- EPUB / HTML only: font stylesheet
  if FORMAT:match("epub") or FORMAT:match("html") then
    inject_font_stylesheet(meta, fontfamily)
  end

  return meta
end
