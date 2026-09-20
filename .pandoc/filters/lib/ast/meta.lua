-- ast/meta.lua — Pandoc Meta inspection and the two metadata-mutation idioms.
-- Part of KAST; see https://keystone.knight-owl.dev/engine/kast/
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

--- Split a metadata value into the words it names, whatever shape it arrived in.
---
--- A YAML list and a lone scalar are indistinguishable by plain Lua type here:
--- both reach a filter as a table, the list holding one entry per item and the
--- scalar holding the inline run of its single value. Nor does one call to
--- `pandoc.utils.stringify` help: it concatenates a list's items with nothing
--- between them, fusing `[a, b]` into `ab`. So each entry goes through
--- stringify on its own and the results are split again, which lands on the
--- same words for either shape — no need to tell the two apart, which is why
--- this reaches for no type check where `items` must.
---
--- Commas separate as well as whitespace, since the list notations authors
--- write in metadata (class options, keywords) accept both.
---
---@param value any  A pandoc Meta value (MetaList, MetaInlines, …) or nil
---@return table     Array of words; empty when the value is absent or blank
function M.words(value)
  local words = {}
  if value == nil then return words end

  local entries = type(value) == "table" and value or { value }
  for _, entry in ipairs(entries) do
    for word in M.stringify(entry):gmatch("[^%s,]+") do
      table.insert(words, word)
    end
  end
  return words
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
    errors.fatal({
      problem = string.format("%s must be a positive number, got: '%s'", field, str),
      see = "https://keystone.knight-owl.dev/errors/missing-metadata/#a-value-it-cant-accept",
    })
  end
  -- errors.fatal exits, so n is never nil here.
  ---@diagnostic disable-next-line: return-type-mismatch
  return n
end

--- Validate that a stringified metadata value names one of `allowed`,
--- returning it. Hard-fails via errors.fatal otherwise.
---
--- The diagnostic enumerates what was allowed, because a rejected value is
--- almost always a near miss and the author needs the vocabulary rather than
--- the verdict. Order comes from `allowed`, so a caller can lead with the
--- default rather than sorting alphabetically.
---
--- The caller owns the unset case: decide default-vs-required on a blank value
--- (via `is_blank`) before calling, since this fatals on one.
---
---@param str string     a stringified metadata value (see `stringify`)
---@param field string   metadata key name, for the diagnostic
---@param allowed table  list of accepted values
---@return string        `str`, unchanged
function M.require_one_of(str, field, allowed)
  for _, candidate in ipairs(allowed) do
    if str == candidate then return str end
  end
  errors.fatal({
    problem = string.format("%s does not take '%s'", field, str),
    choices = allowed,
    see = "https://keystone.knight-owl.dev/errors/missing-metadata/#a-value-it-cant-accept",
  })
  return str  -- unreachable: errors.fatal exits
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

--- True when a metadata value is a YAML list rather than a single value. Both
--- arrive as tables, so only Pandoc's own type separates them.
local function is_list(value)
  return pandoc.utils.type(value) == "List"
end

--- Split a metadata value into comma-separated items, whatever shape it
--- arrived in. Surrounding whitespace is trimmed and empty items dropped, so a
--- trailing comma is harmless.
---
--- The comma-only sibling of `words`. Use this where an item may contain
--- spaces: a TeX dimension may, and `paperwidth=5 in` is a legal five-inch page
--- that splitting on whitespace would read as a five-point one. Use `words`
--- where items are single tokens (class options, keywords) and an author may
--- separate them either way.
---
--- A comma inside braces belongs to the item, not between two: geometry writes
--- a dimension pair as `papersize={5in,5in}`. Splitting it would still rejoin
--- correctly on the way out, since the separator is the same character — but an
--- item is also what a diagnostic quotes back, and half of one is no use to the
--- author reading it.
---
--- Braces are the whole of it. They are the only grouping LaTeX keyval accepts:
--- `papersize=(5in,7in)` and `papersize=[5in,7in]` are errors, not alternative
--- spellings, so there is no second delimiter to track.
---
--- A YAML list is read entry by entry rather than through one `stringify` of
--- the whole value, which would fuse the entries with nothing between them —
--- the same hazard `words` documents.
---
---@param value any  A pandoc Meta value (MetaList, MetaInlines, …) or nil
---@return table     Array of items; empty when the value is absent or blank
function M.items(value)
  local items = {}
  if value == nil then return items end

  local function add(piece)
    local trimmed = text.trim(piece)
    if trimmed ~= "" then items[#items + 1] = trimmed end
  end

  local entries = is_list(value) and value or { value }
  for _, entry in ipairs(entries) do
    local raw = M.stringify(entry)
    local depth, start = 0, 1
    for i = 1, #raw do
      local char = raw:sub(i, i)
      if char == "{" then
        depth = depth + 1
      elseif char == "}" then
        -- Clamp, so a stray closing brace cannot drive the depth negative and
        -- swallow every separator after it.
        depth = math.max(0, depth - 1)
      elseif char == "," and depth == 0 then
        add(raw:sub(start, i - 1))
        start = i + 1
      end
    end
    add(raw:sub(start))
  end
  return items
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
