-- Inserts explicit vertical whitespace for ::: vspace blocks.
-- Attribute: size (required) — named size, explicit CSS length, or "none".
-- "none" (and any zero length) emits nothing — see is_none.
-- See README.md for usage.

local kast = ks_require("ast")

local NAMED_SIZES = {
  tiny   = "0.5em",
  small  = "1em",
  medium = "2em",
  large  = "4em",
  huge   = "8em",
}

-- Ordered thresholds for snapping explicit lengths to named sizes.
-- Midpoints between consecutive em values define bucket boundaries.
local SNAP_THRESHOLDS = {
  { limit = 0.75,  name = "tiny"   },  -- 0..0.75 → tiny (0.5em)
  { limit = 1.5,   name = "small"  },  -- 0.75..1.5 → small (1em)
  { limit = 3.0,   name = "medium" },  -- 1.5..3.0 → medium (2em)
  { limit = 6.0,   name = "large"  },  -- 3.0..6.0 → large (4em)
}

local DOCX_STYLES = {
  tiny   = "VspaceTiny",
  small  = "VspaceSmall",
  medium = "VspaceMedium",
  large  = "VspaceLarge",
  huge   = "VspaceHuge",
}

-- Unit-to-em conversion factors (1em = 12pt baseline).
local UNIT_TO_EM = {
  em  = 1,
  rem = 1,
  pt  = 1 / 12,
  px  = 1 / 16,
  cm  = 1 / 0.4233,
  mm  = 1 / 4.233,
  ["in"] = 1 / 0.1667,
}

--- Parse a CSS length string into a numeric em value, or nil if invalid.
--- Accepts standard forms: "2em", ".5em", "0" (unitless zero).
local function parse_length_em(raw)
  -- Unitless zero is valid CSS and means no space.
  if raw == "0" then return 0 end
  local num, unit = raw:match("^([%d]*%.?[%d]+)(%a+)$")
  if not num then return nil end
  local factor = UNIT_TO_EM[unit]
  if not factor then return nil end
  return tonumber(num) * factor
end

--- Returns true if the string is a valid CSS length (number + known unit,
--- or unitless zero).
local function is_css_length(raw)
  return parse_length_em(raw) ~= nil
end

-- Sentinel for "emit no block": resolvers return it, format handlers turn it
-- into kast.Remove(). Distinct from nil, which signals invalid input (the
-- element is left unprocessed).
local NONE = {}

--- True when the size denotes zero space: the literal "none", or any length
--- that measures 0 ("0", "0em", …). Catching zero here also keeps it out of
--- the DOCX/ODT snap, which would otherwise round 0 up to the smallest style.
local function is_none(raw)
  return raw == "none" or parse_length_em(raw) == 0
end

--- Snap an em value to the nearest named size.
local function snap_to_named(em_value)
  for _, threshold in ipairs(SNAP_THRESHOLDS) do
    if em_value <= threshold.limit then
      return threshold.name
    end
  end
  return "huge"
end

--- Warn on unexpected content and return the size, or nil (warning) if absent —
--- reachable only via direct ks-vspace. Shared by both resolvers.
local function sized(el, report)
  if #el.content > 0 then
    report.warn("vspace: div has content (expected empty)")
  end
  local raw = el.attributes["size"]
  if not raw then
    report.warn("vspace: no size given")
    return nil
  end
  return raw
end

local function warn_unrecognized(raw, report)
  report.warn("vspace: unrecognized size '" .. raw .. "'")
end

--- Validate the element and resolve size for PDF/EPUB. Returns the CSS/LaTeX
--- length string (named lookup or explicit passthrough), or nil on invalid input.
local function resolve_size(el, report)
  local raw = sized(el, report)
  if not raw then return nil end

  if is_none(raw) then return NONE end
  if NAMED_SIZES[raw] then return NAMED_SIZES[raw] end
  if is_css_length(raw) then return raw end

  warn_unrecognized(raw, report)
  return nil
end

--- Validate the element and resolve size for DOCX/ODT. Returns a style name
--- (named lookup or nearest snap for explicit lengths), or nil on invalid input.
local function resolve_style(el, report)
  local raw = sized(el, report)
  if not raw then return nil end

  if is_none(raw) then return NONE end
  if DOCX_STYLES[raw] then return DOCX_STYLES[raw] end

  local em_value = parse_length_em(raw)
  if em_value then return DOCX_STYLES[snap_to_named(em_value)] end

  warn_unrecognized(raw, report)
  return nil
end

--- PDF: emit \vspace*{} with the resolved size. The starred form forces
--- whitespace even at the top of a new page (standard for title pages).
---@param el table  Pandoc Div element
---@return table|nil  RawBlock element, kast.Remove() when size is none, or nil on validation failure
local function latex(el, report)
  local size = resolve_size(el, report)
  if not size then return nil end
  if size == NONE then return kast.Remove() end
  return kast.RawBlock("latex", kast.latex.command("vspace*", { args = { size } }))
end

--- EPUB/HTML: emit an empty div with margin-top inline style.
--- Uses a native Pandoc Div so Pandoc handles HTML serialization safely.
---@param el table  Pandoc Div element
---@return table|nil  Div element, kast.Remove() when size is none, or nil on validation failure
local function html(el, report)
  local size = resolve_size(el, report)
  if not size then return nil end
  if size == NONE then return kast.Remove() end
  local div = kast.Div({}, kast.Attr("", { "vspace" }))
  div.attributes["style"] = "margin-top: " .. size
  return div
end

--- Emit a spacer paragraph with a custom style for DOCX/ODT.
--- The block constructor differs by format: DOCX propagates custom-style
--- to both Plain and Para, but ODT only propagates it to Para. Pass
--- kast.Plain for DOCX and kast.Para for ODT.
---@param el table  Pandoc Div element
---@param block_fn function  kast.Plain (DOCX) or kast.Para (ODT)
---@return table|nil  modified element, kast.Remove() when style is none, or nil on validation failure
local function styled_spacer(el, block_fn, report)
  local style = resolve_style(el, report)
  if not style then return nil end
  if style == NONE then return kast.Remove() end
  el.content = { block_fn({ kast.Str("") }) }
  el.attributes["custom-style"] = style
  el.attributes["size"] = nil
  return el
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = function(el, report) return styled_spacer(el, kast.Plain, report) end,
    odt = function(el, report) return styled_spacer(el, kast.Para, report) end,
  },
  required_attributes = { "size" },
}
