-- hook-diagnostics.lua — Reading the diagnostics a hook sends.
--
-- A hook reports a problem in the same callout table Keystone's own filters
-- declare: it names the pieces of a message and the errors lib assembles them.
-- The JSON keys are the callout names, so nothing is translated here and there
-- is no second vocabulary to hold in step — what a hook may send is whatever
-- errors.lua renders, less `describe`, which is a Lua thunk and has no JSON
-- form. No check here names that exception — a thunk is the one shape no JSON
-- value takes, so the test every callout goes through already refuses it.
--
-- Both entry points meet here. A `describe` diagnostic reports on how the hook
-- was configured and carries a severity beside its callouts; a `transform`
-- refusal reports on one block and carries none, because a hook refusing a
-- block has nothing further to offer for it. The rest is shared, so it lives
-- here rather than once per caller.
--
-- Anything that does not land is one refusal quoting the object whole, rather
-- than a complaint per key. Strictness costs the author nothing that way: the
-- hook's author sees the defect, and the book's author still sees whatever the
-- hook was trying to say.
--
-- The object form only, where errors.lua also takes a bare string. A `describe`
-- diagnostic needs somewhere to put its severity, and a wire shape that is an
-- object in one message and a string in the other would cost a hook author more
-- than the ceremony it saves them.

local errors = ks_require("errors")
local json = ks_require("json")

local M = {}

-- What a hook may call a diagnostic. The two match the severities the engine
-- already has, so a hook chooses between "stop" and "say so" and nothing
-- further: whether a warning ends the build is the author's setting to make,
-- rather than a level for a hook to reach for.
local SEVERITIES = { warning = true, error = true }

--- Keystone's naming, ahead of the hook's own words.
---
--- A prefix is one more part of a list rather than a second code path. It joins
--- with a space like any other, so it carries none of its own — the sink reads
--- the parts unrendered, where a doubled space would survive.
---@param problem string|table  the hook's problem, already checked
---@param with string           what names the hook, up to its connector
---@return string|table
local function prefix(problem, with)
  if type(problem) ~= "table" then return with .. " " .. problem end

  local parts = { with }
  for _, part in ipairs(problem) do parts[#parts + 1] = part end
  return parts
end

--- The callout a diagnostic object carries, or nil when it cannot be read.
---
--- `sibling` names the one key that is not a callout. It is lifted off before
--- the rest is read, and comes back beside the callout.
---
--- Checked before the prefix goes on, so a hook that sent no problem is refused
--- rather than answered with Keystone's half of a sentence and nothing after it.
---@param where string     how the engine names the hook, for the message
---@param object any       what the hook sent
---@param sibling string|nil  the key beside the callouts, if this shape has one
---@return table|nil, any  the callout, and the sibling's value
local function read(where, object, sibling)
  if type(object) ~= "table" then return nil end

  local callout, lifted = {}, nil
  for key, value in pairs(object) do
    if key == sibling then
      lifted = value
    else
      -- A null carries nothing, which is what leaving the key out means. The
      -- key is kept and emptied rather than dropped, so its NAME is still
      -- checked. Dropping it would pass a misspelled callout in silence
      -- whenever its value was null — which is how a serializer writing every
      -- optional field spells one it had nothing for. An empty value renders as
      -- nothing.
      callout[key] = json.is_null(value) and "" or value
    end
  end

  if not errors.check(callout) then return nil end

  callout.problem = prefix(callout.problem, where .. ":")
  return callout, lifted
end

--- The callout refusing a diagnostic object the engine cannot read.
---
--- Quoted whole rather than faulted key by key: the hook was mid-sentence about
--- something, and a refusal that dropped its words would leave the author with
--- a broken build and no account of why the hook thought so.
---
--- Re-encoded rather than relayed byte for byte — the reply was decoded long
--- before it reached here — but every key and value in it is the hook's, which
--- is all the quote bar claims.
---
--- The remedy comes from the caller, because the two shapes disagree on exactly
--- the field a hook is most likely to get wrong.
---@param where string   how the engine names the hook, for the message
---@param object any     what the hook sent
---@param remedy string  what this shape wanted instead
---@return table
local function unreadable(where, object, remedy)
  return {
    problem = where .. " sent a diagnostic Keystone cannot read",
    because = "A diagnostic names the pieces of a message; Keystone assembles them.",
    verbatim = json.encode(object),
    remedy = remedy,
    see = "https://keystone.knight-owl.dev/hooks/writing-a-hook/#writing-the-message",
  }
end

--- Report everything a hook said about how it was configured.
---
--- A hook is configured by the project that wired it in, and a setting it
--- cannot act on is neither the engine's to interpret nor any block's fault.
--- `describe` is where it says so: asked once, before anything is walked, and
--- the only exchange that happens whether or not the manuscript holds a single
--- block the hook claims. A misconfigured hook in a book with no diagrams is
--- otherwise a hook nobody ever hears from.
---
--- Warnings are emitted before any error stops the build, so a run reports
--- everything the hook had to say rather than only its first complaint. Under
--- warnings-as-errors the engine's own sink promotes them, which is why
--- severity here stops at two.
---@param name string        the hook's name, for the message
---@param entries table|nil  what the hook sent as `diagnostics`
function M.configuration(name, entries)
  if entries == nil or json.is_null(entries) then return end

  local where = "hook '" .. name .. "'"

  -- A JSON array decodes to a table the length operator can measure; an object
  -- decodes to one it cannot, which is the shape this rejects.
  if type(entries) ~= "table" or (#entries == 0 and next(entries) ~= nil) then
    errors.fatal({ problem = where .. " sent diagnostics that are not a list" })
    return
  end

  local fatal = {}
  for _, entry in ipairs(entries) do
    local callout, severity = read(where, entry, "severity")

    -- Collected rather than raised on the spot: an entry the engine cannot read
    -- must not cost the author the entries it already read, which is the whole
    -- of what reporting them together is worth.
    --
    -- Fatal rather than a warning, whatever severity it claimed — the hook may
    -- have been stopping the build, and carrying on is the guess that ships a
    -- book the hook had already refused to be part of.
    if not callout or SEVERITIES[severity] == nil then
      fatal[#fatal + 1] = unreadable(where, entry,
        "Name the pieces of your message, with a severity of 'warning' or"
        .. " 'error' beside them.")
    elseif severity == "error" then
      fatal[#fatal + 1] = callout
    else
      errors.warn(callout)
    end
  end

  if #fatal > 0 then errors.fatal_each(fatal) end
end

--- Refuse a block in the hook's own words.
---
--- It is all a transform reply can say to the author — the hook's stderr belongs
--- to another container, and this side sees nothing but the bytes on the socket.
---@param where string  the hook and block, for the message
---@param object any    what the hook sent as `error`
function M.refusal(where, object)
  errors.fatal(read(where, object) or unreadable(where, object,
    "Name the pieces of your message. A refusal carries no severity, because a"
    .. " block the hook will not render leaves nothing to carry on with."))
end

return M
