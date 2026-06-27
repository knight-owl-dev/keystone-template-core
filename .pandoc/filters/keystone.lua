---@diagnostic disable: undefined-global
-- keystone.lua — Metadata validation, enrichment, and style injection
--
-- Second filter in the pipeline (after shortcuts, before divs).
-- Validates required fields, enriches date/cover-image metadata,
-- injects font and code-theme styles into header-includes and meta.css.
--
-- Div/Span walkers collect font-family references so Meta() can build
-- the selective EPUB font embedding set (see _used_font_families).
--
-- Environment (set by publish.sh):
--   KEYSTONE_CSS_FONTS — path for the generated font CSS stylesheet

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration/README.md#path-resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

-- Install the memoized module loader, then acquire KAST. See
-- docs/pandoc-integration/kast.md.
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")

local format_registry = ks_require("format-registry")
local font_registry = ks_require("font-registry")
local code_theme_registry = ks_require("code-theme-registry")
local env_io = ks_require("env-io")
local font_aware = ks_require("font-aware-classes")
local ns = ks_require("handler-namespace")

-- Resolve FORMAT once at load time — all downstream calls use the canonical key
local FORMAT_KEY = format_registry.resolve_key(FORMAT)

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
  return kast.MetaInlines({ kast.Str(get_today()) })
end

-- ── Required fields ─────────────────────────────────────────────────
-- Validation rules split between this filter and each target yaml:
--
-- Common fields apply to every target unconditionally and live here.
-- Per-target fields live alongside the documentclass and preamble in
-- the target's metadata yaml under `keystone-required-fields:` — that
-- way the target yaml is the single source of truth for the target
-- contract, and adding a new target is one file.
--
-- Adding a new target that requires "abstract" automatically gets the
-- abstract-to-description EPUB bridge — no second place to update.

local common_required_fields = {
  "title",
  "author",
}

-- Read the per-target required-fields list from metadata.
-- Each target yaml declares what it needs beyond the common pair via
-- `keystone-required-fields:`. Returns a plain Lua list of strings;
-- Pandoc wraps each item as MetaInlines so we stringify on the way out.
local function target_required_fields(meta)
  local list = meta["keystone-required-fields"]
  if not list then return {} end
  local result = {}
  for _, entry in ipairs(list) do
    table.insert(result, kast.meta.stringify(entry))
  end
  return result
end

-- True if the active target requires <field> (declared in its yaml).
local function target_requires(meta, field)
  for _, key in ipairs(target_required_fields(meta)) do
    if key == field then return true end
  end
  return false
end

-- ── Meta step functions ─────────────────────────────────────────────

-- Validate that all required metadata fields are present.
-- Halts with an error listing missing fields. The active target's
-- name (its documentclass) is appended to per-target field errors
-- so the diagnostic points at the yaml the rule came from.
--
-- Uses kast.meta.is_blank to also reject bare YAML keys, YAML null,
-- and whitespace-only values — Pandoc surfaces those as non-nil Meta
-- values that stringify empty, which raw `not meta[key]` would let
-- through. Behavior matches the rest of the filter (cover-image,
-- subject, description bridges all use is_blank).
local function validate_required_fields(meta)
  local missing = {}

  for _, key in ipairs(common_required_fields) do
    if kast.meta.is_blank(meta[key]) then
      table.insert(missing, key)
    end
  end

  local docclass = kast.meta.stringify(meta["documentclass"])
  if docclass == "" then docclass = "book" end
  for _, key in ipairs(target_required_fields(meta)) do
    if kast.meta.is_blank(meta[key]) then
      table.insert(missing, key .. " (required for " .. docclass .. ")")
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

-- Bridge abstract to description for EPUB Dublin Core metadata.
-- When the active target requires abstract and the user provided it
-- but left description blank, copy abstract into description so Pandoc
-- populates dc:description in the EPUB package document.
--
-- Book targets are intentionally excluded — description is their own
-- required field, so there is nothing to bridge from. A book author
-- who omits description is meant to see the validation error, not a
-- silent fallback. The exclusion is implicit: book/scrbook target
-- yamls declare description (not abstract) in keystone-required-fields,
-- so target_requires(meta, "abstract") returns false for them.
--
-- "Blank" goes through kast.meta.is_blank so a template-supplied bare key
-- (`description:` with no value) does not falsely look set.
local function bridge_abstract_to_description(meta)
  if target_requires(meta, "abstract")
      and not kast.meta.is_blank(meta["abstract"])
      and kast.meta.is_blank(meta["description"]) then
    meta["description"] = meta["abstract"]
  end
end

-- Bridge description to subject for the PDF /Subject field.
-- Pandoc's default LaTeX template populates /Subject from `subject:` only.
-- description: is the canonical author-facing summary field, so when a user
-- provides it but leaves subject blank, copy it across so PDF readers and
-- macOS Finder Get Info see meaningful content. Class-agnostic: both fields
-- are universal Pandoc metadata, so this fires for every documentclass.
--
-- Order matters: this runs after bridge_abstract_to_description so the
-- chain abstract → description → subject works in one pass for article/report.
-- "Blank" goes through kast.meta.is_blank so the template's bare `subject:` key
-- does not block the bridge.
local function bridge_description_to_subject(meta)
  if meta["description"] and kast.meta.is_blank(meta["subject"]) then
    meta["subject"] = meta["description"]
  end
end

-- Inject the current date if "auto" is specified,
-- or remove the date metadata if set to "disabled".
local function enrich_date(meta)
  if meta.date then
    local date_value = kast.meta.stringify(meta.date)
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
  if kast.meta.is_blank(meta["cover-image"]) then
    meta["cover-image"] = nil
  end
end

-- Render the document font family for the active format. The fontfamily
-- metadata value is the single input; each format consumes it differently,
-- so the format branches live inside here (like inject_justify/inject_indent)
-- and Meta() calls this without branching:
--
--   TeX: emit the \setmainfont/\newfontfamily preamble into header-includes.
--        When fontfamily is a registry key the preamble owns the font setup,
--        so nil out meta.fontfamily to stop Pandoc's template also emitting
--        \usepackage{} (backward compatible). A RawBlock("latex") that non-TeX
--        writers would silently drop — hence the gate, not a writer no-op.
--   CSS: generate the @font-face stylesheet (EPUB/HTML) and link it via the
--        css metadata list, embedding only referenced fonts. header-includes
--        only reaches the title page in EPUB; the css list (see book.yaml)
--        applies to every XHTML page.
--
-- DOCX/ODT match neither branch — their reference-doc variants own fonts.
local function inject_fonts(meta)
  local fontfamily = kast.meta.stringify(meta.fontfamily)
  if fontfamily == "" then fontfamily = nil end

  if format_registry.uses_tex(FORMAT_KEY) then
    local preamble, consumed = font_registry.latex_preamble(fontfamily)
    if consumed then
      meta.fontfamily = nil
    end
    if preamble ~= "" then
      kast.meta.add_header_include(meta, preamble)
    end
  end

  if format_registry.uses_css(FORMAT_KEY) then
    local used_fonts = font_registry.build_used_fonts(fontfamily, _used_font_families)
    local css_text = font_registry.css_stylesheet(fontfamily, format_registry.embeds_fonts(FORMAT_KEY), used_fonts)
    if css_text then
      local css_path = env_io.write_file("KEYSTONE_CSS_FONTS", css_text)
      kast.meta.add_css(meta, css_path)
    end
  end
end

-- Activate the draft watermark when draft metadata is set. Pure
-- orchestration of the dynamic values: this resolves the text (DRAFT vs
-- custom) and the scale (validation + the auto-shrink that fits longer
-- text to the page diagonal; draft-scale overrides the automatic value),
-- then emits those two as neutral \keystone* macros and pulls in the
-- package wiring. The LaTeX mechanism lives in includes/draft-watermark.tex,
-- mirroring how page-furniture.lua feeds its layout include.
-- TeX-only: draftwatermark has no CSS equivalent, so non-TeX formats skip
-- the whole concern (including scale validation), like inject_note_placement.
local function inject_draft_watermark(meta)
  local val = kast.meta.stringify(meta.draft)
  if val == "" or val == "disabled" then return end
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local text = (val == "enabled") and "DRAFT" or val

  local scale_str = kast.meta.stringify(meta["draft-scale"])
  local scale
  if scale_str ~= "" then
    scale = tonumber(scale_str)
    if not scale or scale <= 0 then
      error("draft-scale must be a positive number, got: " .. scale_str)
    end
  else
    -- "DRAFT" (5 chars) fits the page diagonal at scale 1.0;
    -- longer text shrinks proportionally to stay within bounds
    local reference_length = 5
    scale = math.min(1, reference_length / #text)
  end

  kast.meta.add_header_include(meta, table.concat({
    kast.latex.newcommand("keystonewatermarktext", kast.latex.inlines({ kast.Str(text) })),
    -- scale is numeric, so no LaTeX escaping is needed on the body
    kast.latex.newcommand("keystonewatermarkscale", string.format("%.2f", scale)),
    kast.latex.input(".pandoc/includes/draft-watermark.tex"),
  }, "\n"))
end

-- Control text justification across all output formats.
--
-- EPUB readers disagree on the default — Apple Books uses ragged-right.
-- Explicit CSS normalizes behavior so the output matches the author's
-- intent regardless of reader.
--
-- Resolution logic lives in resolve-metadata.sh; this filter reads
-- the resolved boolean from KEYSTONE_JUSTIFY (0 = ragged-right, 1 = justified).
-- LaTeX: inject ragged2e's \RaggedRight when disabled (justified is the LaTeX
-- default). \RaggedRight preserves hyphenation, unlike the built-in
-- \raggedright which disables it and produces awkward breaks in narrow layouts.
-- The ragged2e package is loaded globally in base-packages.tex (shared with
-- the align handler), so here we only issue the command.
-- CSS:   always inject body text-align so every reader agrees.
local function inject_justify(meta)
  local val = env_io.require_env("KEYSTONE_JUSTIFY")
  local disabled = val == "0"

  if disabled and format_registry.uses_tex(FORMAT_KEY) then
    kast.meta.add_header_include(meta, "\\RaggedRight")
  end

  if format_registry.uses_css(FORMAT_KEY) then
    local align = disabled and "left" or "justify"
    local css_path = env_io.write_file("KEYSTONE_CSS_JUSTIFY",
      "body { text-align: " .. align .. "; }\n")
    kast.meta.add_css(meta, css_path)
  end
end

-- Control first-line paragraph indentation across all output formats.
--
-- Resolution logic lives in resolve-metadata.sh; this filter reads
-- the resolved boolean from KEYSTONE_INDENT (0 = no indent, 1 = indented).
-- PDF: set meta.indent so Pandoc's default template preserves/zeroes \parindent.
-- CSS: inject p + p { text-indent: var(--ks-indent); } with heading resets when enabled.
-- DOCX/ODT: no action needed (reference doc variants handle it).
local function inject_indent(meta)
  local val = env_io.require_env("KEYSTONE_INDENT")
  local enabled = val == "1"

  if format_registry.uses_tex(FORMAT_KEY) then
    meta.indent = enabled
  end

  if format_registry.uses_css(FORMAT_KEY) then
    local css
    if enabled then
      css = "p + p { text-indent: var(--ks-indent); }\n"
        .. "h1 + p, h2 + p, h3 + p, h4 + p, h5 + p, h6 + p { text-indent: 0; }\n"
    else
      -- Zero out the custom property so handlers (vspace, etc.) that
      -- reference var(--ks-indent) don't reintroduce indentation.
      css = ":root { --ks-indent: 0; }\n"
    end
    local css_path = env_io.write_file("KEYSTONE_CSS_INDENT", css)
    kast.meta.add_css(meta, css_path)
  end
end

-- Inject code-theme TeX and CSS into metadata. The registry owns the
-- resolution and injection logic; we just wire in the dependencies.
local function inject_code_theme(meta)
  code_theme_registry.inject(meta, format_registry.uses_css(FORMAT_KEY), path.join({ script_dir, "code-themes" }), {
    list_directory = pandoc.system.list_directory,
    path_join = path.join,
    env_io = env_io,
  })
end

-- Activate endnote placement when keystone-note-placement is "endnotes".
-- Pure orchestration: the LaTeX mechanism (package load, \footnote alias,
-- heading) lives in includes/endnotes.tex; this only decides whether to
-- pull it in, mirroring how page-furniture.lua drives its layout include.
-- PDF-only — EPUB notes are already section-end, and a RawBlock("latex")
-- is dropped by non-TeX writers, so the marker in Pandoc() is gated too.
local function inject_note_placement(meta)
  local placement = kast.meta.stringify(meta["keystone-note-placement"])
  if placement ~= "endnotes" or not format_registry.uses_tex(FORMAT_KEY) then return end

  kast.meta.add_header_include(meta, kast.latex.input(".pandoc/includes/endnotes.tex"))
end

-- ── Pandoc filter entry points ──────────────────────────────────────

function Div(el)
  local value = font_aware.family_value(el, ns)
  if value then
    _used_font_families[value:lower()] = true
  end
end

function Span(el)
  local value = font_aware.family_value(el, ns)
  if value then
    _used_font_families[value:lower()] = true
  end
end

function Meta(meta)
  -- All formats: metadata enrichment
  validate_required_fields(meta)
  bridge_abstract_to_description(meta)
  bridge_description_to_subject(meta)
  enrich_date(meta)
  sanitize_cover_image(meta)

  -- Per-format style injection — each resolves its own format gating
  inject_fonts(meta)
  inject_draft_watermark(meta)
  inject_justify(meta)
  inject_indent(meta)
  inject_code_theme(meta)
  inject_note_placement(meta)

  return meta
end

-- Place the endnote collection marker as the final body block when
-- keystone-note-placement is "endnotes" (PDF only — see inject_note_placement).
-- This is the filter's only whole-document pass; it runs after Meta(), so
-- doc.meta already carries the resolved placement. The marker lands before
-- citeproc's #refs bibliography: Lua filters run ahead of --citeproc, so the
-- collected endnotes precede the reference list at end-of-document.
--
-- Why the marker is emitted here, not in includes/endnotes.tex like the rest of
-- the mechanism: it is a positional body block — it must be the LAST block so
-- notes collect after all content — so it is an AST append, not a preamble
-- include. A .tex file cannot express "append after the document body". The
-- package load, \footnote alias, and the flush macro itself live in the
-- include; only this placement-dependent call has to be emitted from the filter.
-- \keystoneflushendnotes is \theendnotes guarded by a note-count check, so a
-- book with no notes (book targets default to endnotes) emits nothing.
function Pandoc(doc)
  local placement = kast.meta.stringify(doc.meta["keystone-note-placement"])
  if placement == "endnotes" and format_registry.uses_tex(FORMAT_KEY) then
    table.insert(doc.blocks, kast.RawBlock("latex", "\\keystoneflushendnotes"))
  end
  return doc
end
