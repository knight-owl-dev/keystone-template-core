---@diagnostic disable: undefined-global
-- keystone.lua
-- Validates and enriches metadata for the Keystone project

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration.md § Path Resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

local font_registry = dofile(path.join({ script_dir, "lib", "font-registry.lua" }))

local required_fields = {
  common = {
    "title",
    "author",
  },
  book = {
    "description",
  }
}

-- Utility: get today's date
local function get_today()
  -- Use the system locale to format the date with full month name, day, and year
  -- Example: May 25, 2025 (English)
  return os.date("%B %d, %Y")
end

-- Utility: get the "date" value as a pandoc MetaInlines
local function get_date_as_MetaInlines()
  return pandoc.MetaInlines{pandoc.Str(get_today())}
end

-- Utility: Get the value for the \keystonerights macro
local function get_keystonerights(meta)
  local val = pandoc.utils.stringify(meta["footer-copyright"] or "auto")

  if val == "disabled" then
    return "" -- disables the macro (renders nothing)
  end

  local text;
  if val == "auto" then
    local author = meta.author and pandoc.utils.stringify(meta.author) or "Unknown"
    local year = os.date("%Y")

    text = string.format("© %s %s. All rights reserved.", year, author)
  else
    -- Use the custom value as-is (after stripping whitespace)
    text = val
  end

  return pandoc.write(pandoc.Pandoc({pandoc.Plain{pandoc.Str(text)}}), "latex")
end

function Meta(meta)
  local missing = {}

  -- Start with common fields
  local required = {}
  for _, key in ipairs(required_fields.common) do
    table.insert(required, key)
  end

  -- Add specialized requirements based on documentclass
  local docclass = meta["documentclass"] and pandoc.utils.stringify(meta["documentclass"]) or "book"
  if required_fields[docclass] then
    for _, key in ipairs(required_fields[docclass]) do
      table.insert(required, key)
    end
  end

  -- Validate all required fields
  for _, key in ipairs(required) do
    if not meta[key] then
      table.insert(missing, key .. (docclass ~= "common" and " (required for " .. docclass .. ")" or ""))
    end
  end

  -- Output and halt on missing fields
  if #missing > 0 then
    io.stderr:write("ERROR: Missing required metadata fields:\n")
    for _, key in ipairs(missing) do
      io.stderr:write("  - " .. key .. "\n")
    end

    error("missing required metadata fields")
  end

  -- Inject the current date if "auto" is specified,
  -- or remove the date metadata if set to "disabled"
  if meta.date then
    local date_value = pandoc.utils.stringify(meta.date)
    if date_value == "auto" then
      meta.date = get_date_as_MetaInlines()
    elseif date_value == "disabled" then
      meta.date = nil
    end
  end

  -- Strip empty cover-image to prevent Pandoc EPUB crash.
  -- An empty string or YAML null (including ~) causes Pandoc to error when
  -- building EPUB. Whitespace-only values are trimmed as a precaution.
  -- Removing the field entirely lets the build proceed without a cover.
  if meta["cover-image"] then
    local val = pandoc.utils.stringify(meta["cover-image"]):match("^%s*(.-)%s*$")
    if val == "" then
      meta["cover-image"] = nil
    end
  end

  -- Font registry: intercept fontfamily metadata for registered fonts.
  -- Generates \setmainfont (+ suite companions) and \newfontfamily for all
  -- registered fonts so both document-wide and per-block/inline overrides
  -- share a single source of truth.
  --
  -- If fontfamily is NOT a registry key, leave it untouched — the Pandoc
  -- template handles it as \usepackage{} (backward compatible).
  local fontfamily = meta.fontfamily and pandoc.utils.stringify(meta.fontfamily) or nil
  local font_decls = {}

  if fontfamily and font_registry.fonts[fontfamily] then
    -- Generate \setmainfont for the chosen document font
    table.insert(font_decls, font_registry.setmainfont(fontfamily))

    -- Generate \setsansfont for suite companion (if defined)
    local sans = font_registry.setsansfont(fontfamily)
    if sans then
      table.insert(font_decls, sans)
    end

    -- Nil out fontfamily so the Pandoc template doesn't emit \usepackage{}.
    -- The template falls back to loading lmodern, which our \setmainfont overrides.
    meta.fontfamily = nil
  end

  -- Generate \newfontfamily for ALL registered fonts (for handler use).
  -- Sort keys for reproducible LaTeX preamble output.
  local sorted_keys = {}
  for key in pairs(font_registry.fonts) do
    table.insert(sorted_keys, key)
  end
  table.sort(sorted_keys)

  for _, key in ipairs(sorted_keys) do
    table.insert(font_decls, font_registry.newfontfamily(key))
  end

  -- Inject rights as raw LaTeX for use in the footer
  meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}

  if #font_decls > 0 then
    table.insert(meta["header-includes"],
      pandoc.RawBlock("latex", table.concat(font_decls, "\n")))
  end

  -- Generate CSS rules for EPUB/HTML from registries (font-family + font-size).
  local css_rules = {}
  for _, key in ipairs(sorted_keys) do
    local rule = font_registry.css_rule(key)
    if rule then table.insert(css_rules, rule) end
  end
  for _, rule in ipairs(font_registry.css_size_rules()) do
    table.insert(css_rules, rule)
  end
  if #css_rules > 0 then
    table.insert(meta["header-includes"],
      pandoc.RawBlock("html", "<style>\n" .. table.concat(css_rules, "\n") .. "\n</style>"))
  end

  table.insert(meta["header-includes"], pandoc.RawBlock("latex", "\\newcommand{\\keystonerights}{" .. get_keystonerights(meta) .. "}"))

  return meta
end
