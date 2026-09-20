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
--   • a font from a new TeX Live package: .docker/fonts/README.md is the
--     procedure — the package declaration, the license that has to ship with
--     it, and where the family is recorded
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
--   main.license     (expected) The terms the font travels under, named as files
--                    resolved against main.path. A list, because a font's terms can
--                    span files. A format that carries a whole, unmodified font
--                    file ships the terms beside it; one that embeds a subset
--                    carries none. A font that declares none warns on every
--                    build, and the image build refuses to stage a family whose
--                    terms it cannot find. Which formats do which is at
--                    https://keystone.knight-owl.dev/errors/missing-font-license/
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
-- cspell:ignore dejavuserif LICENCE adoc

local errors = ks_require("errors")
local collections = ks_require("collections")
local env_io = ks_require("env-io")
local identifiers = ks_require("identifiers")
local kast = ks_require("ast")

-- Built-in font files live under this owned root in the runtime image; the
-- Docker font-extractor stages them here (see .docker/fonts/extract-fonts.sh).
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
        license = { "GPL.txt", "LICENCE.txt" },
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
        license = { "GPL.txt", "LICENCE.txt" },
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
        license = { "LICENSE" },
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
        license = { "LICENSE" },
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
        license = { "LICENSE" },
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
        license = { "OFL.txt" },
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
        license = { "GUST-FONT-LICENSE.TXT" },
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
        license = { "GUST-FONT-LICENSE.TXT" },
      },
      css = '"Latin Modern Mono", "Courier New", monospace',
    },
    -- No system fallback (a generic only), so DOCX/ODT degrade like the ornaments.
    ["latin-modern-math"] = {
      main = {
        file = "latinmodern-math.otf",
        path = FONTS_ROOT .. "opentype/public/lm-math/",
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "GUST-FONT-LICENSE.txt" },
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
        license = { "LICENSE_OFL.txt" },
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
        license = { "LICENSE.txt" },
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
        license = { "README" },
      },
      css = '"Fourier Ornaments", serif',
    },
    ["imfell-flowers-1"] = {
      main = {
        file = "FeFlow1.otf",
        path = FONTS_ROOT .. "opentype/iginomarini/imfellenglish/",
        license = { "COPYING" },
      },
      css = '"IM Fell Flowers 1", serif',
    },
    ["imfell-flowers-2"] = {
      main = {
        file = "FeFlow2.otf",
        path = FONTS_ROOT .. "opentype/iginomarini/imfellenglish/",
        license = { "COPYING" },
      },
      css = '"IM Fell Flowers 2", serif',
    },
  },
}

-- ── A font's files ───────────────────────────────────────────────────
-- The `main` fields that name a font file, regular first, each carrying the CSS
-- style, weight and fontspec option its variant stands for. Every pass over a
-- font's files walks this table, so a variant left out of it silently stops
-- being checked, extracted, embedded, declared to fontspec and given a
-- @font-face rule.
local VARIANT_FIELDS = {
  { field = "file",        style = "normal", weight = "normal" },
  { field = "bold",        style = "normal", weight = "bold",
    fontspec = "BoldFont" },
  { field = "italic",      style = "italic", weight = "normal",
    fontspec = "ItalicFont" },
  { field = "bold_italic", style = "italic", weight = "bold",
    fontspec = "BoldItalicFont" },
}

--- The files a font declares, in variant order, skipping the variants it omits.
---@param main table  a font entry's `main`
---@return table[] files  { { field, file, style, weight, fontspec }, … }
function registry.variant_files(main)
  local files = {}
  for _, variant in ipairs(VARIANT_FIELDS) do
    local file = main[variant.field]
    if file then
      files[#files + 1] = {
        field = variant.field,
        file = file,
        style = variant.style,
        weight = variant.weight,
        fontspec = variant.fontspec,
      }
    end
  end
  return files
end

--- What is wrong with a declared `license` value, or nil when nothing is.
---
--- A license filename is author input and nothing else checks it, where a font
--- filename is refused at the merge. Every shape below would otherwise pass
--- quietly and cost the author their terms: yq turns `license: OFL.txt` into a
--- string and a YAML mapping into a keyed table, and ipairs walks neither, so
--- the font would ship with nothing beside it and no diagnostic. An empty name
--- resolves to the fonts directory, which opens like a file. A name carrying a
--- path cannot be a basename in a flat archive.
---
--- An empty list is well-formed: it is how an author says there are none.
---@param value any  a font entry's `main.license`, as declared
---@return string|nil  what is wrong with it, phrased to follow the font's key
function registry.license_list_problem(value)
  if type(value) ~= "table" then
    return "is a " .. type(value) .. ", not a list"
  end

  local keys, numbered = 0, 0
  for k in pairs(value) do
    keys = keys + 1
    if type(k) == "number" then numbered = numbered + 1 end
  end
  if keys ~= #value then
    -- A blank `- ` item leaves a gap rather than a key, and the two mistakes
    -- take different corrections, so they are not reported as one.
    return keys == numbered and "has an entry with no filename"
      or "is a mapping, not a list"
  end

  for _, name in ipairs(value) do
    if type(name) ~= "string" then
      return "names a " .. type(name) .. " where a filename belongs"
    elseif name == "" then
      return "names an empty filename"
    elseif name == "." or name == ".." then
      return "names '" .. name .. "', which is a directory rather than a file"
    elseif name:find("/", 1, true) then
      return "names '" .. name .. "', which is a path rather than a filename"
    elseif name:find("%c") then
      -- A row is two fields split on a tab and read a line at a time, so a
      -- control character in a name would not survive the crossing into
      -- publish.sh — it would split one row into pieces of two others. The font
      -- filenames sharing those rows are unchecked for it, which is older than
      -- this rule and absurd to reach; a license name is new here, so it is
      -- held to what the row format can carry.
      return "names a filename carrying a control character"
    end
  end
  return nil
end

--- The license files a font declares, in declaration order and without repeats.
--- The one enumeration of a font's terms, as variant_files is of its binaries:
--- a name listed twice is one file, and every pass that walks this agrees on
--- how many entries it stands for. A value of the wrong shape enumerates as
--- none, so no caller can walk what license_list_problem rejects.
---@param main table  a font entry's `main`
---@return string[] files  license filenames, resolved against main.path by the caller
function registry.license_files(main)
  if registry.license_list_problem(main.license) then return {} end
  local seen, files = {}, {}
  for _, name in ipairs(main.license) do
    if not seen[name] then
      seen[name] = true
      files[#files + 1] = name
    end
  end
  return files
end

--- The name a license file takes when it is packaged beside the font it
--- covers: the font's own filename, then the license's.
---
--- Packaging flattens — a font and its texts land in one namespace addressed
--- by bare basename — so the prefix is the only thing binding a text to its
--- binary. It also sorts them together, since `.` precedes every letter and
--- digit.
---
--- Across fonts the result is unique for free, since no two declarations may
--- name one font file (see the font-filename uniqueness refusal). Two texts of
--- ONE font share the prefix, so only their own names tell them apart, and the
--- closure below can land two of them on one result — which the declared-terms
--- check reports, and drops the loser of.
---
--- The license keeps its own name because one of them is not ours to choose:
--- libertine's LICENCE.txt names its GPL.txt, and a reader following that
--- reference has to find it under that name.
---
--- `.txt` closes every name that does not already end in it. A packager that
--- types a file by its extension has no entry for .rst, .adoc or .pod and
--- records no type at all, which validators reject — so the name is held to
--- the one extension such a table is certain to carry.
---@param font_file string     the font's filename, as main.file and the variants name it
---@param license_file string  the license's filename, as main.license names it
---@return string  the basename the license takes beside the font
function registry.license_archive_name(font_file, license_file)
  local name = font_file .. "." .. license_file
  if not license_file:lower():find("%.txt$") then
    name = name .. ".txt"
  end
  return name
end

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

-- Whether a path names a file this process can read. A directory opens like a
-- file, so it is ruled out by the one thing a file cannot do: hold a child
-- entry. Reading a byte would not serve — an empty file is already at EOF, and
-- a font or a license of no bytes is still something the author put there.
local function readable_file(path)
  local fh = io.open(path, "r")
  if not fh then return false end
  fh:close()

  local as_directory = io.open(path .. "/.", "r")
  if not as_directory then return true end
  as_directory:close()
  return false
end

-- ── Declaration problems ─────────────────────────────────────────────
-- What the checks below find wrong they collect here rather than reporting.
--
-- Pandoc gives each Lua filter its own interpreter, so this module loads fresh
-- per filter and the merge runs again in every one, reaching the same verdict
-- each time — a merge that spoke would repeat itself once per pass. Skipping
-- the bad entry still happens in all of them, or the registry would differ
-- between passes. Only the telling waits for an owner: keystone.lua drains it
-- once, in every format.

registry.declaration_problems = {}

--- Report what the checks below found wrong with a font declaration.
--- Called once, by the pass that owns them.
function registry.report_declaration_problems()
  for _, callout in ipairs(registry.declaration_problems) do
    errors.warn(callout)
  end
end

local function note_problem(callout)
  table.insert(registry.declaration_problems, callout)
end

-- ── User-supplied fonts ──────────────────────────────────────────────
-- Merge user fonts from the preprocessed Lua table at KEYSTONE_USER_FONTS.
-- publish.sh converts fonts/fonts-registry.yaml → Lua via yq and exports
-- KEYSTONE_USER_FONTS (path to the Lua table) and KEYSTONE_USER_FONTS_DIR
-- (container path to font files, used as default main.path). Each entry is
-- validated (required fields, file existence) before insertion. Built-in
-- keys cannot be overridden — collisions are noted and the entry skipped.

local user_fonts_dir = env_io.optional_env("KEYSTONE_USER_FONTS_DIR")
local user_fonts_path = env_io.optional_env("KEYSTONE_USER_FONTS")
if user_fonts_path then
  local loader, load_err = loadfile(user_fonts_path, "t", {})
  if not loader then
    errors.fatal({
      problem = "font-registry: failed to load user fonts",
      verbatim = load_err,
    })
  end
  -- errors.fatal exits, so loader is non-nil here; the analyzer can't see
  -- through the lib call the way it did the former bare error().
  ---@diagnostic disable-next-line: need-check-nil
  local user_data = loader()

  if user_data then
    for key, entry in collections.sorted_pairs(user_data) do
      -- Collision guard: built-in fonts take precedence
      if registry.fonts[key] then
        note_problem({
          problem = "user font '" .. key .. "' collides with a built-in",
          effect = "The font is skipped.",
        })
      elseif not entry.main or not entry.main.file then
        note_problem({
          problem = "user font '" .. key .. "' is missing main.file",
          effect = "The font is skipped.",
        })
      elseif not entry.css then
        note_problem({
          problem = "user font '" .. key .. "' is missing css",
          effect = "The font is skipped.",
        })
      elseif not (entry.main.path or user_fonts_dir) then
        -- Every font must be path-bearing; without an explicit path and no
        -- mount point to default to, there is nothing to embed.
        note_problem({
          problem = "user font '" .. key
            .. "' has no path and KEYSTONE_USER_FONTS_DIR is unset",
          effect = "The font is skipped.",
        })
      else
        -- Default path to the user fonts mount point
        if not entry.main.path then
          entry.main.path = user_fonts_dir
        end

        -- Validate font files exist on disk
        local invalid = false
        for _, declared in ipairs(registry.variant_files(entry.main)) do
          -- An empty value is not an omitted variant: yq carries `bold:` through
          -- as nil, which reads as absent, but `bold: ""` as a string that
          -- resolves to the fonts directory itself and so passes an existence
          -- check. Naming it here is the only place the author learns which.
          if declared.file == "" then
            local empty_remedy = "Name the variant's file, or remove the field"
              .. " to let the variant fall back to the regular."
            if declared.field == "file" then
              empty_remedy = "Name the family's regular file: main.file is"
                .. " required, and it is what every other variant falls back to."
            end
            note_problem({
              problem = "user font '" .. key .. "' leaves main." .. declared.field
                .. " empty",
              effect = "The font is skipped.",
              remedy = empty_remedy,
            })
            invalid = true
            break
          end
          if not readable_file(entry.main.path .. declared.file) then
            note_problem({
              problem = "user font '" .. key .. "' has no " .. declared.field
                .. " file at " .. entry.main.path .. declared.file,
              effect = "The font is skipped.",
            })
            invalid = true
            break
          end
        end

        if not invalid then
          -- `license: OFL.txt` is the natural single-file spelling, so the
          -- shape is worth checking. Neither a bad shape nor a name pointing
          -- at nothing disqualifies the font: the entry stays usable and only
          -- the terms go unshipped. Both wait until the font has survived,
          -- since a font being dropped needs no advice about terms it will
          -- not travel under.
          local shape = registry.license_list_problem(entry.main.license)
          if entry.main.license ~= nil and shape then
            note_problem({
              problem = "font '" .. key .. "' license " .. shape,
              because = "A font can come with more than one license file, so"
                .. " main.license is always a list. Each entry is a filename"
                .. " in your fonts directory, not a path.",
              effect = "The font ships without its license.",
              remedy = "Write main.license as a list, one filename per entry.",
              see = "https://keystone.knight-owl.dev/errors/missing-font-license/#a-declaration-that-is-not-a-list-of-filenames",
            })
          end

          local shipped_licenses = {}
          for _, license in ipairs(registry.license_files(entry.main)) do
            if readable_file(entry.main.path .. license) then
              table.insert(shipped_licenses, license)
            else
              note_problem({
                -- Named as the author wrote it, where the variant warning above
                -- prints the resolved path: this one is quoted in the manual,
                -- and a container path is neither reproducible there nor
                -- somewhere the author can go and look.
                problem = "font '" .. key .. "' has no license file named "
                  .. license,
                effect = "The font ships without its license.",
                remedy = "Check the name against the file in your fonts"
                  .. " directory, or drop it from main.license.",
                see = "https://keystone.knight-owl.dev/errors/missing-font-license/#a-license-that-cannot-be-read",
              })
            end
          end
          -- What survives replaces the declaration, so nothing downstream
          -- reaches for a file that is not there. A declaration of the wrong
          -- shape is left as the author wrote it: the pass that reports it
          -- needs to see it.
          if shape == nil then
            entry.main.license = shipped_licenses
          end

          -- command is derived, not author-settable; warn on a stray value
          -- rather than dropping it silently.
          if entry.command then
            note_problem({
              problem = "user font '" .. key .. "' sets 'command'",
              effect = "'command' is derived, so the value is ignored.",
            })
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

-- ── Declared terms ───────────────────────────────────────────────────
-- Every font must say what it travels under, or say there is nothing to say.
--
-- Over the merged registry, so it covers the built-ins too: a fork that adds a
-- family to the table above is the case this catches, and the image build's
-- own refusal reads as a stack trace.
--
-- Checked for every format rather than only where the text ships. One
-- manuscript targets them all, so a declaration is either true or it is not,
-- and a project that builds one format today would otherwise hold the mistake
-- until the day it built another.
--
-- Absent and empty are different answers. No main.license is a font nobody has
-- said anything about; an empty list is the author saying there is nothing to
-- ship, which only they can know.
for _, key in ipairs(collections.sorted_keys(registry.fonts)) do
  local main = registry.fonts[key].main

  -- Two names can close as one entry — LICENSE and LICENSE.txt both reach
  -- .LICENSE.txt — and one text would then stand in for the other. Compared
  -- without case, as the font filenames are: the filesystems a book is
  -- unpacked onto do not all keep it. Every text of one font takes that font's
  -- name as its prefix, so closing the bare name compares the whole entry.
  --
  -- What survives replaces the declaration, so nothing downstream reaches for
  -- a name that was never going to arrive.
  local kept, taken = {}, {}
  for _, license in ipairs(registry.license_files(main)) do
    local entry = registry.license_archive_name("", license):lower()
    if taken[entry] then
      note_problem({
        problem = "font '" .. key .. "' names two licenses that cannot be"
          .. " told apart",
        offenders = { taken[entry], license },
        because = "Keystone adds .txt to a license name that does not have"
          .. " it, so two names differing only by that extension end up the"
          .. " same. Case is ignored too, because not every filesystem keeps"
          .. " it.",
        effect = "One of the two files ships and the other does not.",
        remedy = "Rename one of the files, and the entry that names it, so"
          .. " the two differ by more than an extension or by case.",
        see = "https://keystone.knight-owl.dev/errors/missing-font-license/#two-licenses-that-take-one-name",
      })
    else
      taken[entry] = license
      kept[#kept + 1] = license
    end
  end
  -- Only a list is rewritten. A declaration of the wrong shape enumerates as
  -- none, so `kept` is empty against a value that may have no length at all —
  -- and the pass that reports the shape needs to see it as the author wrote it.
  if type(main.license) == "table" and #kept ~= #main.license then
    main.license = kept
  end

  if main.license == nil then
    note_problem({
      problem = "font '" .. key .. "' declares no license",
      because = "A font usually comes with a license file that has to be"
        .. " included wherever the font is. Keystone cannot tell which file"
        .. " that is until the entry names it.",
      effect = "Books that embed this font will not include its license.",
      remedy = "Name the license file in the entry's main.license. Write an"
        .. " empty list where the font is yours and there is nothing to"
        .. " pass on.",
      see = "https://keystone.knight-owl.dev/errors/missing-font-license/#a-font-that-declares-no-license",
    })
  end
end

-- ── Font filename uniqueness ─────────────────────────────────────────
-- No two declarations may name the same font file; the manual page each callout
-- cites carries the author-facing account.
--
-- Refused at the merge rather than at embed time. The declaration is already
-- wrong when it is written, and only EPUB reveals it, so deferring would let a
-- PDF-only project carry the defect for as long as it never builds one.
-- Refusing here also covers the built-ins, so the property they satisfy today
-- cannot lapse.
--
-- Matched on the name, not the path. The name is the whole of an embedded
-- font's address in the archive, so two files in different directories compete
-- there exactly as two in one would.
--
-- Matched without case, because neither end of the journey keeps it: macOS and
-- Windows hold Foo.ttf and foo.ttf as one file, whether that is the reader
-- unpacking the archive or the author filling fonts/. Comparing exactly would
-- hand the verdict to whichever filesystem the build happened to run on.
local ADDRESSED_BY_NAME = "An embedded font is addressed by its filename alone"
local ONE_NAME_ONE_FONT = "so one name cannot stand for two declarations."
local NAME_RULE = ADDRESSED_BY_NAME .. ", " .. ONE_NAME_ONE_FONT
local CASE_RULE = ADDRESSED_BY_NAME .. ", and the filesystems a book is unpacked"
  .. " onto do not all distinguish case, " .. ONE_NAME_ONE_FONT

-- Which side of a collision is Keystone's, and so not the author's to change.
local builtin_key = {}
for _, key in ipairs(builtin_keys) do
  builtin_key[key] = true
end

local ALIAS_HINT = "A second name for one font belongs in shortcuts.yaml,"
  .. " where an alias costs no second copy."

--- What to do about two entries competing for one archive entry.
--- Keystone owns one side of the commonest collision — an author's file named
--- like a built-in's — and a remedy that does not say which side is ours leaves
--- the author free to pick Keystone's.
local function collision_remedy(prior, key, entry, same_name)
  local ours = (builtin_key[prior.key] and prior.key) or (builtin_key[key] and key)
  local one_file = same_name and prior.path == entry.main.path
  if ours and one_file then
    return "'" .. ours .. "' is one of Keystone's own fonts and this is its own"
      .. " file, so drop your entry. " .. ALIAS_HINT
  end
  if ours then
    return "'" .. ours .. "' is one of Keystone's own fonts, so rename your file"
      .. " in fonts/ and the entry that names it."
      .. (same_name and "" or " Case alone is not difference enough.")
  end
  if one_file then
    return "Drop one of the entries. " .. ALIAS_HINT
  end
  if same_name then
    return "Rename one of the files, and the entry that names it."
  end
  return "Rename one of the files, and the entry that names it, so the two"
    .. " differ by more than case."
end

-- One branch per section of the manual page, so each callout cites its own
-- anchor as a literal — gate-manual-links.bats resolves what it finds beside
-- `see =`, and reads nothing through a variable.
local function duplicate_callouts()
  local declared, callouts = {}, {}
  for key, entry in collections.sorted_pairs(registry.fonts) do
    for _, item in ipairs(registry.variant_files(entry.main)) do
      local prior = declared[item.file:lower()]
      if prior then
        local one_entry = prior.key == key
        local same_name = prior.file == item.file
        local offenders = one_entry
          and { "main." .. prior.field, "main." .. item.field }
          or {
            -- The declaring field: that is what the author edits, where a
            -- built-in's path is engine-internal.
            prior.key .. ": main." .. prior.field,
            key .. ": main." .. item.field,
          }
        local subject = one_entry and "font '" .. key .. "' declares "
          or "fonts '" .. prior.key .. "' and '" .. key .. "' declare "

        if not same_name then
          -- Two spellings are two files wherever case is kept, so the one-file
          -- rule the other branches state would be false here. Naming both is
          -- what lets the author see which pair collided.
          table.insert(callouts, {
            problem = subject .. "'" .. prior.file .. "' and '" .. item.file
              .. "', which differ only in case",
            offenders = offenders,
            because = CASE_RULE,
            remedy = one_entry
              and "Rename one of the files, and the field that names it, so the"
                .. " two differ by more than case."
              or collision_remedy(prior, key, entry, same_name),
            see = "https://keystone.knight-owl.dev/errors/duplicate-font-file/#names-that-differ-only-in-case",
          })
        elseif one_entry then
          table.insert(callouts, {
            problem = subject .. "'" .. item.file .. "' twice",
            offenders = offenders,
            because = "Each variant of a family is its own file; one file"
              .. " cannot be two of them.",
            remedy = "Name the missing variant's file, or remove the field when"
              .. " the family ships no such variant — an absent variant already"
              .. " falls back to the regular.",
            see = "https://keystone.knight-owl.dev/errors/duplicate-font-file/#one-entry-naming-a-file-twice",
          })
        else
          table.insert(callouts, {
            problem = "fonts '" .. prior.key .. "' and '" .. key
              .. "' both declare '" .. item.file .. "'",
            offenders = offenders,
            because = NAME_RULE,
            remedy = collision_remedy(prior, key, entry, same_name),
            see = "https://keystone.knight-owl.dev/errors/duplicate-font-file/#two-entries-naming-one-file",
          })
        end
      else
        declared[item.file:lower()] =
          { key = key, field = item.field, path = entry.main.path, file = item.file }
      end
    end
  end
  return callouts
end

local duplicates = duplicate_callouts()
if #duplicates > 0 then
  errors.fatal_each(duplicates)
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
--- carries. User fonts are excluded; they mount at publish time.
---@return string[] files  relative paths under FONTS_ROOT; sorted and duplicate-free
function registry.builtin_font_files()
  local seen, files = {}, {}
  for _, key in ipairs(builtin_keys) do
    local main = registry.fonts[key].main
    -- Built-in paths are built from FONTS_ROOT, so stripping it yields the
    -- subtree; a registry-integrity test locks that invariant.
    local rel = main.path:sub(#FONTS_ROOT + 1)
    for _, declared in ipairs(registry.variant_files(main)) do
      if not seen[rel .. declared.file] then
        seen[rel .. declared.file] = true
        table.insert(files, rel .. declared.file)
      end
    end
  end
  table.sort(files)
  return files
end

--- List every built-in license file as paths relative to FONTS_ROOT — the
--- companion to builtin_font_files(), and what the image stages beside the
--- binaries. Entries sharing a package directory name the same file, so the
--- list is deduplicated; user fonts are excluded, as there.
---@return string[] files  relative paths under FONTS_ROOT; sorted and duplicate-free
function registry.builtin_license_files()
  local seen, files = {}, {}
  for _, key in ipairs(builtin_keys) do
    local main = registry.fonts[key].main
    -- Defensive, like fontspec_options' path guard: the suite asserts every
    -- built-in declares its terms, so reaching this is a malformed entry.
    local problem = registry.license_list_problem(main.license)
    if problem then
      error("builtin_license_files: font '" .. key .. "' license " .. problem)
    end
    local rel = main.path:sub(#FONTS_ROOT + 1)
    for _, name in ipairs(registry.license_files(main)) do
      if not seen[rel .. name] then
        seen[rel .. name] = true
        table.insert(files, rel .. name)
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
  for _, declared in ipairs(registry.variant_files(spec)) do
    if declared.fontspec then
      table.insert(parts, declared.fontspec .. "=" .. declared.file)
    end
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

  local rules = {}
  local paths = {}

  for _, v in ipairs(registry.variant_files(font.main)) do
    table.insert(rules, "@font-face {\n"
      .. '  font-family: "' .. family .. '";\n'
      .. "  font-style: " .. v.style .. ";\n"
      .. "  font-weight: " .. v.weight .. ";\n"
      .. '  src: url("../fonts/' .. v.file .. '");\n'
      .. "}")
    table.insert(paths, font.main.path .. v.file)
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
