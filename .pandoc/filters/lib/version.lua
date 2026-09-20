-- version.lua — Comparing release versions.
--
-- Keystone states its version as a release tag, `vMAJOR.MINOR.PATCH`, and the
-- leading `v` is part of how it is written rather than part of the number —
-- so it is accepted and ignored.
--
-- Anything that is not that shape parses to nil rather than to a guess. An
-- unversioned build reports `local`, and a caller that cannot place a version
-- should say so instead of ordering it against one it can.

local M = {}

--- Split a release version into comparable parts.
---@param text string|nil  a version, with or without its leading `v`
---@return table|nil       { major, minor, patch }, or nil if unparseable
function M.parse(text)
  if type(text) ~= "string" then return nil end
  local major, minor, patch = text:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

--- Is `have` the same version as `want`, or a later one?
---
--- Both come from parse(). Comparing parsed parts rather than strings is the
--- point: "v2.10.0" precedes "v2.9.0" alphabetically and follows it in fact.
---@param have table  parsed version
---@param want table  parsed version to reach
---@return boolean
function M.at_least(have, want)
  for i = 1, 3 do
    if have[i] ~= want[i] then return have[i] > want[i] end
  end
  return true
end

return M
