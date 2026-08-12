-- ast/meta.lua — Pandoc Meta inspection and the two metadata-mutation idioms.
-- Part of KAST; see docs/pandoc-integration/kast.md.
--
-- Pandoc surfaces bare YAML keys (e.g. `subject:` with no value) as non-nil
-- MetaValues that stringify to an empty string. Plain Lua truthiness reads
-- those as set, which silently breaks bridges and defaults. The inspection
-- helpers centralize the "is this really set?" check so every filter agrees
-- on the semantics. The mutators own the `or MetaList{}` first-use guard so
-- it is spelled exactly once.

local text = ks_require("text")
local errors = ks_require("errors")

local M = {}

--- Stringify a metadata value and trim leading/trailing whitespace.
---
--- Wraps `pandoc.utils.stringify` (which does not trim) and adds the
--- whitespace strip so callers can compare the result directly to "auto",
--- "disabled", etc. without re-implementing the trim. Returns "" for nil
--- and for bare YAML keys (e.g. `subject:` with no value), tilde-null
--- (`subject: ~`), and whitespace-only strings (`subject: "  "`) — all of
--- which Pandoc surfaces as non-nil but content-free Meta values.
---
---@param value any  A pandoc Meta value (MetaInlines, MetaString, etc.) or nil
---@return string    Trimmed string ("" if blank or nil)
function M.stringify(value)
  if value == nil then return "" end
  return text.trim(pandoc.utils.stringify(value))
end

--- True if a metadata value is absent or carries no usable content.
---
--- Convenience predicate over `stringify` — true when the trimmed string
--- is empty.
---
---@param value any  A pandoc Meta value (MetaInlines, MetaString, etc.) or nil
---@return boolean
function M.is_blank(value)
  return M.stringify(value) == ""
end

--- Validate that a stringified metadata value is a plain positive decimal,
--- returning it as a number. Hard-fails via errors.fatal otherwise.
---
--- Why not a bare `tonumber`: these values pass straight into TeX (e.g.
--- `\setstretch`, draftwatermark's scale), whose number scanner takes only a
--- plain decimal. `tonumber` is looser: it reads hex (`0x2`) and scientific
--- notation (`1e3`) — rejected here by the pattern — and it overflows a huge
--- input to `inf` — rejected by the finiteness check. Either would otherwise
--- abort xelatex cryptically or leak `inf` into the preamble.
---
--- The caller owns the unset case: decide default-vs-required on a blank value
--- (via `is_blank`) before calling, since this fatals on one.
---
---@param str string   a stringified metadata value (see `stringify`)
---@param field string metadata key name, for the diagnostic
---@return number      the parsed value (finite and > 0)
function M.require_positive_number(str, field)
  local n = str:match("^%d*%.?%d+$") and tonumber(str)
  if not n or n <= 0 or n == math.huge then
    errors.fatal(field .. " must be a positive number, got: " .. str)
  end
  -- errors.fatal exits, so n is never nil here.
  ---@diagnostic disable-next-line: return-type-mismatch
  return n
end

--- Append a LaTeX RawBlock to `header-includes`, creating the MetaList on
--- first use. `header-includes` is the metadata list Pandoc injects into the
--- preamble; it must be a MetaList, so the first append seeds one. Centralizes
--- the `meta[k] = meta[k] or MetaList{}; insert` idiom.
---@param meta table   Pandoc Meta object
---@param latex string raw LaTeX for the preamble
function M.add_header_include(meta, latex)
  meta["header-includes"] = meta["header-includes"] or pandoc.MetaList{}
  table.insert(meta["header-includes"], pandoc.RawBlock("latex", latex))
end

--- Append a stylesheet path to `meta.css`, creating the MetaList on first use.
--- `css` is the metadata list of stylesheet paths Pandoc links into CSS-based
--- outputs (EPUB/HTML). Centralizes the same first-use guard as
--- add_header_include.
---@param meta table  Pandoc Meta object
---@param path string stylesheet path
function M.add_css(meta, path)
  meta["css"] = meta["css"] or pandoc.MetaList{}
  table.insert(meta["css"], pandoc.MetaString(path))
end

return M
