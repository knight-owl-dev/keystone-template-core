-- Wraps content in a multi-column layout using the multicol LaTeX package
-- (PDF) or CSS column-count (EPUB/HTML).
-- See README.md for usage. LaTeX macros loaded from macros.tex.

local kast = ks_require("ast")

--- Validate the cols attribute. Returns the numeric value or nil on error.
local function validate_cols(el)
  local raw = el.attributes["cols"]
  if not raw then return 2 end
  local n = tonumber(raw)
  if not n or n ~= math.floor(n) or n < 2 or n > 4 then
    io.stderr:write("WARN: multicol: invalid cols '" .. raw
      .. "' (must be an integer from 2 to 4)\n")
    return nil
  end
  return n
end

local function latex(el)
  local cols = validate_cols(el)
  if not cols then return nil end

  local tex = kast.latex.blocks(el.content)

  return kast.RawBlock("latex", kast.latex.env("multicols", tex, { args = { cols } }))
end

local function html(el)
  local cols = validate_cols(el)
  if not cols then return nil end

  el.classes = { "multicol" }
  if cols ~= 2 then
    el.attributes["style"] = "column-count: " .. cols
  end
  el.attributes["cols"] = nil
  return el
end

-- No multi-column in DOCX — unwrap div, content renders as single column
local function docx(el)
  return el.content
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
