-- page-position.lua — The page's column vocabulary, and the `<row>:<col>`
-- grammar that places the page number in it.
--
-- A position names one slot: a row (the header, the footer, or both) and a
-- column within it. A column is positional (left, center, right) or relative to
-- the spread (outer, inner), so the recto/verso split is a property of the
-- value itself.
--
-- `parse` and `column` both validate, through one splitter, so a malformed
-- position reports the same message whichever is called. `resolve_parity` takes
-- a bare column and validates nothing — a column can arrive from a key that has
-- no row, so its caller owns what it passes.

local kast = ks_require("ast")
local errors = ks_require("errors")

local M = {}

local ROWS = { "header", "footer", "header-and-footer" }

local COLUMNS = { "left", "center", "right", "outer", "inner" }

--- Split a position into its row and column, faulting on anything malformed.
---@param str string  a `page-number-position` value
---@return string row  one of header, footer, header-and-footer
---@return string col  one of left, center, right, outer, inner
local function split(str)
  local row, col = str:match("^([^:]+):([^:]+)$")
  if not row or not col then
    errors.fatal(string.format(
      "page-number-position must be of the form '<row>:<col>' "
      .. "(row in header|footer|header-and-footer, "
      .. "col in left|center|right|outer|inner); got %q",
      str))
  end
  kast.meta.require_one_of(row, "page-number-position row", ROWS)
  kast.meta.require_one_of(col, "page-number-position col", COLUMNS)
  return row, col
end

--- Resolve a column to the pair of columns it occupies on facing pages.
---
--- `outer` and `inner` are named for the spread, not the page: outer is the
--- edge a thumbing finger lands on, which is the right of a recto and the left
--- of a verso; inner is the binding edge, its mirror. The positional columns
--- name the same side on both parities.
---@param col string  one of left, center, right, outer, inner
---@return table  { recto = <positional col>, verso = <positional col> }
function M.resolve_parity(col)
  if col == "outer" then return { recto = "right", verso = "left" } end
  if col == "inner" then return { recto = "left", verso = "right" } end
  return { recto = col, verso = col }
end

--- The column a position names, discarding its row.
---
--- Serves the metadata layer, which settles a column for the opening-page
--- footer. That footer is always at the foot — an opening page has no running
--- header to hold it — so only the column carries over.
---@param str string  a `page-number-position` value
---@return string  one of left, center, right, outer, inner
function M.column(str)
  local _, col = split(str)
  return col
end

--- Parse a position into the per-row columns it occupies on each parity.
---
--- A row the folio does not occupy maps to nil on both parities, so a consumer
--- reads one shape whichever row was named.
---@param str string  a `page-number-position` value
---@return table  { header = { recto, verso }, footer = { recto, verso } }
function M.parse(str)
  local row, col = split(str)
  local parity = M.resolve_parity(col)
  local result = {
    header = { recto = nil, verso = nil },
    footer = { recto = nil, verso = nil },
  }
  if row == "header-and-footer" then
    result.header = parity
    result.footer = parity
  else
    result[row] = parity
  end
  return result
end

return M
