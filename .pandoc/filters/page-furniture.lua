---@diagnostic disable: undefined-global
-- page-furniture.lua — Compose running header/footer slot content
--
-- Runs after shortcuts → keystone → divs in the pipeline.
-- Reads `header-text` / `footer-text` (un-suffixed) plus the parity-
-- suffixed `header-text-recto` / `header-text-verso` /
-- `footer-text-recto` / `footer-text-verso`, runs each non-blank
-- source key through the placeholder substitution layer
-- (lib/placeholder-substitute.lua) to resolve `{title}`, `{chapter}`,
-- `{page}` and the other registry tokens, then emits the per-slot
-- content macros into header-includes. Whatever carries a default —
-- `page-number-position`, the opening-page pair — arrives settled from
-- keystone.lua, so this filter holds none of its own; for the running
-- text keys blank simply means no content:
--
--   \keystoneheader<slot>         body-page running header
--   \keystonefooter<slot>         body-page running footer
--   \keystoneopeningfooter<slot>  opening-page footer
--
-- where <slot> is a column letter (L, C, R) followed by a parity letter
-- (O = odd = recto, E = even = verso). The corresponding LaTeX include
-- (page-layout-fancyhdr.tex, page-layout-scrlayer.tex) wires those
-- macros into the layout package's native parity slots — fancyhdr's
-- [LO]/[LE] etc., or scrlayer-scrpage's \lohead/\lehead etc.
--
-- The opening-page family covers chapter starts, the table of contents,
-- the index, and part titles — the pages that render with no running
-- header and no rule. Its source key is `footer-text-opening`, which
-- `disabled` empties; the column it occupies arrives in
-- `footer-text-opening-column`, already resolved, so placing it needs no
-- knowledge of whether the author named that column or the folio did.
-- The include owns which transitions select the opening page style,
-- under one invariant: the title page is not one of them and stays bare.
--
-- Composition rules (text vs. page number, center-slot conflict,
-- recto/verso fallback) live here, not in the includes — they only
-- map the resulting macros to their package's native slots.
-- Placeholder tokenization and substitution live in their own
-- libs (placeholder-registry.lua + placeholder-substitute.lua) so
-- this filter only wires them in at the metadata boundary.
--
-- ATTENTION! This filter MUST remain package-agnostic.
--
-- Every macro this filter emits must be package-neutral — no
-- \fancyhead, \fancyfoot, \fancypagestyle, \pagestyle, \scrlayer*,
-- \automark, \pagemark, or any other package-specific macro. Those
-- are the include's job. The contract is that any LaTeX layout
-- package (fancyhdr, scrlayer-scrpage, titleps, …) can supply its
-- own include that consumes these \keystone* macros and produces
-- correct output without changing this filter. Today the output is
-- the slot-content \newcommand definitions plus the package-agnostic
-- \keystoneheaderrule invocation (each include defines what that name
-- expands to for its package). That mix is fine: the invariant is
-- package-neutrality itself. Adding a fancyhdr-specific (or
-- scr-specific) command here breaks the contract and forces the filter
-- to know about every supported package.
--
-- Single-sided documents: under report / article (and any document
-- with classoption: oneside), LaTeX's page-style dispatch only ever
-- selects the recto (odd-page) macros. The verso macros are defined
-- but unused, and composing them anyway costs nothing — so slot
-- composition stays parity-symmetric, and authors who flip
-- classoption: twoside on an article get correct verso output without
-- any infrastructure change.
--
-- The one place sidedness is consulted is the center-slot conflict
-- warning, which reports text losing its slot to the page number. On a
-- verso that will never render there is no loss to report, and saying
-- otherwise fails a strict build over nothing. `keystone-twoside`
-- carries the answer, settled by keystone.lua from the target's
-- declaration and any classoption override.
--
-- Running after the handler and shortcut filters is intentional: it
-- lets handlers (.font, .align via
-- divs.lua) and user-defined shortcuts (via shortcuts.lua) already
-- dispatch into metadata Spans before this filter renders the inlines
-- to LaTeX. By the time Meta() runs here, the inline tree is pure
-- Pandoc primitives plus format-specific RawInlines.

local path = pandoc.path

local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

-- Install the memoized module loader, then acquire KAST. See
-- https://keystone.knight-owl.dev/engine/kast/
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")
local errors = ks_require("errors")

local format_registry        = ks_require("format-registry")
local page_position          = ks_require("page-position")
local placeholder_registry   = ks_require("placeholder-registry")
local placeholder_substitute = ks_require("placeholder-substitute")
local marks                  = ks_require("marks")
local env_io                 = ks_require("env-io")

local FORMAT_KEY = format_registry.resolve_key(FORMAT)

local COL_LETTER = { left = "L", center = "C", right = "R" }
local SLOT_SUFFIXES = { "LO", "LE", "CO", "CE", "RO", "RE" }

-- Rows all compose into the same grid, so it is derived from SLOT_SUFFIXES
-- rather than respelled per row.
local function empty_slots()
  local slots = {}
  for _, suffix in ipairs(SLOT_SUFFIXES) do
    slots[suffix] = ""
  end
  return slots
end

-- Resolve the text Meta value to use for one parity. Suffixed key wins
-- over the un-suffixed key when present; falls back to un-suffixed only
-- when the suffixed key is nil (which Meta()'s substitute helper uses
-- as the universal "no content" sentinel — see Meta() below). The
-- "disabled" literal is content for resolve_parity_text and reaches
-- place_text where it's caught explicitly.
local function resolve_parity_text(suffixed, unsuffixed)
  if suffixed == nil then return unsuffixed end
  return suffixed
end

-- True when a text value is the literal "disabled" — the suppression
-- sentinel every `*-text` source key accepts. Recognizing it takes a
-- stringify because it survives substitution as ordinary content; every
-- other "no content" case has already collapsed to nil in Meta().
local function is_disabled(text_meta)
  return kast.meta.stringify(text_meta) == "disabled"
end

-- Place inline text into the center slot for one parity, handling the
-- center-slot conflict rule. When the page number occupies the center
-- column for this parity AND the text is non-blank, the page number
-- wins and the text is dropped with a WARN (via the errors lib). Either
-- parity can trigger the warning independently.
--
-- text_meta is either nil (Meta() normalized all blank cases to nil)
-- or a non-empty inline list.
--
-- `renders` says whether this parity reaches paper at all. A one-sided
-- document selects only the recto macros, so a verso conflict there costs
-- nothing: warning about it would report a loss that cannot happen, and fail
-- a strict build over it.
local function place_text(slots, slot_key, row_name, parity_name, text_meta, pn_col, renders)
  if text_meta == nil or is_disabled(text_meta) then return end
  if pn_col == "center" then
    if renders then
      errors.warn(string.format(
        "page-number-position occupies %s:center on %s; %s-text suppressed on %s",
        row_name, parity_name, row_name, parity_name))
    end
    return
  end
  slots[slot_key] = kast.latex.inlines(text_meta)
end

-- Compose the six per-parity slot strings (LO, LE, CO, CE, RO, RE) for
-- one row. `unsuffixed` is the row's `<row>-text` meta value; `recto`
-- and `verso` are the parity-suffixed values. `pn` is the row's pn map
-- ({ recto = <col>|nil, verso = <col>|nil }).
local function compose_row(row_name, unsuffixed, recto, verso, pn, twoside)
  local slots = empty_slots()

  if pn.recto then
    slots[COL_LETTER[pn.recto] .. "O"] = "\\thepage"
  end
  if pn.verso then
    slots[COL_LETTER[pn.verso] .. "E"] = "\\thepage"
  end

  local recto_text = resolve_parity_text(recto, unsuffixed)
  place_text(slots, "CO", row_name, "recto", recto_text, pn.recto, true)

  local verso_text = resolve_parity_text(verso, unsuffixed)
  place_text(slots, "CE", row_name, "verso", verso_text, pn.verso, twoside)

  return slots
end

-- Emit one RawBlock holding every \newcommand definition. One block keeps the
-- header-includes payload tidy and atomic. Each slot map holds already-rendered
-- LaTeX, "" for a slot that carries nothing.
local function emit_macros(meta, header_slots, footer_slots, opening_slots)
  local lines = {}
  for _, suffix in ipairs(SLOT_SUFFIXES) do
    table.insert(lines, kast.latex.newcommand("keystoneheader" .. suffix, header_slots[suffix]))
    table.insert(lines, kast.latex.newcommand("keystonefooter" .. suffix, footer_slots[suffix]))
    table.insert(lines, kast.latex.newcommand("keystoneopeningfooter" .. suffix, opening_slots[suffix]))
  end
  table.sort(lines)  -- deterministic order for tests/diffs
  kast.meta.add_header_include(meta, table.concat(lines, "\n"))
end

-- Opt the running-header rule on when the author enabled it. The rule is
-- off by default in both page-layout includes; each include defines
-- \keystoneheaderrule to re-enable it through its own package API
-- (fancyhdr's \headrulewidth, scrlayer's headsepline). We only invoke the
-- neutral macro — resolution lives in publish.sh (KEYSTONE_HEADER_RULE),
-- and the include owns the package-specific body, keeping this filter
-- package-agnostic. PDF-only by construction: Meta() returns early for
-- non-TeX formats before this runs.
local function emit_header_rule(meta)
  if env_io.optional_env("KEYSTONE_HEADER_RULE") ~= "1" then return end
  kast.meta.add_header_include(meta, "\\keystoneheaderrule")
end

function Meta(meta)
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local pn = page_position.parse(kast.meta.stringify(meta["page-number-position"]))

  -- Substitute `{name}` placeholders in each of the six potential
  -- source text keys before parity dispatch composes them into
  -- slots. Substituting at the metadata boundary — once per distinct
  -- source value — keeps `compose_row` oblivious to substitution and
  -- avoids re-running on values that two parities both fall back to.
  --
  -- This helper is also the one place we normalize "no content" to a
  -- single sentinel (nil). `kast.meta.is_blank` catches blank input
  -- (absent key, empty string, whitespace-only, stringify-blank
  -- inline lists); a substitution result that collapses to an empty
  -- inline list (all-blank-static placeholders) is also normalized
  -- to nil. Downstream code only needs to check `nil` to decide
  -- whether to render or fall back — no stringify-based blank checks
  -- that would mis-classify RawInline-only output as empty.
  -- Fold the author-declared marks (KEYSTONE_MARKS) into the placeholder
  -- registry and collect their \NewMarkClass preamble (emitted below).
  local registry, mark_classes = marks.resolve(env_io.optional_env("KEYSTONE_MARKS") or "", placeholder_registry)
  local subst_deps = { registry = registry }
  local function substitute_value(val)
    if kast.meta.is_blank(val) then return nil end
    local result = placeholder_substitute.substitute(val, meta, subst_deps)
    if type(result) == "table" and #result == 0 then return nil end
    return result
  end
  local function substitute(key)
    return substitute_value(meta[key])
  end

  -- Effective sidedness, settled by keystone.lua from the target's
  -- declaration and any classoption override.
  local twoside = kast.meta.stringify(meta["keystone-twoside"]) == "true"

  local header_slots = compose_row(
    "header",
    substitute("header-text"),
    substitute("header-text-recto"),
    substitute("header-text-verso"),
    pn.header,
    twoside)
  local footer_slots = compose_row(
    "footer",
    substitute("footer-text"),
    substitute("footer-text-recto"),
    substitute("footer-text-verso"),
    pn.footer,
    twoside)

  -- The opening-page footer skips compose_row: it holds one piece of content
  -- with no page number to collide with, so it needs the column's parity split
  -- but none of the row's precedence rules. The same rendering fills both
  -- parities — a page is one or the other, never both — and a value that
  -- substitutes away renders empty rather than falling back to anything.
  local opening_slots = empty_slots()
  local opening_source = meta["footer-text-opening"]
  if not is_disabled(opening_source) then
    local rendered = kast.latex.inlines(substitute_value(opening_source))
    local parity = page_position.resolve_parity(
      kast.meta.stringify(meta["footer-text-opening-column"]))
    opening_slots[COL_LETTER[parity.recto] .. "O"] = rendered
    opening_slots[COL_LETTER[parity.verso] .. "E"] = rendered
  end

  emit_macros(meta, header_slots, footer_slots, opening_slots)
  emit_header_rule(meta)
  if #mark_classes > 0 then
    kast.meta.add_header_include(meta, table.concat(mark_classes, "\n"))
  end
  return meta
end
