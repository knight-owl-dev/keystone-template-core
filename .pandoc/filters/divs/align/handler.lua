-- Applies text alignment to ::: align divs via a single style= attribute.
-- See README.md for usage. No macros.tex needed — the standard LaTeX
-- alignment environments suffice (keystonejustify lives in base-style.tex).

local kast = ks_require("ast")

-- Alignment value → LaTeX environment name. Content is serialized and wrapped
-- via kast.latex.env (same pattern as quote/multicol/aside).
local ALIGN_ENV = {
  left = "flushleft",
  center = "center",
  right = "flushright",
  justified = "keystonejustify",
}

local DOCX_ALIGN_STYLES = {
  left = "AlignLeft",
  center = "Centered",
  right = "AlignRight",
  justified = "Justified",
}

--- Returns the alignment value or nil on error.
local function validate(el)
  local style = el.attributes["style"]
  if not style then return nil end

  if not ALIGN_ENV[style] then
    io.stderr:write("WARN: align: unknown style '" .. style .. "'\n")
    return nil
  end

  return style
end

local function latex(el)
  local style = validate(el)
  if not style then return nil end

  local body = kast.latex.blocks(el.content)
  return kast.RawBlock("latex", kast.latex.env(ALIGN_ENV[style], body))
end

local function html(el)
  local style = validate(el)
  if not style then return nil end

  el.classes = { "style-" .. style }
  el.attributes["style"] = nil
  return el
end

local function docx(el)
  local style = validate(el)
  if not style then return nil end

  el.attributes["custom-style"] = DOCX_ALIGN_STYLES[style]
  el.attributes["style"] = nil
  return el
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = docx,
    odt = docx,
  },
}
