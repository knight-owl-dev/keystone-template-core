-- ast/hash.lua — Content digests. Part of KAST; see
-- https://keystone.knight-owl.dev/engine/kast/
--
-- Named for the concern rather than the one algorithm Pandoc exposes, so a
-- caller asking for a digest need not change if that stops being the only one.
-- It lives behind the seam because the namespace it draws from is claimed
-- there as a whole.

local M = {}

--- SHA-1 digest of `contents`, as lowercase hex.
---
--- This addresses content — a cache key, a stable generated name — rather than
--- authenticating it, which SHA-1 is no longer fit for.
---@param contents string  bytes to digest
---@return string  40-character lowercase hex digest
function M.sha1(contents)
  return pandoc.utils.sha1(contents)
end

return M
