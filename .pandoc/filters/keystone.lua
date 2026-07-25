---@diagnostic disable: undefined-global
-- keystone.lua — Metadata validation, enrichment, and style injection
--
-- Validates required fields and the author's fontsize; enriches date and
-- cover-image metadata; injects font and code-theme styles into
-- header-includes and meta.css. Div/Span walkers collect font-family
-- references so Meta() can build the selective EPUB font-embedding set
-- (see _used_font_families).
--
-- Runs in the Pandoc filter pipeline; publish.sh (STANDARD_FILTERS) owns the
-- filter order. This filter reads resolved KEYSTONE_* metadata values (owned
-- by resolve-metadata.sh) and writes generated CSS to the KEYSTONE_CSS_* paths
-- (set by publish.sh).

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
local errors = ks_require("errors")

local format_registry = ks_require("format-registry")
local font_registry = ks_require("font-registry")
local code_theme_registry = ks_require("code-theme-registry")
local safe_path = ks_require("safe-path")
local env_io = ks_require("env-io")
local fontsize = ks_require("fontsize")
local font_aware = ks_require("font-aware-classes")
local ns = ks_require("handler-namespace")
local collections = ks_require("collections")

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
    local lines = { "Missing required metadata fields:" }
    for _, key in ipairs(missing) do
      lines[#lines + 1] = "  - " .. key
    end
    errors.fatal(table.concat(lines, "\n"))
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
  if meta["date"] then
    local date_value = kast.meta.stringify(meta["date"])
    if date_value == "auto" then
      meta["date"] = get_date_as_MetaInlines()
    elseif date_value == "disabled" then
      meta["date"] = nil
    end
  end
end

-- Sanitize and confine cover-image.
-- Blank cases (empty string, YAML null/`~`, whitespace-only) crash Pandoc's
-- EPUB build, so drop the field entirely — the build proceeds with no cover.
-- A present value is confined to the project tree: an absolute path or `..`
-- escape would let untrusted content read outside it into the EPUB cover (#486),
-- so safe_path hard-fails those.
local function sanitize_cover_image(meta)
  if kast.meta.is_blank(meta["cover-image"]) then
    meta["cover-image"] = nil
  else
    safe_path.require_relative(kast.meta.stringify(meta["cover-image"]), "cover-image")
  end
end

-- Override `secnumdepth`: keystone caps numbering by attribution (see
-- limit_section_numbering), so the native key must not also reach LaTeX's
-- \setcounter{secnumdepth}. Cleared unconditionally — the resolved value travels
-- via KEYSTONE_SECNUMDEPTH, and non-TeX writers ignore the key.
local function strip_secnumdepth(meta)
  meta["secnumdepth"] = nil
end

-- Validate a font metadata value, warn on an unrecognized key (a consuming
-- format notes the owned fallback), and clear it from meta so no raw value
-- reaches a writer. Returns the raw value for later resolution.
local function take_font(meta, key, default_name, consumed)
  local raw = kast.meta.stringify(meta[key])
  if raw ~= "" and not font_registry.is_font(raw) then
    local msg = key .. " '" .. raw .. "' is not a registry key"
    if consumed then
      msg = msg .. "; using the default (" .. default_name .. ")"
    end
    errors.warn(msg .. ". See https://keystone.knight-owl.dev/writing/typography/")
  end
  meta[key] = nil
  return raw
end

-- Inject the document body font (fontfamily) and code font (monofont). Both are
-- validated on every target — an invalid value is an author error like a missing
-- required field. LaTeX emits a header-includes preamble; EPUB/HTML use the css
-- metadata list, since header-includes reaches only the EPUB title page (see
-- book.yaml).
local function inject_fonts(meta)
  local consumed = format_registry.uses_font(FORMAT_KEY)
  local raw_family = take_font(meta, "fontfamily", font_registry.default, consumed)
  local raw_mono = take_font(meta, "monofont", font_registry.mono_default, consumed)

  if not consumed then return end
  local fontfamily = font_registry.resolve_family(raw_family)
  local monofont = font_registry.resolve_family(raw_mono, font_registry.mono_default)

  if format_registry.uses_tex(FORMAT_KEY) then
    local preamble = font_registry.latex_preamble(fontfamily, monofont)
    if preamble ~= "" then
      kast.meta.add_header_include(meta, preamble)
    end
  end

  if format_registry.uses_css(FORMAT_KEY) then
    local used_fonts = font_registry.build_used_fonts(fontfamily, monofont, _used_font_families)
    local css_text = font_registry.css_stylesheet(
      fontfamily, monofont, format_registry.embeds_fonts(FORMAT_KEY), used_fonts)
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
  local val = kast.meta.stringify(meta["draft"])
  if val == "" or val == "disabled" then return end
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local text = (val == "enabled") and "DRAFT" or val

  local scale_str = kast.meta.stringify(meta["draft-scale"])
  local scale
  if scale_str ~= "" then
    scale = kast.meta.require_positive_number(scale_str, "draft-scale")
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
    meta["indent"] = enabled
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

-- Deliver the resolved TOC depth to PDF as metadata — PDF takes its depth from
-- metadata, not the --toc-depth flag, and base-style.tex applies the per-class
-- offset. Written for every TeX build so the default holds when the author omits
-- toc-depth. Write-only, TeX-only.
local function inject_toc_depth(meta)
  if not format_registry.uses_tex(FORMAT_KEY) then return end
  meta["toc-depth"] = kast.MetaString(env_io.require_env("KEYSTONE_TOC_DEPTH"))
end

-- The metadata key → resolved-env-var map for the hyperlink colors.
local LINK_COLOR_ENV = {
  linkcolor = "KEYSTONE_LINKCOLOR",
  urlcolor = "KEYSTONE_URLCOLOR",
  citecolor = "KEYSTONE_CITECOLOR",
  toccolor = "KEYSTONE_TOCCOLOR",
}

-- Capture the six hex digits of a #RRGGBB color (resolve-metadata.sh validated
-- the shape before exporting it).
local HEX_COLOR = "^#(%x%x%x%x%x%x)$"

-- Deliver the resolved hyperlink colors. For PDF, each #RRGGBB becomes a
-- \definecolor in the preamble plus the bare color name in its metadata key;
-- the name form is deliberate — an [HTML]{…} metadata value is escaped by the
-- LaTeX writer, so only a plain name survives interpolation into \hypersetup.
-- Other formats have the key cleared.
local function inject_link_colors(meta)
  local tex = format_registry.uses_tex(FORMAT_KEY)
  -- Sorted keys so the emitted \definecolor lines land in a stable order.
  for key in collections.sorted_pairs(LINK_COLOR_ENV) do
    local hex = tex and env_io.require_env(LINK_COLOR_ENV[key]):match(HEX_COLOR)
    if hex then
      local name = "keystone" .. key
      kast.meta.add_header_include(meta, "\\definecolor{" .. name .. "}{HTML}{" .. hex:upper() .. "}")
      meta[key] = kast.MetaString(name)
    else
      meta[key] = nil
    end
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

-- Validate the line-spacing multiplier. linestretch is a raw Pandoc passthrough
-- (default template -> setspace's \setstretch), so a bad value silently renders
-- overlapping lines (zero/negative leading) or aborts xelatex cryptically.
-- require_positive_number rejects both — including the Lua-lax hex/scientific/
-- overflow forms \setstretch can't parse (see its docstring), which matters
-- here because the author's value passes through untouched. TeX-only: EPUB
-- leaves leading to the reading system and DOCX/ODT ignore the variable, so
-- only the PDF path consumes — and so validates — it.
local function validate_linestretch(meta)
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local value = kast.meta.stringify(meta["linestretch"])
  if value ~= "" then
    kast.meta.require_positive_number(value, "linestretch")
  end
end

-- Enforce the author's fontsize against the set its target declares via
-- keystone-fontsize-set (see lib/fontsize.lua, which owns why the sets differ).
-- fontsize is an unchecked Pandoc passthrough, so an unsupported size reaches
-- LaTeX and fails silently; here it warns — a hard fail under
-- KEYSTONE_WARNINGS_AS_ERRORS. The fallback is deterministic: a malformed size
-- resets to the default, a well-formed but disallowed one to the nearest
-- allowed size. TeX-only: no documentclass, no fontsize.
local function validate_fontsize(meta)
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local value = kast.meta.stringify(meta["fontsize"])
  if value == "" then return end

  -- No declared set (e.g. an author-supplied unknown documentclass) means no
  -- contract to check against, so leave the value untouched.
  local set_id = kast.meta.stringify(meta["keystone-fontsize-set"])
  if set_id == "" then return end

  if not fontsize.is_valid(set_id) then
    errors.fatal("target declares unknown keystone-fontsize-set '" .. set_id
      .. "' — must be one of: " .. table.concat(fontsize.ids(), ", "))
    return
  end

  local sizes = fontsize.sizes(set_id)
  if fontsize.is_allowed(sizes, value) then return end

  local points = fontsize.points(value)
  local fallback, why
  if points then
    fallback = fontsize.nearest(sizes, points)
    why = "is not supported (allowed: " .. table.concat(sizes, ", ") .. ")"
  else
    fallback = fontsize.default
    why = "is not a valid size (use e.g. '" .. fallback .. "')"
  end

  -- Set-specific guidance (e.g. where larger sizes live) comes from the lib.
  local hint = fontsize.hint(set_id)

  errors.warn("fontsize '" .. value .. "' " .. why .. "; using " .. fallback
    .. "." .. (hint and (" " .. hint) or ""))
  meta["fontsize"] = kast.MetaString(fallback)
end

-- Cap section-numbering depth uniformly across formats. `secnumdepth: N` (author
-- heading levels, # = 1) means "number levels 1..N; deeper headings unnumbered."
-- Adding .unnumbered caps numbering in every writer — one AST pass, no LaTeX
-- counter, no per-class offset; .unlisted additionally suppresses a PDF contents
-- leak past toc-depth. Rationale and the \addcontentsline gotcha:
-- docs/pandoc-integration/latex.md § Section-numbering depth.
--
-- No-op when secnumdepth is unset (number all levels) or numbersections is off
-- (numbering off, so depth is moot). Numbering state comes from the resolved
-- KEYSTONE_NUMBERSECTIONS toggle, not doc.meta — publish.sh now gates
-- --number-sections on that toggle, so it is the single source of truth.
local function limit_section_numbering(doc)
  local secnumdepth = tonumber(env_io.require_env("KEYSTONE_SECNUMDEPTH"))
  if not secnumdepth then return end
  if env_io.require_env("KEYSTONE_NUMBERSECTIONS") == "0" then return end

  local toc_depth = tonumber(env_io.require_env("KEYSTONE_TOC_DEPTH"))
  doc.blocks = kast.walk(doc.blocks, {
    Header = function(h)
      if h.level > secnumdepth then
        if not h.classes:includes("unnumbered") then h.classes:insert("unnumbered") end
        if h.level > toc_depth and not h.classes:includes("unlisted") then
          h.classes:insert("unlisted")
        end
      end
      return h
    end,
  })
end

-- Append the endnote collection marker for TeX endnotes (keystone-note-placement
-- "endnotes" — see inject_note_placement). It lands before citeproc's #refs
-- bibliography because Lua filters run ahead of --citeproc.
--
-- Why the marker is emitted here, not in includes/endnotes.tex like the rest of
-- the mechanism: it is a positional body block — it must be the LAST block so
-- notes collect after all content — so it is an AST append, not a preamble
-- include. A .tex file cannot express "append after the document body". The
-- package load, \footnote alias, and the flush macro itself live in the
-- include; only this placement-dependent call has to be emitted from the filter.
-- \keystoneflushendnotes is \theendnotes guarded by a note-count check, so a
-- book with no notes (book targets default to endnotes) emits nothing.
local function append_endnote_marker(doc)
  local placement = kast.meta.stringify(doc.meta["keystone-note-placement"])
  if placement == "endnotes" and format_registry.uses_tex(FORMAT_KEY) then
    table.insert(doc.blocks, kast.RawBlock("latex", "\\keystoneflushendnotes"))
  end
end

-- ── Pandoc filter entry points ──────────────────────────────────────

function Div(el)
  local value = font_aware.family_value(el, ns)
  if value then
    _used_font_families[font_registry.canonical(value)] = true
  end
end

function Span(el)
  local value = font_aware.family_value(el, ns)
  if value then
    _used_font_families[font_registry.canonical(value)] = true
  end
end

function Meta(meta)
  -- All formats: metadata enrichment
  validate_required_fields(meta)
  validate_linestretch(meta)
  validate_fontsize(meta)
  bridge_abstract_to_description(meta)
  bridge_description_to_subject(meta)
  enrich_date(meta)
  sanitize_cover_image(meta)
  strip_secnumdepth(meta)

  -- Per-format style injection — each resolves its own format gating
  inject_fonts(meta)
  inject_draft_watermark(meta)
  inject_justify(meta)
  inject_indent(meta)
  inject_toc_depth(meta)
  inject_link_colors(meta)
  inject_code_theme(meta)
  inject_note_placement(meta)

  return meta
end

function Pandoc(doc)
  limit_section_numbering(doc)
  append_endnote_marker(doc)

  return doc
end
