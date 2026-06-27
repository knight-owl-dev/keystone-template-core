-- code-theme-registry.lua — Discover and resolve code syntax highlighting themes
--
-- Each theme lives in its own subdirectory under filters/code-themes/.
-- A directory is recognized as a theme when it contains style.css (the
-- discovery probe, parallel to handler.lua in divs/).
--
-- Environment (set by publish.sh):
--   KEYSTONE_CSS_CODE_THEME — path for the generated code theme CSS stylesheet
--   KEYSTONE_CODE_THEME     — resolved code theme name
--
-- Public API:
--   registry.resolve()  — discover, validate, read style files
--   registry.inject()   — resolve + inject TeX/CSS into Pandoc metadata

-- KAST is acquired here as a global platform facility (like pandoc itself);
-- the genuinely caller-owned collaborators — list_directory, path_join, env_io
-- — stay injected via the `deps` table so they remain swappable per call site
-- (and per test). Same split, and same reasoning, as placeholder-substitute.lua.
local kast = ks_require("ast")

local registry = {}

--- Read a file's full contents. Returns the content string.
--- Errors on any I/O failure — never returns nil silently.
local function read_file(filepath)
  local f, open_err = io.open(filepath, "r")
  if not f then
    error("failed to open " .. filepath .. ": " .. (open_err or "unknown error"))
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Discover available theme names by probing for style.css.
--- Returns a sorted list of theme name strings.
local function discover(themes_dir, deps)
  local entries = deps.list_directory(themes_dir)
  table.sort(entries)

  local themes = {}
  for _, entry in ipairs(entries) do
    local probe_path = deps.path_join({ themes_dir, entry, "style.css" })
    local probe = io.open(probe_path, "r")
    if probe then
      probe:close()
      table.insert(themes, entry)
    end
  end

  return themes
end

--- Resolve a theme by name. Probes the specific theme directory,
--- reads its style files, and wraps the TeX content in a deferred
--- Shaded guard. Only discovers other themes for the error message
--- when the requested theme is missing.
---
---@param themes_dir string    Path to the code-themes/ directory
---@param theme_name string    Theme name (e.g. "tango", "espresso")
---@param deps table           { list_directory = fn, path_join = fn }
---@return table               { tex = string, css = string }
function registry.resolve(themes_dir, theme_name, deps)
  local theme_dir = deps.path_join({ themes_dir, theme_name })
  local probe = io.open(deps.path_join({ theme_dir, "style.css" }), "r")

  if not probe then
    local available = discover(themes_dir, deps)
    error("unknown code-theme '" .. theme_name .. "'"
      .. " — available themes: " .. table.concat(available, ", "))
  end
  probe:close()

  local css = read_file(deps.path_join({ theme_dir, "style.css" }))
  local tex = read_file(deps.path_join({ theme_dir, "style.tex" }))

  -- Wrap TeX in deferred guard: Pandoc's highlighting-macros (which define
  -- Shaded) appear after header-includes in the LaTeX template, so color
  -- definitions must be deferred with \AtBeginDocument. The \ifdefined guard
  -- skips injection when the document has no code blocks.
  local wrapped_tex = "\\AtBeginDocument{%\n"
    .. "  \\ifdefined\\Shaded%\n"
    .. "    " .. tex
    .. "  \\fi\n"
    .. "}"

  return { tex = wrapped_tex, css = css }
end

--- Resolve the code theme and inject its styles into Pandoc metadata.
--- TeX goes into header-includes (all formats); CSS is written to the
--- KEYSTONE_CSS_CODE_THEME path and appended to meta.css (CSS formats only).
---
---@param meta table           Pandoc Meta object
---@param inject_css boolean   Whether the format uses CSS (from format-registry)
---@param themes_dir string    Path to the code-themes/ directory
---@param deps table           { list_directory, path_join, env_io }
function registry.inject(meta, inject_css, themes_dir, deps)
  local theme_name = deps.env_io.require_env("KEYSTONE_CODE_THEME")
  local result = registry.resolve(themes_dir, theme_name, deps)

  kast.meta.add_header_include(meta, result.tex)

  if inject_css then
    local css_path = deps.env_io.write_file("KEYSTONE_CSS_CODE_THEME", result.css)
    kast.meta.add_css(meta, css_path)
  end
end

return registry
