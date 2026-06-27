-- Transforms ::: dialog blocks into stylized dialog lines.
--
-- Style attribute (optional):
--   ::: dialog                       (default — tight, flush-left wrap)
--   ::: {.dialog style=hanging}      (hanging — wrap indented under speech)
--
-- See README.md for full usage. LaTeX macros loaded from macros.tex.

local kast = ks_require("ast")

-- Bare command names (no leading backslash) — emitted via kast.latex.command.
local DIALOGLINE_MACRO = {
  default = "dialogline",
  hanging = "dialoglinehang",
}

--- Resolve the style attribute on a dialog div. Recognized values
--- are "default" and "hanging"; absent attribute is treated as
--- "default". Unknown values warn to stderr and fall through to
--- "default" — consistent with align/aside/font handler conventions.
local function resolve_style(el)
  local raw = el.attributes and el.attributes["style"] or ""
  if raw == "" or raw == "default" then return "default" end
  if raw == "hanging" then return "hanging" end
  io.stderr:write("WARN: dialog: unknown style '" .. raw .. "'\n")
  return "default"
end

--- Collect inlines from each BulletList item across all blocks.
local function collect_items(el)
  local items = {}
  for _, block in ipairs(el.content) do
    if block.t == "BulletList" then
      for _, item in ipairs(block.content) do
        items[#items + 1] = item[1].content
      end
    end
  end
  return items
end

local function latex(el)
  local items = collect_items(el)
  local macro = DIALOGLINE_MACRO[resolve_style(el)]
  local blocks = {}

  -- Vertical space before the dialog block so it visibly separates from
  -- preceding prose. Required because Pandoc's \parskip can be 0 (book
  -- mode); the macro adds whatever's needed to reach \medskipamount.
  blocks[#blocks + 1] = kast.RawBlock("latex", "\\beforedialogblock")

  for _, inlines in ipairs(items) do
    local tex = kast.latex.inlines(inlines)
    blocks[#blocks + 1] = kast.RawBlock("latex", kast.latex.command(macro, { args = { tex } }))
  end

  -- Vertical space after the block — same mode-independent target
  -- (\medskipamount of separation), via a different formula because
  -- \dialogline eats the trailing \parskip. See macros.tex.
  blocks[#blocks + 1] = kast.RawBlock("latex", "\\afterdialogblock")
  return blocks
end

--- Em-dash prefix output for HTML, EPUB, and DOCX.
--- Wraps the lines in a `dialog` Div so style.css can target `.dialog p`
--- and override the global `p + p { text-indent: var(--ks-indent) }`
--- rule (otherwise the second dialog line picks up an indent in
--- indent-on mode). When style=hanging, an extra `hanging` class is
--- added so `.dialog.hanging p` can apply the hanging-indent CSS.
--- DOCX/ODT writers ignore unknown-class wrappers so the wrapper has
--- no effect outside HTML/EPUB.
local function html(el)
  local items = collect_items(el)
  local blocks = {}

  for _, inlines in ipairs(items) do
    local line = kast.List({ kast.Str("\u{2014}"), kast.Space() })
    line:extend(inlines)
    blocks[#blocks + 1] = kast.Para(line)
  end

  local classes = { "dialog" }
  if resolve_style(el) == "hanging" then
    table.insert(classes, "hanging")
  end

  return kast.Div(blocks, kast.Attr("", classes))
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = html,
    odt = html,
  },
}
