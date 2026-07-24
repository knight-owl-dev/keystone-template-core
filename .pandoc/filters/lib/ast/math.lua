-- ast/math.lua — Probe whether a document's equations convert for a target
-- format. Part of KAST; see docs/pandoc-integration/kast.md. The why — refusing
-- unconvertible math instead of leaking raw TeX — lives in math-check.lua, the
-- one caller.
--
-- Faithful to the actual target by design: rather than probing a proxy format
-- and assuming the others match, it writes the document to the *real* target
-- writer and reports the conversion failures that writer emits — OMML for docx,
-- MathML for html/epub/odt, raw passthrough for latex (which never fails).
--
-- Pandoc offers no structured way to ask whether an equation converted — the
-- only signal is the text of its "Could not convert TeX math …" warning, so we
-- match that.

local M = {}

-- The warning Pandoc logs when texmath can't parse an equation. Matching the log
-- (not each writer's raw-TeX leak shape) keeps the check writer-agnostic.
local FAIL_SIGNAL = "Could not convert TeX math"

--- Probe `doc` against the `format` writer and return the math-conversion
--- failures it produces. An empty list means every equation converts for that
--- format. The write output is discarded — only the captured log matters — and
--- texmath's warnings are silenced here so the caller emits one clean report.
---
--- `opts` should mirror the real build's writer options; in particular
--- `html_math_method` must match (mathml today), because that is what decides
--- whether the html/epub writers route math through texmath at all. A
--- non-texmath method (webtex/mathjax) renders without parsing and never fails
--- — probing with the real method keeps the verdict true to what ships.
---
--- A write that throws (a non-math writer error) yields an empty list: that is
--- the real build's failure to surface, not this guard's.
---@param doc table        a Pandoc document
---@param format string    the target writer (e.g. "epub3", "docx", "latex")
---@param opts table|nil   writer options (e.g. { html_math_method = "mathml" })
---@return table  list of failure diagnostic strings (empty = all convert)
function M.unconvertible(doc, format, opts)
  -- pcall belongs inside the silence callback — see kast.md
  local write_ok
  local messages = pandoc.log.silence(function()
    -- writer_options is a valid 3rd arg (pandoc 3.x); the bundled type stub
    -- declares only two, so silence its false "redundant parameter" warning.
    ---@diagnostic disable-next-line: redundant-parameter
    write_ok = pcall(pandoc.write, doc, format, opts or {})
  end)
  if not write_ok then return {} end

  local failures = {}
  for _, m in ipairs(messages) do
    if m.message:find(FAIL_SIGNAL, 1, true) then
      failures[#failures + 1] = m.message
    end
  end
  return failures
end

return M
