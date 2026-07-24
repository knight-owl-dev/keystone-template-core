-- safe-path.lua — Confine an author-supplied path to the project tree.
--
-- Author metadata can carry file paths (e.g. cover-image). Left unchecked, the
-- value reaches the toolchain verbatim, so an absolute path or a `..` escape
-- would read outside the project. This guard hard-fails such a value at the
-- metadata seam (#486).
--
-- Lexical, not symlink-resolved: a read here is harmless under the
-- secret-free-container invariant (the build runs on the public image with only
-- the submitter's own inputs and no network — see the #486 threat model), so
-- this blocks the obvious absolute/traversal cases and author mistakes. The
-- residual a crafted symlink could still slip past is already inert under that
-- invariant, which is why lexical is enough and realpath is not worth the cost.
-- "Absolute" is a leading "/" (the build container is Linux) or a URL scheme
-- (file:, http:, …) — the latter is an out-of-tree reference in path's clothing.

local errors = ks_require("errors")

local M = {}

--- Require a project-relative path: reject an absolute path, a URL scheme, or
--- any `..` segment. Hard-fails via errors.fatal; returns the value when ok.
---@param value string  author-supplied path
---@param field string  metadata field name, for the message
---@return string
function M.require_relative(value, field)
  -- Leading "/" is absolute; a "<scheme>:" prefix (file:, http:, …) is an
  -- out-of-tree reference that the leading-"/" test alone would miss.
  if value:sub(1, 1) == "/" or value:match("^%a[%w%+%-%.]*:") then
    errors.fatal("'" .. field .. "' must be a project-relative path, not an absolute path or URL: " .. value)
  end
  for component in value:gmatch("[^/]+") do
    if component == ".." then
      errors.fatal("'" .. field .. "' must stay within the project — remove the '..': " .. value)
    end
  end
  return value
end

return M
