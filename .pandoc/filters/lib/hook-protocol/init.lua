-- hook-protocol/init.lua — Which wire version to speak, and who speaks it.
--
-- `describe` is deliberately outside every protocol: a hook cannot be asked
-- which versions it speaks in a version not yet agreed. Its request carries
-- nothing and its reply is the same shape forever — protocols, targets, and
-- any engine floor. Everything after that follows the version chosen here.
--
-- Selection is the engine's, as the floor check is: a hook says what it can
-- do, and the side holding both halves of the answer decides.
--
-- Checking a reply enters here as well: a version owns the shape it asked for,
-- and what must hold whatever the shape is belongs above it.

local errors = ks_require("errors")

local M = {}

-- Versions this engine speaks, oldest first. A hook offering several gets the
-- newest they share, so both ends move forward without either being pinned.
M.SUPPORTED = { 1 }

--- Choose the newest version both ends speak.
---
--- Comparing the highest each side offers would be wrong whenever a set has a
--- gap: against a hook speaking 1 and 3, an engine speaking 1 and 2 would land
--- on 2, which the hook cannot answer. A hook that has dropped an old version
--- is exactly how such a gap appears, so membership is what decides.
---
--- A version arrives decoded from JSON and so is a float, but Lua stores an
--- integral float under the integer key, which is what makes the lookup meet.
---@param offered table|nil  the versions a hook says it speaks
---@return number|nil        the agreed version, or nil when there is none
function M.select(offered)
  if type(offered) ~= "table" then return nil end

  local speaks = {}
  for _, version in ipairs(offered) do speaks[version] = true end

  -- SUPPORTED runs oldest first, so walking back returns the newest shared.
  for index = #M.SUPPORTED, 1, -1 do
    if speaks[M.SUPPORTED[index]] then return M.SUPPORTED[index] end
  end
  return nil
end

--- The module implementing one version's request and reply shapes.
---@param version number
---@return table
function M.for_version(version)
  return ks_require("hook-protocol.v" .. string.format("%d", version))
end

-- An asset's name becomes a filename under the cache entry and a key in the
-- resource store, so it has to be one: a separator or a traversal would put
-- the file outside the entry, in a directory the author mounted.
local function is_filename(name)
  return name ~= "" and name ~= "." and name ~= ".." and not name:find("/", 1, true)
end

--- Reject a reply that cannot be used, whichever version shaped it.
---
--- The version module owns the reply's shape. What the engine can then do with
--- the parts is the same in every version, so it is checked here, where a later
--- version cannot quietly stop enforcing it.
---
--- Order matters: the shared rules read fields the version check has just
--- guaranteed.
---@param version number    the agreed wire version
---@param reply table      what the hook sent
---@param where string      the hook and block, for the message
function M.check_transform(version, reply, where)
  M.for_version(version).check_transform(reply, where)

  local seen = {}
  for index, asset in ipairs(reply.assets or {}) do
    if not is_filename(asset.name) then
      errors.fatal({
        problem = where .. " returned asset " .. index .. " named '" ..
          asset.name .. "', which is not a filename",
        see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
      })
      return
    end

    -- The engine files an asset under its name, so a repeat within one reply
    -- overwrites and leaves the body pointing at whichever landed last. Across
    -- replies names are free: each response is filed under its own key.
    if seen[asset.name] then
      errors.fatal({
        problem = where .. " returned two assets named '" .. asset.name .. "'",
        see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
      })
      return
    end
    seen[asset.name] = true
  end
end

--- Render a version list for a person.
---
--- Decoded JSON integers arrive as floats, so an unformatted one reads "1.0"
--- in the very message whose job is naming a version exactly.
---@param versions table|nil
---@return string
function M.list_text(versions)
  if type(versions) ~= "table" or #versions == 0 then return "none" end

  local text = {}
  for index, version in ipairs(versions) do
    text[index] = type(version) == "number"
      and string.format("%d", version)
      or tostring(version)
  end
  return table.concat(text, ", ")
end

return M
