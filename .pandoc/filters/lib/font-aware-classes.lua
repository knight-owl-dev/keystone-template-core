-- font-aware-classes.lua — Maps handler classes to their font-family attribute
--
-- Each handler that supports a font-family attribute names it in a way that
-- fits its context: "family" is natural on .font, "font-family" reads better
-- on .dropcap. This table maps each class to its attribute name so that:
--
--   * font-scan.lua detects content font references during the EPUB pre-scan
--   * keystone.lua collects used fonts for @font-face CSS generation
--
-- Adding a new family-aware handler: add a class = attribute entry below.
-- No other files need to change — both consumers derive behavior from this map.

local classes = {
  dropcap = "font-family",
  font = "family",
}

local lib = {}

--- Extract the font-family attribute value from a Div or Span element.
--- Accepts an optional namespace library for ks- prefix resolution so callers
--- running before divs.lua (which strips the prefix) still match correctly.
---@param el table         Pandoc Div or Span element with .classes and .attributes
---@param namespace table? Handler namespace lib with canonical() (optional)
---@return string|nil      The font-family attribute value, or nil if no match
function lib.family_value(el, namespace)
  for _, cls in ipairs(el.classes) do
    local canonical = namespace and namespace.canonical(cls) or cls
    local attr = classes[canonical]
    if attr and el.attributes[attr] then
      return el.attributes[attr]
    end
  end
  return nil
end

return lib
