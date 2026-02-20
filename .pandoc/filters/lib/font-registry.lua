-- font-registry.lua — Single source of truth for all Keystone font and size definitions
--
-- Both keystone.lua (document-wide fontfamily, CSS generation) and the font
-- handler (per-block/inline overrides) load this file via dofile(). Adding a
-- font or size means updating this one table — LaTeX declarations, CSS rules,
-- and handler lookups are all derived from it.
--
-- Size values map 1:1 to LaTeX's built-in size commands:
-- https://www.overleaf.com/learn/latex/Font_sizes,_families,_and_styles#Font_sizes
--
-- Keep in sync: when adding or removing a font or size, also update:
--   • filters/divs/font/README.md  (Supported families / sizes tables)

local registry = {
  sizes = {
    { name = "tiny",         latex = "\\tiny",         css = "0.6em" },
    { name = "scriptsize",   latex = "\\scriptsize",   css = "0.7em" },
    { name = "footnotesize", latex = "\\footnotesize", css = "0.8em" },
    { name = "small",        latex = "\\small",        css = "0.9em" },
    { name = "normalsize",   latex = "\\normalsize",   css = "1.0em" },
    { name = "large",        latex = "\\large",        css = "1.2em" },
    { name = "Large",        latex = "\\Large",        css = "1.44em" },
    { name = "LARGE",        latex = "\\LARGE",        css = "1.728em" },
    { name = "huge",         latex = "\\huge",         css = "2.074em" },
    { name = "Huge",         latex = "\\Huge",         css = "2.488em" },
  },
  fonts = {
    ["libertine"] = {
      main = {
        file = "LinLibertine_R.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/libertine/",
        bold = "LinLibertine_RB.otf",
        italic = "LinLibertine_RI.otf",
        bold_italic = "LinLibertine_RBI.otf",
      },
      sans = "biolinum",
      css = '"Linux Libertine", "Georgia", serif',
      command = "\\keystonelibertine",
    },
    ["biolinum"] = {
      main = {
        file = "LinBiolinum_R.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/libertine/",
        bold = "LinBiolinum_RB.otf",
        italic = "LinBiolinum_RI.otf",
        bold_italic = "LinBiolinum_RBO.otf",
      },
      css = '"Linux Biolinum", "Helvetica Neue", sans-serif',
      command = "\\keystonebiolinum",
    },
    ["dejavu-serif"] = {
      main = {
        file = "DejaVu Serif",
      },
      css = '"DejaVu Serif", "Georgia", serif',
      command = "\\keystonedejavuserif",
    },
    ["dejavu-sans"] = {
      main = {
        file = "DejaVu Sans",
      },
      css = '"DejaVu Sans", "Helvetica Neue", sans-serif',
      command = "\\keystonedejavusans",
    },
    ["dejavu-mono"] = {
      main = {
        file = "DejaVu Sans Mono",
      },
      css = '"DejaVu Sans Mono", "Courier New", monospace',
      command = "\\keystonedejavumono",
    },
    ["latin-modern"] = {
      main = {
        file = "lmroman10-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/lm/",
        bold = "lmroman10-bold.otf",
        italic = "lmroman10-italic.otf",
        bold_italic = "lmroman10-bolditalic.otf",
      },
      css = '"Latin Modern Roman", "Computer Modern", serif',
      command = "\\keystonelatinmodern",
    },
  },
}

--- Build fontspec option string for a font spec.
--- TeX Live fonts (with path) use [Path=...,BoldFont=...]{file}.
--- System fonts (without path) use just {name}.
---@param spec table  Font spec with file, path, bold, italic, bold_italic
---@return string options  The [...] portion (empty string if no options needed)
---@return string file     The {file} portion
function registry.fontspec_options(spec)
  if not spec.path then
    return "", spec.file
  end

  local parts = { "Path=" .. spec.path }
  if spec.bold then
    table.insert(parts, "BoldFont=" .. spec.bold)
  end
  if spec.italic then
    table.insert(parts, "ItalicFont=" .. spec.italic)
  end
  if spec.bold_italic then
    table.insert(parts, "BoldItalicFont=" .. spec.bold_italic)
  end

  return "[" .. table.concat(parts, ",\n  ") .. "]", spec.file
end

--- Build a \newfontfamily declaration for a registered font.
---@param name string  Registry key (e.g. "libertine")
---@return string|nil  LaTeX declaration, or nil if not found
function registry.newfontfamily(name)
  local font = registry.fonts[name]
  if not font then return nil end

  local options, file = registry.fontspec_options(font.main)
  return "\\newfontfamily" .. font.command .. options .. "{" .. file .. "}"
end

--- Build a \setmainfont declaration for a registered font.
---@param name string  Registry key
---@return string|nil  LaTeX declaration, or nil if not found
function registry.setmainfont(name)
  local font = registry.fonts[name]
  if not font then return nil end

  local options, file = registry.fontspec_options(font.main)
  return "\\setmainfont" .. options .. "{" .. file .. "}"
end

--- Build a \setsansfont declaration for a font's suite companion.
---@param name string  Registry key
---@return string|nil  LaTeX declaration, or nil if no sans companion
function registry.setsansfont(name)
  local font = registry.fonts[name]
  if not font or not font.sans then return nil end

  local companion = registry.fonts[font.sans]
  if not companion then return nil end

  local options, file = registry.fontspec_options(companion.main)
  return "\\setsansfont" .. options .. "{" .. file .. "}"
end

--- Build a CSS rule for the font handler's EPUB/HTML class.
--- Returns e.g. '.font-family-libertine { font-family: "Linux Libertine", "Georgia", serif; }'
---@param name string  Registry key
---@return string|nil  CSS rule, or nil if not found
function registry.css_rule(name)
  local font = registry.fonts[name]
  if not font then return nil end

  return ".font-family-" .. name .. " { font-family: " .. font.css .. "; }"
end

--- Build a lookup table mapping size names to LaTeX commands.
---@return table<string, string>  { "tiny" = "\\tiny", ... }
function registry.latex_size_map()
  local map = {}
  for _, entry in ipairs(registry.sizes) do
    map[entry.name] = entry.latex
  end
  return map
end

--- Build CSS rules for all registered sizes.
---@return string[]  Array of CSS rule strings
function registry.css_size_rules()
  local rules = {}
  for _, entry in ipairs(registry.sizes) do
    table.insert(rules,
      ".font-size-" .. entry.name .. " { font-size: " .. entry.css .. "; }")
  end
  return rules
end

return registry
