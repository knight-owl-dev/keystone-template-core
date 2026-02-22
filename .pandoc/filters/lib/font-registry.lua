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
--
-- Font entry properties:
--
--   main.file        (required) Font filename (TeX Live OTF) or name (system font).
--                    Used as the fontspec {file} argument and the @font-face regular source.
--
--   main.path        (optional) Absolute path to the font directory. Present for TeX Live
--                    fonts, absent for system fonts. Determines two behaviors:
--                    • LaTeX: fontspec uses [Path=...]{file} instead of {name}
--                    • EPUB: font files are embedded and @font-face CSS is generated.
--                    Fonts without path use CSS fallback stacks only in EPUB.
--
--   main.bold        (optional) Bold variant filename. TeX Live fonts only.
--   main.italic      (optional) Italic variant filename. TeX Live fonts only.
--   main.bold_italic (optional) Bold-italic variant filename. TeX Live fonts only.
--                    When present, fontspec maps variants explicitly. When absent,
--                    fontspec auto-discovers variants (system fonts) or the font has
--                    no variants. EPUB embeds each variant as a separate @font-face rule.
--
--   css              (required) EPUB/HTML font-family fallback stack. The first quoted
--                    value is the canonical font name used in @font-face declarations.
--                    Example: '"Linux Libertine", "Georgia", serif'
--
--   command          (required) LaTeX command name. Must be unique across the registry.
--                    Convention: \keystone + key with hyphens removed.
--                    Used by \newfontfamily for per-block/inline overrides.
--
--   sans             (optional) Registry key of a sans-serif companion from the same
--                    type design family. When the font is set as the document main font
--                    (via fontfamily metadata), keystone.lua also emits \setsansfont with
--                    the companion. Omit for: sans-serif fonts, monospace fonts, and serif
--                    fonts without a designated typographic partner.

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
    ["eb-garamond"] = {
      main = {
        file = "EBGaramond-Regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/ebgaramond/",
        bold = "EBGaramond-Bold.otf",
        italic = "EBGaramond-Italic.otf",
        bold_italic = "EBGaramond-BoldItalic.otf",
      },
      css = '"EB Garamond", "Garamond", "Georgia", serif',
      command = "\\keystoneebgaramond",
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
    ["tex-gyre-adventor"] = {
      main = {
        file = "texgyreadventor-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyreadventor-bold.otf",
        italic = "texgyreadventor-italic.otf",
        bold_italic = "texgyreadventor-bolditalic.otf",
      },
      css = '"TeX Gyre Adventor", "Avant Garde", sans-serif',
      command = "\\keystonetexgyreadventor",
    },
    ["tex-gyre-bonum"] = {
      main = {
        file = "texgyrebonum-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyrebonum-bold.otf",
        italic = "texgyrebonum-italic.otf",
        bold_italic = "texgyrebonum-bolditalic.otf",
      },
      sans = "tex-gyre-adventor",
      css = '"TeX Gyre Bonum", "Bookman Old Style", serif',
      command = "\\keystonetexgyrebonum",
    },
    ["tex-gyre-cursor"] = {
      main = {
        file = "texgyrecursor-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyrecursor-bold.otf",
        italic = "texgyrecursor-italic.otf",
        bold_italic = "texgyrecursor-bolditalic.otf",
      },
      css = '"TeX Gyre Cursor", "Courier New", monospace',
      command = "\\keystonetexgyrecursor",
    },
    ["tex-gyre-heros"] = {
      main = {
        file = "texgyreheros-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyreheros-bold.otf",
        italic = "texgyreheros-italic.otf",
        bold_italic = "texgyreheros-bolditalic.otf",
      },
      css = '"TeX Gyre Heros", "Helvetica", "Arial", sans-serif',
      command = "\\keystonetexgyreheros",
    },
    ["tex-gyre-pagella"] = {
      main = {
        file = "texgyrepagella-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyrepagella-bold.otf",
        italic = "texgyrepagella-italic.otf",
        bold_italic = "texgyrepagella-bolditalic.otf",
      },
      sans = "tex-gyre-heros",
      css = '"TeX Gyre Pagella", "Palatino Linotype", "Book Antiqua", serif',
      command = "\\keystonetexgyrepagella",
    },
    ["tex-gyre-schola"] = {
      main = {
        file = "texgyreschola-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyreschola-bold.otf",
        italic = "texgyreschola-italic.otf",
        bold_italic = "texgyreschola-bolditalic.otf",
      },
      css = '"TeX Gyre Schola", "Century Schoolbook", serif',
      command = "\\keystonetexgyreschola",
    },
    ["tex-gyre-termes"] = {
      main = {
        file = "texgyretermes-regular.otf",
        path = "/opt/texlive/texdir/texmf-dist/fonts/opentype/public/tex-gyre/",
        bold = "texgyretermes-bold.otf",
        italic = "texgyretermes-italic.otf",
        bold_italic = "texgyretermes-bolditalic.otf",
      },
      sans = "tex-gyre-heros",
      css = '"TeX Gyre Termes", "Times New Roman", serif',
      command = "\\keystonetexgyretermes",
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

--- Build the full LaTeX font preamble for header-includes.
--- If fontfamily is a registry key, emits \setmainfont (+ optional \setsansfont)
--- and reports consumed=true so the caller can nil out meta.fontfamily.
--- Always emits sorted \newfontfamily declarations for every registered font.
---@param fontfamily string|nil  Document fontfamily metadata value
---@return string  LaTeX preamble text (may be empty)
---@return boolean  Whether fontfamily was consumed (is a registry key)
function registry.latex_preamble(fontfamily)
  local decls = {}
  local consumed = false

  if fontfamily and registry.fonts[fontfamily] then
    table.insert(decls, registry.setmainfont(fontfamily))

    local sans = registry.setsansfont(fontfamily)
    if sans then
      table.insert(decls, sans)
    end

    consumed = true
  end

  -- \newfontfamily for ALL registered fonts (sorted for reproducible output).
  local sorted_keys = {}
  for key in pairs(registry.fonts) do
    table.insert(sorted_keys, key)
  end
  table.sort(sorted_keys)

  for _, key in ipairs(sorted_keys) do
    table.insert(decls, registry.newfontfamily(key))
  end

  return table.concat(decls, "\n"), consumed
end

--- Build the set of used registry keys for selective @font-face emission.
--- Includes fontfamily (+ its sans companion) and any content_refs that are
--- valid registry keys. Unknown keys are silently dropped.
---@param fontfamily string|nil      Document fontfamily metadata value
---@param content_refs table|nil     Set of family keys found in content (keys are lowercase strings)
---@return table<string, boolean>    Set of used registry keys
function registry.build_used_fonts(fontfamily, content_refs)
  local used = {}

  if fontfamily and registry.fonts[fontfamily] then
    used[fontfamily] = true
    local companion = registry.fonts[fontfamily].sans
    if companion then used[companion] = true end
  end

  if content_refs then
    for key in pairs(content_refs) do
      if registry.fonts[key] then
        used[key] = true
      end
    end
  end

  return used
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

--- Extract the primary font-family name from a font's css field.
--- Returns the first double-quoted value, used as the font-family in @font-face.
--- Example: '"Linux Libertine", "Georgia", serif' → "Linux Libertine"
---@param name string  Registry key
---@return string|nil  Font-family name, or nil if not found
function registry.css_font_family_name(name)
  local font = registry.fonts[name]
  if not font then return nil end

  return font.css:match('"([^"]+)"')
end

--- Build @font-face CSS rules and file paths for EPUB font embedding.
--- Returns two tables for fonts with explicit path (TeX Live):
---   1. Array of @font-face CSS rule strings (one per variant)
---   2. Array of absolute file paths for epub-fonts metadata
--- Returns nil, nil for system fonts (no path) — they use CSS fallback only.
---@param name string  Registry key
---@return string[]|nil  @font-face CSS rules
---@return string[]|nil  Absolute file paths
function registry.epub_font_faces(name)
  local font = registry.fonts[name]
  if not font or not font.main.path then return nil, nil end

  local family = registry.css_font_family_name(name)
  if not family then return nil, nil end

  local variants = {
    { field = "file",        style = "normal", weight = "normal" },
    { field = "bold",        style = "normal", weight = "bold" },
    { field = "italic",      style = "italic", weight = "normal" },
    { field = "bold_italic", style = "italic", weight = "bold" },
  }

  local rules = {}
  local paths = {}

  for _, v in ipairs(variants) do
    local filename = font.main[v.field]
    if filename then
      table.insert(rules, "@font-face {\n"
        .. '  font-family: "' .. family .. '";\n'
        .. "  font-style: " .. v.style .. ";\n"
        .. "  font-weight: " .. v.weight .. ";\n"
        .. '  src: url("../fonts/' .. filename .. '");\n'
        .. "}")
      table.insert(paths, font.main.path .. filename)
    end
  end

  if #rules == 0 then return nil, nil end
  return rules, paths
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

--- Build the complete CSS stylesheet for EPUB/HTML output.
--- Includes body font (if fontfamily is a registry key), font-family class
--- rules, font-size class rules, and @font-face declarations (EPUB only).
--- When used_fonts is a table (set of keys), @font-face rules are generated
--- only for fonts in the set. When nil, generates for all (backward compatible).
--- CSS class rules stay unfiltered — they're one line each, and a class for a
--- non-embedded font still works via CSS fallback stack.
---@param fontfamily string|nil  Document fontfamily metadata value
---@param format string          Pandoc FORMAT string (e.g. "epub", "html5")
---@param used_fonts table|nil   Set of registry keys to emit @font-face for
---@return string|nil  Complete CSS text, or nil if no rules generated
function registry.css_stylesheet(fontfamily, format, used_fonts)
  local rules = {}

  -- Body font: the CSS equivalent of \setmainfont for LaTeX.
  if fontfamily and registry.fonts[fontfamily] then
    table.insert(rules,
      "body { font-family: " .. registry.fonts[fontfamily].css .. "; }")
  end

  -- Font-family class rules for div/span handler overrides.
  -- Sort keys for reproducible output.
  local sorted_keys = {}
  for key in pairs(registry.fonts) do
    table.insert(sorted_keys, key)
  end
  table.sort(sorted_keys)

  for _, key in ipairs(sorted_keys) do
    local rule = registry.css_rule(key)
    if rule then table.insert(rules, rule) end
  end

  -- Font-size class rules.
  for _, rule in ipairs(registry.css_size_rules()) do
    table.insert(rules, rule)
  end

  -- @font-face rules for EPUB font embedding. System fonts (no path) use
  -- CSS fallback only. The font files are embedded via --epub-embed-font
  -- flags in publish.sh. When used_fonts is provided, only fonts in the
  -- set get @font-face rules — the rest rely on CSS fallback stacks.
  if format:match("epub") then
    for _, key in ipairs(sorted_keys) do
      if not used_fonts or used_fonts[key] then
        local face_rules = registry.epub_font_faces(key)
        if face_rules then
          for _, rule in ipairs(face_rules) do
            table.insert(rules, rule)
          end
        end
      end
    end
  end

  if #rules == 0 then return nil end
  return table.concat(rules, "\n") .. "\n"
end

return registry
