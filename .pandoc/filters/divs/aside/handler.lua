-- Transforms ::: aside blocks into styled callout boxes (tip, warning,
-- note, example). PDF uses tcolorbox; EPUB/HTML uses styled divs.
-- Authors can override accent color, title, and border.
-- See README.md for usage. LaTeX macros loaded from macros.tex.

local kast = ks_require("ast")

-- Type registry: label, LaTeX color name, CSS border color, CSS background
local TYPES = {
  tip     = { label = "Tip",     color = "aside-tip",     css_border = "#5b7a5e", css_bg = "#f4f7f4" },
  warning = { label = "Warning", color = "aside-warning", css_border = "#9e7c4a", css_bg = "#f8f5f0" },
  note    = { label = "Note",    color = "aside-note",    css_border = "#4a6a8a", css_bg = "#f0f4f8" },
  example = { label = "Example", color = "aside-example", css_border = "#6a5a7a", css_bg = "#f5f3f7" },
}

--- Mix a hex color 93% toward white for light EPUB backgrounds.
---@param hex string  "#rrggbb" hex color
---@return string  "#rrggbb" lightened color
local function lighten_hex(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)

  r = math.floor(r + (255 - r) * 0.93 + 0.5)
  g = math.floor(g + (255 - g) * 0.93 + 0.5)
  b = math.floor(b + (255 - b) * 0.93 + 0.5)

  return string.format("#%02x%02x%02x", r, g, b)
end

--- Shared validation. Returns type_info, title, custom_color, border
--- — or nil on error.
local function validate(el)
  local aside_type = el.attributes["type"]
  if not aside_type then
    io.stderr:write("WARN: aside: missing required 'type' attribute\n")
    return nil
  end

  local type_info = TYPES[aside_type]
  if not type_info then
    io.stderr:write("WARN: aside: unknown type '" .. aside_type .. "'\n")
    return nil
  end

  local custom_color = el.attributes["color"]
  if custom_color and not custom_color:match("^#%x%x%x%x%x%x$") then
    io.stderr:write("WARN: aside: invalid color '" .. custom_color .. "' (must be #rrggbb)\n")
    return nil
  end

  local border = el.attributes["border"]
  if border and border ~= "none" then
    io.stderr:write("WARN: aside: invalid border '" .. border .. "' (must be 'none')\n")
    return nil
  end

  local title = el.attributes["title"]
  if title == nil then
    title = type_info.label
  elseif title == "" then
    title = nil
  end

  return type_info, title, custom_color, border
end

local function latex(el)
  local type_info, title, custom_color, border = validate(el)
  if not type_info then return nil end

  local parts = {}

  if custom_color then
    local hex = custom_color:sub(2)
    parts[#parts + 1] = kast.latex.command("definecolor", { args = { "aside-user", "HTML", hex } })
  end

  local color_name = custom_color and "aside-user" or type_info.color

  local box_opts = {}
  if title then
    local title_latex = kast.latex.inlines({ kast.Str(title) })
    box_opts[#box_opts + 1] = "title=" .. title_latex
  end
  if border ~= "none" then
    box_opts[#box_opts + 1] = "borderline west={2pt}{0pt}{" .. color_name .. "}"
  end

  local body_latex = kast.latex.blocks(el.content)
  parts[#parts + 1] = kast.latex.env("asidebox", body_latex,
    { opts = box_opts, args = { color_name } })

  return kast.RawBlock("latex", table.concat(parts, "\n"))
end

local function html(el)
  local type_info, title, custom_color, border = validate(el)
  if not type_info then return nil end

  local aside_type = el.attributes["type"]
  local content = {}

  -- Optional title div — uses Plain (not Para) to avoid <p> margin
  -- collapse issues that break EPUB reader pagination
  local title_div = nil
  if title then
    title_div = kast.Div(
      { kast.Plain({ kast.Str(title) }) },
      kast.Attr("", { "aside-title" })
    )
    content[#content + 1] = title_div
  end

  for _, block in ipairs(el.content) do
    content[#content + 1] = block
  end

  local classes = { "aside", "aside-" .. aside_type }
  if border == "none" then
    classes[#classes + 1] = "aside-no-border"
  end

  local wrapper = kast.Div(content, kast.Attr("", classes))

  if custom_color then
    local bg = lighten_hex(custom_color)
    wrapper.attributes["style"] = "border-left-color: " .. custom_color
      .. "; background-color: " .. bg .. ";"
    if title_div then
      title_div.attributes["style"] = "color: " .. custom_color .. ";"
    end
  end

  -- Clear consumed attributes
  el.attributes["type"] = nil
  el.attributes["title"] = nil
  el.attributes["color"] = nil
  el.attributes["border"] = nil

  return wrapper
end

local function docx(el)
  local type_info, title = validate(el)
  if not type_info then return nil end

  -- Title as bold first paragraph, content follows — all in Aside style
  local content = {}
  if title then
    content[#content + 1] = kast.Para({ kast.Strong({ kast.Str(title) }) })
  end

  for _, block in ipairs(el.content) do
    content[#content + 1] = block
  end

  local wrapper = kast.Div(content, kast.Attr("", {}))
  wrapper.attributes["custom-style"] = "Aside"
  return wrapper
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
