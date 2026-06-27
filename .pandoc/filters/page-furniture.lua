---@diagnostic disable: undefined-global
-- page-furniture.lua — Compose running header/footer slot content
--
-- Runs after shortcuts → keystone → divs in the pipeline.
-- Reads `header-text` / `footer-text` (un-suffixed) plus the parity-
-- suffixed `header-text-recto` / `header-text-verso` /
-- `footer-text-recto` / `footer-text-verso`, runs each non-blank
-- source key through the placeholder substitution layer
-- (lib/placeholder-substitute.lua) to resolve `{title}`, `{chapter}`,
-- `{page}` and the other registry tokens, then emits the twelve
-- per-slot content macros into header-includes:
--
--   \keystoneheaderLO  \keystoneheaderCO  \keystoneheaderRO
--   \keystoneheaderLE  \keystoneheaderCE  \keystoneheaderRE
--   \keystonefooterLO  \keystonefooterCO  \keystonefooterRO
--   \keystonefooterLE  \keystonefooterCE  \keystonefooterRE
--
-- The {L,C,R} suffix names the column (left, center, right); the
-- trailing {O,E} names page parity (odd = recto, even = verso). The
-- corresponding LaTeX include (page-layout-fancyhdr.tex,
-- page-layout-scrlayer.tex) wires those macros into the layout
-- package's native parity slots — fancyhdr's [LO]/[LE] etc., or
-- scrlayer-scrpage's \lohead/\lehead etc.
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
-- the twelve slot-content \newcommand definitions plus the package-
-- agnostic \keystoneheaderrule invocation (each include defines what
-- that name expands to for its package). That mix is fine — the
-- invariant is package-neutrality, not the macro count. Adding a
-- fancyhdr-specific (or scr-specific) command here breaks the contract
-- and forces the filter to know about every supported package.
--
-- Single-sided documents: under report / article (and any document
-- with classoption: oneside), LaTeX's page-style dispatch only ever
-- selects the recto (odd-page) macros. The verso macros are defined
-- but unused. That's correct by design — the filter doesn't need to
-- know whether the target is one- or two-sided, and authors who flip
-- classoption: twoside on an article get correct verso output
-- without any infrastructure change.
--
-- Running after the handler and shortcut filters is intentional: it
-- lets handlers (.font, .align via
-- divs.lua) and user-defined shortcuts (via shortcuts.lua) already
-- dispatch into metadata Spans before this filter renders the inlines
-- to LaTeX. By the time Meta() runs here, the inline tree is pure
-- Pandoc primitives plus format-specific RawInlines.

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

local format_registry        = ks_require("format-registry")
local placeholder_registry   = ks_require("placeholder-registry")
local placeholder_substitute = ks_require("placeholder-substitute")
local marks                  = ks_require("marks")

local FORMAT_KEY = format_registry.resolve_key(FORMAT)

local DEFAULT_POSITION = "footer:outer"
local VALID_ROWS = { header = true, footer = true, ["header-and-footer"] = true }
local VALID_COLS = {
  left = true, center = true, right = true,
  outer = true, inner = true,
}
local COL_LETTER = { left = "L", center = "C", right = "R" }
local SLOT_SUFFIXES = { "LO", "LE", "CO", "CE", "RO", "RE" }

-- Resolve a col value to its (recto, verso) col pair.
--   outer  → recto=right, verso=left   (outside edge of the spread)
--   inner  → recto=left,  verso=right  (binding edge of the spread)
--   left|center|right → same col on both parities (positional)
local function resolve_parity(col)
  if col == "outer" then return { recto = "right", verso = "left" } end
  if col == "inner" then return { recto = "left", verso = "right" } end
  return { recto = col, verso = col }
end

-- Parse `<row>:<col>` form into a per-row recto/verso col map.
-- header-and-footer expands to both rows getting the page number at <col>.
-- Errors with a helpful message on any invalid input.
local function parse_position(str)
  local row, col = str:match("^([^:]+):([^:]+)$")
  if not row or not col then
    error(string.format(
      "page-number-position must be of the form '<row>:<col>' "
      .. "(row in header|footer|header-and-footer, "
      .. "col in left|center|right|outer|inner); got %q",
      str))
  end
  if not VALID_ROWS[row] then
    error(string.format(
      "page-number-position row must be one of header, footer, header-and-footer; got %q",
      row))
  end
  if not VALID_COLS[col] then
    error(string.format(
      "page-number-position col must be one of left, center, right, outer, inner; got %q",
      col))
  end
  local parity = resolve_parity(col)
  local result = {
    header = { recto = nil, verso = nil },
    footer = { recto = nil, verso = nil },
  }
  if row == "header-and-footer" then
    result.header = parity
    result.footer = parity
  else
    result[row] = parity
  end
  return result
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

-- Place inline text into the center slot for one parity, handling the
-- center-slot conflict rule. When the page number occupies the center
-- column for this parity AND the text is non-blank, the page number
-- wins and the text is dropped with a stderr WARNING. Either parity
-- can trigger the warning independently.
--
-- text_meta is either nil (Meta() normalized all blank cases to nil)
-- or a non-empty inline list. The "disabled" sentinel check uses
-- stringify because it's the only place we need to recognize that
-- specific literal — every other blank case has already collapsed
-- to nil upstream.
local function place_text(slots, slot_key, row_name, parity_name, text_meta, pn_col)
  if text_meta == nil or kast.meta.stringify(text_meta) == "disabled" then return end
  if pn_col == "center" then
    io.stderr:write(string.format(
      "WARNING: page-number-position occupies %s:center on %s; "
      .. "%s-text suppressed on %s\n",
      row_name, parity_name, row_name, parity_name))
    return
  end
  slots[slot_key] = kast.latex.inlines(text_meta)
end

-- Compose the six per-parity slot strings (LO, LE, CO, CE, RO, RE) for
-- one row. `unsuffixed` is the row's `<row>-text` meta value; `recto`
-- and `verso` are the parity-suffixed values. `pn` is the row's pn map
-- ({ recto = <col>|nil, verso = <col>|nil }).
local function compose_row(row_name, unsuffixed, recto, verso, pn)
  local slots = { LO = "", LE = "", CO = "", CE = "", RO = "", RE = "" }

  if pn.recto then
    slots[COL_LETTER[pn.recto] .. "O"] = "\\thepage"
  end
  if pn.verso then
    slots[COL_LETTER[pn.verso] .. "E"] = "\\thepage"
  end

  local recto_text = resolve_parity_text(recto, unsuffixed)
  place_text(slots, "CO", row_name, "recto", recto_text, pn.recto)

  local verso_text = resolve_parity_text(verso, unsuffixed)
  place_text(slots, "CE", row_name, "verso", verso_text, pn.verso)

  return slots
end

-- Emit one RawBlock holding all twelve \newcommand definitions.
-- One block keeps the header-includes payload tidy and atomic.
local function emit_macros(meta, header_slots, footer_slots)
  local lines = {}
  for _, suffix in ipairs(SLOT_SUFFIXES) do
    table.insert(lines, kast.latex.newcommand("keystoneheader" .. suffix, header_slots[suffix]))
    table.insert(lines, kast.latex.newcommand("keystonefooter" .. suffix, footer_slots[suffix]))
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
  if os.getenv("KEYSTONE_HEADER_RULE") ~= "1" then return end
  kast.meta.add_header_include(meta, "\\keystoneheaderrule")
end

function Meta(meta)
  if not format_registry.uses_tex(FORMAT_KEY) then return end

  local pos_str = kast.meta.stringify(meta["page-number-position"])
  if pos_str == "" then pos_str = DEFAULT_POSITION end
  local pn = parse_position(pos_str)

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
  local registry, mark_classes = marks.resolve(os.getenv("KEYSTONE_MARKS") or "", placeholder_registry)
  local subst_deps = { registry = registry }
  local function substitute(key)
    local val = meta[key]
    if kast.meta.is_blank(val) then return nil end
    local result = placeholder_substitute.substitute(val, meta, subst_deps)
    if type(result) == "table" and #result == 0 then return nil end
    return result
  end

  local header_slots = compose_row(
    "header",
    substitute("header-text"),
    substitute("header-text-recto"),
    substitute("header-text-verso"),
    pn.header)
  local footer_slots = compose_row(
    "footer",
    substitute("footer-text"),
    substitute("footer-text-recto"),
    substitute("footer-text-verso"),
    pn.footer)

  emit_macros(meta, header_slots, footer_slots)
  emit_header_rule(meta)
  if #mark_classes > 0 then
    kast.meta.add_header_include(meta, table.concat(mark_classes, "\n"))
  end
  return meta
end
