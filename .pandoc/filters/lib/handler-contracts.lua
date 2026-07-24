-- handler-contracts.lua — Load handler modules and read their declared contracts
--
-- A handler's returned table may declare a `required_attributes` list — the
-- attributes it cannot run without (vspace needs `size`, set needs `mark`).
-- Enforcement lives at shortcut load, not in the handler (see shortcuts.lua);
-- this lib only loads modules and reads the contract:
--
--   load(path, class)        dofile the handler + guard that it returned a table
--   required_of(raw, class)  read + validate `required_attributes` ({} if none)
--   unmet(required, iface)   which required attrs the interface fails to guarantee
--
-- divs.lua loads handlers to wire their hooks; shortcuts.lua loads them to read
-- `required_attributes`. Extracting load() here keeps the "must return a table"
-- invariant in one place rather than duplicated across both filters.
--
-- Guards raise bare error() — a mis-declared contract is an internal-invariant
-- bug, not author input (see lib/errors.lua).

local M = {}

--- dofile a handler module and guard its return type.
---@param handler_path string  path to divs/<class>/handler.lua
---@param class_name string    class name, for the error message
---@return table  the handler's format-hook + contract table
function M.load(handler_path, class_name)
  local raw = dofile(handler_path)
  if type(raw) ~= "table" then
    error("divs/" .. class_name .. "/handler.lua must return a table, got " .. type(raw))
  end
  return raw
end

--- Read and validate a handler's `required_attributes` (absent → {}). One flat
--- list covers both div and span forms — a shortcut routes to its handler for
--- both, and no handler needs a field in one form but not the other.
---@param raw table          a loaded handler table
---@param class_name string  class name, for error messages
---@return string[]  list of required attribute names (possibly empty)
function M.required_of(raw, class_name)
  local required = raw.required_attributes
  if required == nil then return {} end
  if type(required) ~= "table" then
    error("divs/" .. class_name .. "/handler.lua: `required_attributes` must be a list, got "
      .. type(required))
  end
  for _, attr in ipairs(required) do
    if type(attr) ~= "string" then
      error("divs/" .. class_name .. "/handler.lua: `required_attributes` entries must be strings, got "
        .. type(attr))
    end
  end
  return required
end

--- Which of a handler's required attributes are not guaranteed to reach it.
--- A is guaranteed when an interface entry binds `<bind_class>.A` with a default
--- or `required: true`, or when `baked` already carries A. Entries binding any
--- other target don't count.
---@param required string[]   the handler's required attribute names
---@param interface table     a resolved interface (name → { bind, default, required })
---@param bind_class string|nil  bind prefix routing to this handler; default "class"
---@param baked table|nil     attributes already present on the body div
---@return string[]  required attrs with no guaranteeing source
function M.unmet(required, interface, bind_class, baked)
  bind_class = bind_class or "class"
  baked = baked or {}
  local missing = {}
  for _, attr in ipairs(required) do
    local guaranteed = baked[attr] ~= nil
    if not guaranteed then
      local target = bind_class .. "." .. attr
      for _, entry in pairs(interface) do
        if entry.bind == target and (entry.default ~= nil or entry.required == true) then
          guaranteed = true
          break
        end
      end
    end
    if not guaranteed then
      missing[#missing + 1] = attr
    end
  end
  return missing
end

return M
