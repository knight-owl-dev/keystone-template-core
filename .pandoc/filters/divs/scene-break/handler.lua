-- Inserts a scene break ornament for ::: scene-break blocks.
-- Content priority: div content > default "* * *". Custom ornaments are
-- supplied via shortcut body injection (not handler attributes).
-- LaTeX output uses \scenebreak{} for page-break protection.
-- See README.md for usage. EPUB/HTML styling loaded from style.css.

local kast = ks_require("ast")

local DEFAULT_ORNAMENT = "* * *"

local function latex(el)
  local content
  if #el.content > 0 then
    local inlines = kast.blocks_to_inlines(el.content)
    content = kast.latex.inlines(inlines)
  else
    content = DEFAULT_ORNAMENT
  end

  return kast.RawBlock("latex", kast.latex.command("scenebreak", { args = { content } }))
end

local function html(el)
  if #el.content > 0 then
    el.classes = { "scene-break" }
    return el
  else
    return kast.RawBlock("html", '<div class="scene-break">' .. DEFAULT_ORNAMENT .. "</div>")
  end
end

local function docx(el)
  -- Ornament text as a styled paragraph; empty div gets default ornament
  if #el.content == 0 then
    el.content = { kast.Plain({ kast.Str(DEFAULT_ORNAMENT) }) }
  end
  el.attributes["custom-style"] = "SceneBreak"
  return el
end

-- ODT writer only propagates custom-style to Para blocks, not Plain.
-- Use Para so the style applies to both empty and content scene breaks.
local function odt(el)
  if #el.content == 0 then
    el.content = { kast.Para({ kast.Str(DEFAULT_ORNAMENT) }) }
  end
  el.attributes["custom-style"] = "SceneBreak"
  return el
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = docx,
    odt = odt,
  },
}
