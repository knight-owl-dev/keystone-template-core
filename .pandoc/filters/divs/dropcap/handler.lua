-- Applies drop-cap styling to the first letter of a paragraph.
-- Supports both span syntax ([T]{.dropcap}) for explicit control and
-- div syntax (::: dropcap) for automatic first-character extraction.
-- See README.md for usage. LaTeX uses the lettrine package (macros.tex).

local font_registry = ks_require("font-registry")
local kast = ks_require("ast")

local family_map = {}
for name, font in pairs(font_registry.fonts) do
  family_map[name] = font.command
end

--- Extract the first UTF-8 character from a string.
local function first_utf8_char(s)
  if s == "" then return nil, s end
  local pos = utf8.offset(s, 2)
  if not pos then return s, "" end
  return s:sub(1, pos - 1), s:sub(pos)
end

--- Validate the lines attribute. Returns the numeric value or nil on error.
local function validate_lines(el, report)
  local raw = el.attributes["lines"]
  if not raw then return 3 end
  local n = tonumber(raw)
  if not n or n ~= math.floor(n) or n < 1 then
    report.warn({
      problem = "dropcap: invalid lines '" .. raw .. "'",
      because = "A lines value is a positive integer.",
      see = "https://keystone.knight-owl.dev/errors/invalid-value/",
    })
    return nil
  end
  return n
end

--- Resolve the optional font-family attribute. Returns the LaTeX command (or
--- nil if no font-family is set), or false on validation error.
local function resolve_family(el, report)
  local family = el.attributes["font-family"]
  if not family then return nil end
  local key = font_registry.canonical(family)
  local cmd = family_map[key]
  if not cmd then
    report.warn({
      problem = "dropcap: unknown family '" .. family .. "'",
      see = "https://keystone.knight-owl.dev/errors/invalid-value/",
    })
    return false
  end
  return cmd, key
end

--- Find the first Para block and validate it starts with a Str inline.
--- Returns para, para_idx or nil on error.
local function find_first_para(el, report)
  for i, block in ipairs(el.content) do
    if block.t == "Para" then
      if #block.content == 0 or block.content[1].t ~= "Str" then
        report.warn({
          problem = "dropcap: first inline is not a Str",
          remedy = "Use span syntax for this case.",
        })
        return nil
      end
      return block, i
    end
  end
  report.warn({ problem = "dropcap: no paragraph found in div content" })
  return nil
end

-- Both span paths reject empty content identically.
local function has_span_content(el, report)
  if #el.content == 0 then
    report.warn({ problem = "dropcap: empty span content" })
    return false
  end
  return true
end

-- Both div paths pull the first character off the leading Str the same way.
local function first_char_of(para, report)
  local char, rest = first_utf8_char(para.content[1].text)
  if not char then
    report.warn({ problem = "dropcap: could not extract first character" })
    return nil
  end
  return char, rest
end

local function span_latex(el, report)
  if not has_span_content(el, report) then return nil end

  local lines = validate_lines(el, report)
  if not lines then return nil end

  local family_cmd = resolve_family(el, report)
  if family_cmd == false then return nil end

  local letter_latex = kast.latex.inlines(el.content)

  -- A font family wraps the letter in its own brace group so the family
  -- switch is scoped to the drop cap; the trailing {} is lettrine's empty
  -- "rest of word" argument.
  local first = family_cmd and ("{" .. family_cmd .. " " .. letter_latex .. "}") or letter_latex
  local latex = kast.latex.command("lettrine", { opts = { "lines=" .. lines }, args = { first, "" } })

  return kast.RawInline("latex", latex)
end

local function span_html(el, report)
  if not has_span_content(el, report) then return nil end

  local lines = validate_lines(el, report)
  if not lines then return nil end

  local _, family_key = resolve_family(el, report)
  if _ == false then return nil end

  local classes = { "dropcap" }
  if family_key then
    classes[#classes + 1] = "font-family-" .. family_key
  end
  el.classes = classes
  el.attributes["style"] = "--dropcap-lines: " .. lines
  el.attributes["lines"] = nil
  el.attributes["font-family"] = nil
  return el
end

local function div_latex(el, report)
  local para = find_first_para(el, report)
  if not para then return nil end

  local char, rest = first_char_of(para, report)
  if not char then return nil end

  local lines = validate_lines(el, report)
  if not lines then return nil end

  local family_cmd = resolve_family(el, report)
  if family_cmd == false then return nil end

  local char_latex = kast.latex.inlines({ kast.Str(char) })
  -- See span_latex: the family brace-group scopes the family switch to the
  -- drop cap; the trailing {} is lettrine's empty "rest of word" argument.
  local first = family_cmd and ("{" .. family_cmd .. " " .. char_latex .. "}") or char_latex
  local latex = kast.latex.command("lettrine", { opts = { "lines=" .. lines }, args = { first, "" } })

  -- Update or remove the first Str inline
  if rest == "" then
    table.remove(para.content, 1)
  else
    para.content[1] = kast.Str(rest)
  end

  -- Prepend the lettrine RawInline to the paragraph
  table.insert(para.content, 1, kast.RawInline("latex", latex))

  -- Return unwrapped content (remove the div wrapper)
  return el.content
end

local function div_html(el, report)
  local para = find_first_para(el, report)
  if not para then return nil end

  local char, rest = first_char_of(para, report)
  if not char then return nil end

  local lines = validate_lines(el, report)
  if not lines then return nil end

  local _, family_key = resolve_family(el, report)
  if _ == false then return nil end

  local classes = { "dropcap" }
  if family_key then
    classes[#classes + 1] = "font-family-" .. family_key
  end

  local dropcap_span = kast.Span(
    { kast.Str(char) },
    kast.Attr("", classes, { style = "--dropcap-lines: " .. lines })
  )

  -- Update or remove the first Str inline
  if rest == "" then
    table.remove(para.content, 1)
  else
    para.content[1] = kast.Str(rest)
  end

  -- Prepend the dropcap span
  table.insert(para.content, 1, dropcap_span)

  -- Return unwrapped content (remove the div wrapper)
  return el.content
end

-- Normal first letter in DOCX — passthrough
local function default(_el)
  return nil
end

return {
  span = {
    latex = span_latex,
    html = span_html,
    epub = span_html,
    docx = default,
    odt = default,
  },
  div = {
    latex = div_latex,
    html = div_html,
    epub = div_html,
    docx = default,
    odt = default,
  },
}
