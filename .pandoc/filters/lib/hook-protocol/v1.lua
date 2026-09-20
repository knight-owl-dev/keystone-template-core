-- hook-protocol/v1.lua — The first wire version: what a transform looks like
-- going out, and what counts as an answer coming back.
--
-- Everything version-specific about talking to a hook lives here. A later
-- version is a sibling file, not an edit to this one, and the negotiation in
-- init.lua decides which is in play.

local errors = ks_require("errors")
local hook_diagnostics = ks_require("hook-diagnostics")
local json = ks_require("json")

local M = {}

--- Build the request for one block.
---
--- The block goes over verbatim. Nothing describes the div around it, because
--- a hook never sees one, and nothing describes the engine, because a hook has
--- no decision left to make with it.
---@param input table  { target = language, format = output format, content = the block }
---@return table       the wire request
function M.transform_request(input)
  return {
    op = "transform",
    target = input.target,
    format = input.format,
    content = input.content,
  }
end

--- Reject a reply that cannot be used, before a caller splices anything.
---
--- A hook answering with nothing usable has failed at its one job, and the
--- author needs to know which hook and which block. Assets are optional; one
--- that is present must be complete, since a half-described asset would reach
--- the document as a broken reference rather than an error.
---
--- `error` comes first because a hook that sends one is not answering: it is
--- refusing, and its own account of why beats anything inferred from what the
--- reply then lacks — a reply carrying one would otherwise fall through to
--- "returned no body", the uninformative message `error` exists to replace.
--- What it carries and how it reads are hook-diagnostics', because `describe`
--- sends the same shape and is negotiated by no version at all.
---
--- Every branch below ends the process, so its return is unreachable. They are
--- there for the reader, and for an analyzer that cannot see through a lib
--- call the way it would a bare error().
---@param reply table   what the hook sent; an object, by the transport's contract
---@param where string  the hook and block, for the message
function M.check_transform(reply, where)
  -- Absent or null alike: a hook that set the field and had nothing to put in
  -- it is not refusing the block, and reading one as a refusal would throw away
  -- the body sitting beside it.
  if reply.error ~= nil and not json.is_null(reply.error) then
    hook_diagnostics.refusal(where, reply.error)
    return
  end

  if type(reply.body) ~= "string" then
    errors.fatal({
      problem = where .. " returned no body",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
    })
    return
  end

  if json.is_null(reply.assets) then reply.assets = nil end

  if reply.assets ~= nil and type(reply.assets) ~= "table" then
    errors.fatal({
      problem = where .. " returned assets that are not a list",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
    })
    return
  end

  for index, asset in ipairs(reply.assets or {}) do
    for _, field in ipairs({ "name", "media_type", "data" }) do
      if type(asset[field]) ~= "string" then
        errors.fatal({
          problem = where .. " returned asset " .. index .. " with no " .. field,
          see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
        })
        return
      end
    end
  end
end

return M
