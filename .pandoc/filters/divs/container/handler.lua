-- Pure structural grouping — no visual output for any format.
-- Returning nil defers to Pandoc's default behavior: EPUB/HTML emits the
-- div/span with its classes intact; LaTeX passes content through unchanged.
-- See README.md for usage.

local function default(_el)
  return nil
end

return {
  div = {
    default = default,
  },
  span = {
    default = default,
  },
}
