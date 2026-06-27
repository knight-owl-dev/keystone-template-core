---@diagnostic disable: undefined-global
-- xmp-metadata.lua — Conditionally load hyperxmp for PDF builds
--
-- hyperxmp writes a full XMP packet alongside the legacy PDF Info dict
-- (UTF-16 conversion, color profiles, etc.) and adds ~0.5–2s to every
-- xelatex pass. Pandoc 3.9.0.2+ also emits \xmpquote in \hypersetup
-- when pdfkeywords is set, which requires hyperxmp to be loaded.
--
-- This filter gates that cost behind a metadata key:
--
--   xmp-metadata: auto      (default) — embed XMP + Info dict
--   xmp-metadata: disabled            — Info dict only (faster)
--
-- Each mode injects exactly one \xmpquote definition so there is no
-- load-order ambiguity:
--   auto     — \usepackage{hyperxmp} provides \xmpquote with proper
--              XMP quoting. hyperref is pre-loaded in the same block
--              because hyperxmp errors if hyperref is not already
--              loaded; Pandoc's later \usepackage{bookmark} sees
--              hyperref already loaded and its \RequirePackage becomes
--              a no-op.
--   disabled — \providecommand\xmpquote{#1} is injected as a passthrough
--              so Pandoc's emitted \hypersetup{pdfkeywords=\xmpquote{…}}
--              compiles without crashing. Pandoc's \usepackage{bookmark}
--              loads hyperref normally; Title/Author/Subject still flow
--              into the Info dict via hyperref. Only the parallel XMP
--              packet is omitted.
--
-- Wired into publish.sh's PDF branch only — non-PDF formats never see
-- this filter. Blank values are treated as auto, matching the bridge
-- semantics in keystone.lua.

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration/README.md#path-resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

-- Install the memoized module loader, then acquire KAST. See
-- docs/pandoc-integration/kast.md.
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")

local AUTO_PREAMBLE = table.concat({
  "\\usepackage{hyperref}",
  "\\usepackage{hyperxmp}",
  "\\hypersetup{keeppdfinfo}",
}, "\n")

local DISABLED_PREAMBLE = "\\providecommand{\\xmpquote}[1]{#1}"

function Meta(meta)
  local val = kast.meta.stringify(meta["xmp-metadata"])
  if val == "" then val = "auto" end

  if val == "auto" then
    kast.meta.add_header_include(meta, AUTO_PREAMBLE)
  elseif val == "disabled" then
    kast.meta.add_header_include(meta, DISABLED_PREAMBLE)
  else
    error("xmp-metadata must be 'auto' or 'disabled', got: " .. val)
  end

  return meta
end
