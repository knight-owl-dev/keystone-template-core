-- font-registry.lua — Single source of truth for all font and size definitions
--
-- This module is the merged registry that all downstream code consumes.
-- Built-in Keystone fonts are defined in the table below; user-supplied fonts
-- (from fonts/fonts-registry.yaml) are validated and merged at load time.
-- The result is a single registry — no consumer distinguishes between the two.
--
-- Both keystone.lua (document-wide fontfamily, CSS generation) and the font
-- handler (per-block/inline overrides) load this file via ks_require. LaTeX
-- declarations, CSS rules, and handler lookups are all derived from it.
--
-- Size values map 1:1 to LaTeX's built-in size commands:
-- https://www.overleaf.com/learn/latex/Font_sizes,_families,_and_styles#Font_sizes
--
-- Keep in sync: when adding or removing a font or size, also update:
--   • filters/divs/font/README.md  (Supported families / sizes tables)
--   • the public manual's Built-in fonts table (Typography & fonts)
--   • a font from a new TeX Live package: add the package to the font-extractor
--     stage in the runtime Dockerfile (its registry-referenced files are then
--     staged automatically) and license it in NOTICE.md
--
-- Font entry properties:
--
--   main.file        (required) Font filename (OTF/TTF).
--                    Used as the fontspec {file} argument and the @font-face regular source.
--
--   main.path        (required) Absolute path to the font directory; built-ins declare
--                    it, user fonts default to KEYSTONE_USER_FONTS_DIR. Every font is
--                    embedded, so this locates the files for fontspec [Path=...]{file},
--                    EPUB embedding, and @font-face generation.
--
--   main.bold        (optional) Bold variant filename.
--   main.italic      (optional) Italic variant filename.
--   main.bold_italic (optional) Bold-italic variant filename.
--                    Present variants map explicitly via fontspec; each is embedded as
--                    a separate @font-face rule. A font may ship regular-only.
--
--   css              (required) EPUB/HTML font-family fallback stack. The first quoted
--                    value is the canonical font name used in @font-face declarations.
--                    Example: '"Linux Libertine", "Georgia", serif'
--
--   command          (derived) LaTeX \newfontfamily command for per-block/inline
--                    overrides. Derived from the key, never authored; unique
--                    across the registry (see the derivation).
--
--   sans             (optional) Registry key of a sans-serif companion from the same
--                    type design family. When the font is set as the document main font
--                    (via fontfamily metadata), keystone.lua also emits \setsansfont with
--                    the companion. Omit for: sans-serif fonts, monospace fonts, and serif
--                    fonts without a designated typographic partner.
--
-- Environment (set by publish.sh):
--   KEYSTONE_USER_FONTS     — path to the preprocessed user font registry Lua table
--   KEYSTONE_USER_FONTS_DIR — container path to user font files (default main.path)
-- cspell:ignore dejavuserif

local errors = ks_require("errors")
local collections = ks_require("collections")
local env_io = ks_require("env-io")
local identifiers = ks_require("identifiers")
local kast = ks_require("ast")

-- Built-in font files live under this owned root in the runtime image; the
-- Docker font-extractor stages them here (see .docker/extract-fonts.sh).
-- Distinct from KEYSTONE_USER_FONTS_DIR (/keystone/fonts/), where user-mounted
-- fonts land.
local FONTS_ROOT = "/opt/keystone/fonts/"

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
        path = FONTS_ROOT .. "opentype/public/libertine/",
        bold = "LinLibertine_RB.otf",
        italic = "LinLibertine_RI.otf",
        bold_italic = "LinLibertine_RBI.otf",
      },
      sans = "biolinum",
      css = '"Linux Libertine", "Georgia", serif',
    },
    ["biolinum"] = {
      main = {
        file = "LinBiolinum_R.otf",
        path = FONTS_ROOT .. "opentype/public/libertine/",
        bold = "LinBiolinum_RB.otf",
        italic = "LinBiolinum_RI.otf",
        bold_italic = "LinBiolinum_RBO.otf",
      },
      css = '"Linux Biolinum", "Helvetica Neue", sans-serif',
    },
    -- The TeX Live `dejavu` package (TrueType): wide Unicode coverage for code.
    ["dejavu-serif"] = {
      main = {
        file = "DejaVuSerif.ttf",
        path = FONTS_ROOT .. "truetype/public/dejavu/",
        bold = "DejaVuSerif-Bold.ttf",
        italic = "DejaVuSerif-Italic.ttf",
        bold_italic = "DejaVuSerif-BoldItalic.ttf",
      },
      css = '"DejaVu Serif", "Georgia", serif',
    },
    ["dejavu-sans"] = {
      main = {
        file = "DejaVuSans.ttf",
        path = FONTS_ROOT .. "truetype/public/dejavu/",
        bold = "DejaVuSans-Bold.ttf",
        italic = "DejaVuSans-Oblique.ttf",
        bold_italic = "DejaVuSans-BoldOblique.ttf",
      },
      css = '"DejaVu Sans", "Helvetica Neue", sans-serif',
    },
    ["dejavu-mono"] = {
      main = {
        file = "DejaVuSansMono.ttf",
        path = FONTS_ROOT .. "truetype/public/dejavu/",
        bold = "DejaVuSansMono-Bold.ttf",
        italic = "DejaVuSansMono-Oblique.ttf",
        bold_italic = "DejaVuSansMono-BoldOblique.ttf",
      },
      css = '"DejaVu Sans Mono", "Courier New", monospace',
    },
    ["eb-garamond"] = {
      main = {
        file = "EBGaramond-Regular.otf",
        path = FONTS_ROOT .. "opentype/public/ebgaramond/",
        bold = "EBGaramond-Bold.otf",
        italic = "EBGaramond-Italic.otf",
        bold_italic = "EBGaramond-BoldItalic.otf",
      },
      css = '"EB Garamond", "Garamond", "Georgia", serif',
    },
    ["latin-modern"] = {
      main = {
        file = "lmroman10-regular.otf",
        path = FONTS_ROOT .. "opentype/public/lm/",
        bold = "lmroman10-bold.otf",
        italic = "lmroman10-italic.otf",
        bold_italic = "lmroman10-bolditalic.otf",
      },
      css = '"Latin Modern Roman", "Computer Modern", serif',
    },
    -- lmmonolt (Light cut): the only Latin Modern Mono family with a real bold —
    -- lmmono10 ships regular + italic only.
    ["latin-modern-mono"] = {
      main = {
        file = "lmmonolt10-regular.otf",
        path = FONTS_ROOT .. "opentype/public/lm/",
        bold = "lmmonolt10-bold.otf",
        italic = "lmmonolt10-oblique.otf",
        bold_italic = "lmmonolt10-boldoblique.otf",
      },
      css = '"Latin Modern Mono", "Courier New", monospace',
    },
    -- No system fallback (a generic only), so DOCX/ODT degrade like the ornaments.
    ["latin-modern-math"] = {
      main = {
        file = "latinmodern-math.otf",
        path = FONTS_ROOT .. "opentype/public/lm-math/",
      },
      css = '"Latin Modern Math", serif',
    },
    ["tex-gyre-adventor"] = {
      main = {
        file = "texgyreadventor-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyreadventor-bold.otf",
        italic = "texgyreadventor-italic.otf",
        bold_italic = "texgyreadventor-bolditalic.otf",
      },
      css = '"TeX Gyre Adventor", "Avant Garde", sans-serif',
    },
    ["tex-gyre-bonum"] = {
      main = {
        file = "texgyrebonum-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyrebonum-bold.otf",
        italic = "texgyrebonum-italic.otf",
        bold_italic = "texgyrebonum-bolditalic.otf",
      },
      sans = "tex-gyre-adventor",
      css = '"TeX Gyre Bonum", "Bookman Old Style", serif',
    },
    ["tex-gyre-cursor"] = {
      main = {
        file = "texgyrecursor-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyrecursor-bold.otf",
        italic = "texgyrecursor-italic.otf",
        bold_italic = "texgyrecursor-bolditalic.otf",
      },
      css = '"TeX Gyre Cursor", "Courier New", monospace',
    },
    ["tex-gyre-heros"] = {
      main = {
        file = "texgyreheros-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyreheros-bold.otf",
        italic = "texgyreheros-italic.otf",
        bold_italic = "texgyreheros-bolditalic.otf",
      },
      css = '"TeX Gyre Heros", "Helvetica", "Arial", sans-serif',
    },
    ["tex-gyre-pagella"] = {
      main = {
        file = "texgyrepagella-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyrepagella-bold.otf",
        italic = "texgyrepagella-italic.otf",
        bold_italic = "texgyrepagella-bolditalic.otf",
      },
      sans = "tex-gyre-heros",
      css = '"TeX Gyre Pagella", "Palatino Linotype", "Book Antiqua", serif',
    },
    ["tex-gyre-schola"] = {
      main = {
        file = "texgyreschola-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyreschola-bold.otf",
        italic = "texgyreschola-italic.otf",
        bold_italic = "texgyreschola-bolditalic.otf",
      },
      css = '"TeX Gyre Schola", "Century Schoolbook", serif',
    },
    ["tex-gyre-termes"] = {
      main = {
        file = "texgyretermes-regular.otf",
        path = FONTS_ROOT .. "opentype/public/tex-gyre/",
        bold = "texgyretermes-bold.otf",
        italic = "texgyretermes-italic.otf",
        bold_italic = "texgyretermes-bolditalic.otf",
      },
      sans = "tex-gyre-heros",
      css = '"TeX Gyre Termes", "Times New Roman", serif',
    },
    -- ── Modern monospace code faces ────────────────────────────────────
    -- The TeX Live `noto` package (TrueType). Regular + bold only — Google
    -- ships no italic cut, so an italic request has no true italic: PDF falls
    -- back to the upright regular, EPUB synthesizes a slant.
    ["noto-mono"] = {
      main = {
        file = "NotoSansMono-Regular.ttf",
        path = FONTS_ROOT .. "truetype/google/noto/",
        bold = "NotoSansMono-Bold.ttf",
      },
      css = '"Noto Sans Mono", "Courier New", monospace',
    },
    -- The TeX Live `sourcecodepro` package (OpenType). Adobe names the italic
    -- cut "RegularIt", so the italic field looks unlike the others.
    ["source-code-pro"] = {
      main = {
        file = "SourceCodePro-Regular.otf",
        path = FONTS_ROOT .. "opentype/adobe/sourcecodepro/",
        bold = "SourceCodePro-Bold.otf",
        italic = "SourceCodePro-RegularIt.otf",
        bold_italic = "SourceCodePro-BoldIt.otf",
      },
      css = '"Source Code Pro", "Courier New", monospace',
    },
    -- ── Ornamental / decorative fonts ──────────────────────────────────
    -- Single-variant symbol fonts: fleurons, manicules, floral printer's
    -- ornaments. No bold/italic variants — only main.file. css carries a
    -- bare generic fallback (serif) and no system fallback: there is no
    -- web-safe ornament font, so system_fallback() returns nil and DOCX/ODT
    -- degrade gracefully (no custom-style; the glyph passes through in the
    -- document font). PDF embeds via fontspec Path=; EPUB embeds the OTF.
    -- Glyph access differs per font: most ornaments sit on Latin letters/digits,
    -- though fourier-ornaments also carries ❦ ❧ ☙ at their Unicode codepoints.
    -- Per-font glyph tables live in the public manual:
    --   https://keystone.knight-owl.dev/writing/ornaments/
    ["fourier-ornaments"] = {
      main = {
        file = "FourierOrns-Regular.otf",
        path = FONTS_ROOT .. "opentype/public/fourier/",
      },
      css = '"Fourier Ornaments", serif',
    },
    ["imfell-flowers-1"] = {
      main = {
        file = "FeFlow1.otf",
        path = FONTS_ROOT .. "opentype/iginomarini/imfellenglish/",
      },
      css = '"IM Fell Flowers 1", serif',
    },
    ["imfell-flowers-2"] = {
      main = {
        file = "FeFlow2.otf",
        path = FONTS_ROOT .. "opentype/iginomarini/imfellenglish/",
      },
      css = '"IM Fell Flowers 2", serif',
    },
  },
}

-- ── Derived command names ────────────────────────────────────────────
-- Each font's LaTeX \newfontfamily command is derived from its key, never
-- authored: \keystonefont + the key reduced to a control-word body
-- (kast.latex.control_word), made unique against the others (identifiers.make_unique).
-- The `font` infix namespaces them: handler macros are \keystone<name> (e.g.
-- \keystonesource) without the infix, so \keystonefont<name> stays clear of them.
-- (The make_unique guard sees only other fonts, not those preamble macros.)
-- The key's shape is unconstrained, so distinct keys can reduce to the same base
-- (dejavu-serif, dejavuserif both → \keystonefontdejavuserif); suffix disambiguates.
local function derive_command(key, seen)
  return identifiers.make_unique(seen, "\\keystonefont" .. kast.latex.control_word(key))
end

-- Built-in keys are curated collision-free, so deriving them first claims the
-- canonical base names; user fonts (below) then suffix around the built-ins
-- rather than displacing one. Sorted for reproducible suffix assignment.
-- builtin_keys is captured here, before any user fonts merge in, so
-- builtin_font_files() enumerates only the fonts baked into the image.
local builtin_keys = {}
local seen_commands = {}
for key, entry in collections.sorted_pairs(registry.fonts) do
  entry.command = derive_command(key, seen_commands)
  table.insert(builtin_keys, key)
end

-- ── User-supplied fonts ──────────────────────────────────────────────
-- Merge user fonts from the preprocessed Lua table at KEYSTONE_USER_FONTS.
-- publish.sh converts fonts/fonts-registry.yaml → Lua via yq and exports
-- KEYSTONE_USER_FONTS (path to the Lua table) and KEYSTONE_USER_FONTS_DIR
-- (container path to font files, used as default main.path). Each entry is
-- validated (required fields, file existence) before insertion. Built-in
-- keys cannot be overridden — collisions warn and skip.

local user_fonts_dir = env_io.optional_env("KEYSTONE_USER_FONTS_DIR")
local user_fonts_path = env_io.optional_env("KEYSTONE_USER_FONTS")
if user_fonts_path then
  local loader, load_err = loadfile(user_fonts_path, "t", {})
  if not loader then
    errors.fatal("font-registry: failed to load user fonts: " .. load_err)
  end
  -- errors.fatal exits, so loader is non-nil here; the analyzer can't see
  -- through the lib call the way it did the former bare error().
  ---@diagnostic disable-next-line: need-check-nil
  local user_data = loader()

  if user_data then
    for key, entry in collections.sorted_pairs(user_data) do
      -- Collision guard: built-in fonts take precedence
      if registry.fonts[key] then
        errors.warn("user font '" .. key .. "' collides with built-in — skipping")
      elseif not entry.main or not entry.main.file then
        errors.warn("user font '" .. key .. "' missing main.file — skipping")
      elseif not entry.css then
        errors.warn("user font '" .. key .. "' missing css — skipping")
      elseif not (entry.main.path or user_fonts_dir) then
        -- Every font must be path-bearing; without an explicit path and no
        -- mount point to default to, there is nothing to embed.
        errors.warn("user font '" .. key
          .. "' has no path and KEYSTONE_USER_FONTS_DIR is unset — skipping")
      else
        -- Default path to the user fonts mount point
        if not entry.main.path then
          entry.main.path = user_fonts_dir
        end

        -- Validate font files exist on disk
        local missing = false
        local variants = { "file", "bold", "italic", "bold_italic" }
        for _, variant in ipairs(variants) do
          local filename = entry.main[variant]
          if filename then
            local fh = io.open(entry.main.path .. filename, "r")
            if fh then
              fh:close()
            else
              errors.warn("user font '" .. key .. "' — " .. variant
                .. " file not found: " .. entry.main.path .. filename .. " — skipping")
              missing = true
              break
            end
          end
        end

        if not missing then
          -- command is derived, not author-settable; warn on a stray value
          -- rather than dropping it silently.
          if entry.command then
            errors.warn("user font '" .. key
              .. "' sets 'command', which is derived — ignoring")
          end
          -- Derive against the built-in-seeded set, so a key that reduces to a
          -- built-in's command gets a suffix instead of displacing it.
          entry.command = derive_command(key, seen_commands)
          registry.fonts[key] = entry
        end
      end
    end
  end
end

-- ── Owned default ────────────────────────────────────────────────────
-- Keystone's default document font. Unset and unknown fontfamily values
-- resolve here, so output never rides the engine's implicit default (which can
-- shift across engine/Pandoc versions). Must be a built-in key — user fonts
-- may be absent.
registry.default = "latin-modern"

-- Keystone's default code/monospace font. Unset and unknown monofont values
-- resolve here, so PDF/EPUB never ride XeLaTeX's implicit \ttfamily choice.
-- Must be a built-in key.
registry.mono_default = "latin-modern-mono"

--- Canonicalize a font name to its registry-key form — the one place font-name
--- normalization lives, so every lookup and comparison agrees. Lowercase today;
--- widen here if keys ever need more than case folding.
---@param name string  a raw font name (author metadata or content attribute)
---@return string  the canonical registry key
function registry.canonical(name)
  return name:lower()
end

--- True when `name` names a key in the composed registry (built-in or user
--- font). Compared via registry.canonical, so matching is case-insensitive.
---@param name string|nil  candidate registry key
---@return boolean
function registry.is_font(name)
  return name ~= nil and registry.fonts[registry.canonical(name)] ~= nil
end

--- Resolve an author font value (fontfamily or monofont) to a registry key;
--- unset (nil/empty) and unknown both fall back to default_key — one rule so
--- every path agrees. Returns the canonical key so all consumers embed and
--- declare the same font. Warning on an unknown value is the caller's job; this
--- is the pure resolution.
---@param value string|nil       raw author font value
---@param default_key string|nil owned fallback (defaults to registry.default)
---@return string  a valid registry key
function registry.resolve_family(value, default_key)
  if value ~= nil and registry.is_font(value) then
    return registry.canonical(value)
  end
  return default_key or registry.default
end

--- List every built-in font file (all present variants) as paths relative to
--- FONTS_ROOT — the single source of truth for which files the runtime image
--- carries. Consumed by the Docker font-extractor (see .docker/extract-fonts.sh).
--- User fonts are excluded; they mount at publish time.
---@return string[] files  relative paths under FONTS_ROOT; sorted and duplicate-free
function registry.builtin_font_files()
  local seen, files = {}, {}
  local variants = { "file", "bold", "italic", "bold_italic" }
  for _, key in ipairs(builtin_keys) do
    local main = registry.fonts[key].main
    -- Built-in paths are built from FONTS_ROOT, so stripping it yields the
    -- subtree; a registry-integrity test locks that invariant.
    local rel = main.path:sub(#FONTS_ROOT + 1)
    for _, variant in ipairs(variants) do
      local filename = main[variant]
      if filename and not seen[rel .. filename] then
        seen[rel .. filename] = true
        table.insert(files, rel .. filename)
      end
    end
  end
  table.sort(files)
  return files
end

--- Build the fontspec options for a font spec — the [Path=...,BoldFont=...] portion
--- and the {file} argument. Every registry entry is path-bearing, so a missing
--- path is a malformed entry: fail fast with a clear message, not a bare
--- concatenation error.
---@param spec table  Font spec with file, path, bold, italic, bold_italic
---@return string options  The [...] portion
---@return string file     The {file} portion
function registry.fontspec_options(spec)
  if not spec.path or spec.path == "" then
    error("fontspec_options: font '" .. tostring(spec.file) .. "' has no path")
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

--- Build a \setmonofont declaration for a registered font.
---@param name string  Registry key
---@return string|nil  LaTeX declaration, or nil if not found
function registry.setmonofont(name)
  local font = registry.fonts[name]
  if not font then return nil end

  local options, file = registry.fontspec_options(font.main)
  return "\\setmonofont" .. options .. "{" .. file .. "}"
end

--- Build the full LaTeX font preamble for header-includes.
--- Emits \setmainfont (+ optional \setsansfont companion) for the family and
--- \setmonofont for the code font, then sorted \newfontfamily declarations for
--- every registered font. The caller resolves both to valid keys beforehand, so
--- the guards here are defensive: an unrecognized key yields no \set*font.
---@param fontfamily string|nil  Resolved registry key for the main font
---@param monofont string|nil    Resolved registry key for the code font
---@return string  LaTeX preamble text
function registry.latex_preamble(fontfamily, monofont)
  local decls = {}

  if fontfamily and registry.fonts[fontfamily] then
    table.insert(decls, registry.setmainfont(fontfamily))

    local sans = registry.setsansfont(fontfamily)
    if sans then
      table.insert(decls, sans)
    end
  end

  if monofont and registry.fonts[monofont] then
    table.insert(decls, registry.setmonofont(monofont))
  end

  -- \newfontfamily for ALL registered fonts (sorted for reproducible output).
  for key in collections.sorted_pairs(registry.fonts) do
    table.insert(decls, registry.newfontfamily(key))
  end

  return table.concat(decls, "\n")
end

--- Build the set of used registry keys for selective @font-face emission.
--- Includes fontfamily (+ its sans companion), monofont, and any content_refs
--- that are valid registry keys. Unknown keys are silently dropped.
---@param fontfamily string|nil      Document fontfamily metadata value
---@param monofont string|nil        Document monofont metadata value
---@param content_refs table|nil     Set of family keys found in content (keys are lowercase strings)
---@return table<string, boolean>    Set of used registry keys
function registry.build_used_fonts(fontfamily, monofont, content_refs)
  local used = {}

  if fontfamily and registry.fonts[fontfamily] then
    used[fontfamily] = true
    local companion = registry.fonts[fontfamily].sans
    if companion then used[companion] = true end
  end

  if monofont and registry.fonts[monofont] then
    used[monofont] = true
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

--- The system (host-installed) fallback font for a face: the second quoted
--- value of its css stack (the first is the canonical embedded name). DOCX/ODT
--- can't embed and name a single font rather than a stack, so they render in
--- this host substitute. Best-effort: it shows only where the reader's app has
--- it, else the app uses its own default. Faces with no second value (math,
--- ornaments) return nil.
--- Example: '"Linux Libertine", "Georgia", serif' → "Georgia"
---@param name string  Registry key
---@return string|nil  System (host) fallback font name, or nil if <2 css values
function registry.system_fallback(name)
  local font = registry.fonts[name]
  if not font then return nil end

  -- Match second quoted value: skip first "...", then capture second "..."
  return font.css:match('"[^"]+"[^"]*"([^"]+)"')
end

--- Build a style ID for a system font name (DOCX/ODT custom-style).
--- Lowercases and kebab-cases the font name for use as a colon-delimited ID.
--- Example: "Times New Roman" → "font:times-new-roman"
---@param font_name string  System font display name
---@return string  Style ID prefix
function registry.font_style_id(font_name)
  return "font:" .. font_name:lower():gsub(" ", "-")
end

--- Extract the CSS em value string for a size name.
--- Returns just the numeric portion (e.g. "0.9", "1.44") used as the
--- case-safe identifier in DOCX/ODT style IDs.
--- Example: "small" → "0.9", "Large" → "1.44"
---@param size_name string  Registry size name (case-sensitive)
---@return string|nil  Em value string, or nil if unknown
function registry.size_em_value(size_name)
  for _, entry in ipairs(registry.sizes) do
    if entry.name == size_name then
      return entry.css:match("([%d%.]+)")
    end
  end
  return nil
end

--- Build a DOCX/ODT-safe style ID for a size name.
--- OOXML style lookups are case-insensitive, so names like large/Large/LARGE
--- collide. Uses the CSS em value as a unique, case-safe identifier.
--- Example: "small" → "size:0.9", "Large" → "size:1.44"
---@param size_name string  Registry size name (case-sensitive)
---@return string|nil  Style ID, or nil if unknown
function registry.size_style_id(size_name)
  local em = registry.size_em_value(size_name)
  if not em then return nil end
  return "size:" .. em
end

--- Build @font-face CSS rules and file paths for EPUB font embedding.
--- Returns two tables:
---   1. Array of @font-face CSS rule strings (one per variant)
---   2. Array of absolute file paths for epub-fonts metadata
---@param name string  Registry key
---@return string[]|nil  @font-face CSS rules, or nil if the key is unknown
---@return string[]|nil  Absolute file paths
function registry.epub_font_faces(name)
  local font = registry.fonts[name]
  if not font then return nil, nil end

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
--- rules, font-size class rules, and @font-face declarations (embed_fonts only).
--- When used_fonts is a table (set of keys), @font-face rules are generated
--- only for fonts in the set. When nil, generates for all (backward compatible).
--- CSS class rules stay unfiltered — they're one line each, and a class for a
--- non-embedded font still works via CSS fallback stack.
---@param fontfamily string|nil  Document fontfamily metadata value
---@param monofont string|nil    Document monofont metadata value
---@param embed_fonts boolean    Whether the format embeds font files (from format-registry)
---@param used_fonts table|nil   Set of registry keys to emit @font-face for
---@return string|nil  Complete CSS text, or nil if no rules generated
function registry.css_stylesheet(fontfamily, monofont, embed_fonts, used_fonts)
  local rules = {}

  -- Body font: the CSS equivalent of \setmainfont for LaTeX.
  if fontfamily and registry.fonts[fontfamily] then
    table.insert(rules,
      "body { font-family: " .. registry.fonts[fontfamily].css .. "; }")
  end

  -- Code font: the CSS equivalent of \setmonofont (code = inline, pre = block).
  if monofont and registry.fonts[monofont] then
    table.insert(rules,
      "code, pre { font-family: " .. registry.fonts[monofont].css .. "; }")
  end

  -- Font keys sorted once, reused by both the class-rule and @font-face loops
  -- below for reproducible output.
  local font_keys = collections.sorted_keys(registry.fonts)

  -- Font-family class rules for div/span handler overrides.
  for _, key in ipairs(font_keys) do
    local rule = registry.css_rule(key)
    if rule then table.insert(rules, rule) end
  end

  -- Font-size class rules.
  for _, rule in ipairs(registry.css_size_rules()) do
    table.insert(rules, rule)
  end

  -- @font-face rules for font-embedding formats (EPUB). The font files are
  -- embedded via --epub-embed-font flags in publish.sh. When used_fonts is
  -- provided, only fonts in the set get @font-face rules — the rest rely on
  -- their CSS fallback stacks.
  if embed_fonts then
    for _, key in ipairs(font_keys) do
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
