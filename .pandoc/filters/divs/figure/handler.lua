-- Transforms ::: figure divs and standalone images into styled figures
-- with explicit sizing control. The div handler moves width from Pandoc
-- image attribute syntax to a clean div attribute; the Figure handler
-- intercepts standalone images to prevent LaTeX float placement.
-- See README.md for usage. No macros.tex needed — the caption package
-- lives in base-style.tex (global). Alignment is handled by composing
-- the align handler via shortcuts (e.g. aligned-figure).

local kast = ks_require("ast")

--- Find the first Image inline in block content.
--- Handles Para [Image], Plain [Image], and Figure > (recurse) wrappers.
local function find_image(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Para" or block.t == "Plain" then
      for _, inline in ipairs(block.content) do
        if inline.t == "Image" then return inline end
      end
    elseif block.t == "Figure" then
      return find_image(block.content)
    end
  end
end

--- Convert percentage width to LaTeX \textwidth fraction.
--- "50%" becomes "0.50\textwidth"; other units pass through unchanged.
local function width_to_latex(w)
  local pct = w:match("^(%d+)%%$")
  if pct then
    return string.format("%.2f\\textwidth", tonumber(pct) / 100)
  end
  return w
end

--- Shared div validation. Returns image, width, identifier, caption_width or nil on error.
local function validate_div(el)
  local image = find_image(el.content)
  if not image then return nil end

  local width = el.attributes["width"] or image.attributes["width"]
  local id = el.identifier or ""
  local caption_width = el.attributes["caption-width"]
  if caption_width and caption_width ~= "full" then
    io.stderr:write("WARN: figure: unknown caption-width value '" .. caption_width .. "', ignoring\n")
    caption_width = nil
  end

  return image, width, id, caption_width
end

local function div_latex(el)
  local image, width, id, caption_width = validate_div(el)
  if not image then return nil end

  -- When width is set and caption-width is not "full", constrain the
  -- caption to image width via minipage: the minipage gets the explicit
  -- width and the image fills it with \linewidth.
  local use_minipage = width and caption_width ~= "full"

  local gfx_opts = {}
  if width then
    gfx_opts = { use_minipage and "width=\\linewidth" or ("width=" .. width_to_latex(width)) }
  end

  el.attributes["caption-width"] = nil

  local caption_text = kast.latex.inlines(image.caption)

  local parts = {}

  parts[#parts + 1] = kast.latex.command("includegraphics",
    { opts = gfx_opts, args = { kast.latex.escape_path(image.src) } })

  if caption_text ~= "" then
    parts[#parts + 1] = kast.latex.command("captionof", { args = { "figure", caption_text } })
  end

  if id ~= "" then
    local ok, label_err = kast.latex.check_label(id)
    if ok then
      parts[#parts + 1] = kast.latex.command("label", { args = { id } })
    else
      io.stderr:write("WARN: figure: " .. label_err .. "\n")
    end
  end

  -- Constrain the caption to image width by wrapping the figure body in a
  -- fixed-width minipage; the image fills it via \linewidth (set above).
  local body = table.concat(parts, "\n")
  if use_minipage then
    body = kast.latex.env("minipage", body, { args = { width_to_latex(width) } })
  end

  return kast.RawBlock("latex", body)
end

local function div_html(el)
  local image, width, id, caption_width = validate_div(el)
  if not image then return nil end

  if width then
    if caption_width == "full" then
      -- Unconstrained caption: width on the image, container is full-width
      image.attributes["width"] = width
    else
      -- Constrained caption: width on the container (like minipage),
      -- image fills it. Percentage widths inside display:table resolve
      -- against the containing block, not the table — so the width must
      -- go on the container to actually constrain.
      el.attributes["style"] = "width: " .. width
      image.attributes["width"] = nil
    end
  end

  if id ~= "" then
    el.identifier = id
  end

  local classes = { "figure" }
  if caption_width == "full" then
    classes[#classes + 1] = "caption-full"
  end

  el.classes = classes
  el.attributes["width"] = nil
  el.attributes["caption-width"] = nil

  return el
end

-- Pandoc native figure handling suffices for DOCX
local function default(_el)
  return nil
end

local function figure_latex(fig)
  local id = fig.identifier or ""
  local caption_text = ""
  if fig.caption and fig.caption.long then
    caption_text = kast.latex.blocks(fig.caption.long)
  end

  local blocks = kast.List{}
  blocks:extend(fig.content)
  if caption_text ~= "" then
    blocks:insert(kast.RawBlock("latex", kast.latex.command("captionof", { args = { "figure", caption_text } })))
  end
  if id ~= "" then
    local ok, label_err = kast.latex.check_label(id)
    if ok then
      blocks:insert(kast.RawBlock("latex", kast.latex.command("label", { args = { id } })))
    else
      io.stderr:write("WARN: figure: " .. label_err .. "\n")
    end
  end

  return blocks
end

return {
  div = {
    latex = div_latex,
    html = div_html,
    epub = div_html,
    docx = default,
    odt = default,
  },
  global = {
    Figure = {
      latex = figure_latex,
      default = default,
    },
  },
}
