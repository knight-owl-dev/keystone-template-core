-- hooks.lua — Finding hook processes and asking them to transform a block.
--
-- A hook is a process the author wires in through compose. The engine is never
-- told about it: it looks in the hook directory and finds whatever is there, so
-- adding one is a compose edit rather than an engine change.
--
-- Socket filenames are the registry. Sorted, they also fix precedence, so two
-- hooks claiming the same language resolve the same way on every machine and
-- renaming one is enough to reorder them. The name is an identity, not a
-- language — a hook says which languages it claims, and may claim several.
--
-- Everything a hook says is checked before it is believed, and a disagreement
-- ends the build rather than degrading it: a wrong answer here would otherwise
-- surface far downstream as a missing figure or a broken reference, with
-- nothing pointing back at the process that caused it.
--
-- Wire shapes live in hook-protocol/, one file per version, so this file is
-- about which hook to ask rather than how to phrase the question.

local errors = ks_require("errors")
local hook_diagnostics = ks_require("hook-diagnostics")
local ipc = ks_require("ipc")
local json = ks_require("json")
local kast = ks_require("ast")
local protocol = ks_require("hook-protocol")
local text = ks_require("text")
local version = ks_require("version")

local M = {}

local SOCKET_SUFFIX = ".sock"

-- Enough of a block to tell two apart at a glance, and short enough that the
-- message it sits in stays one line in a terminal.
local EXCERPT_LIMIT = 48

--- Ask a hook, naming it if the transport fails.
---
--- ipc moves bytes and does not know whose socket it holds, so it raises; the
--- hook's identity lives here. Without this the author gets Pandoc's "Error
--- running filter" and a traceback into filter source — the very thing the
--- errors lib exists to replace — for the most ordinary failure there is, a
--- sidecar that died or ran long.
---
--- No element context: a transport failure is about the hook, not about the
--- block that happened to be next, and naming one of twenty identical fences
--- would only imply the block was at fault.
---@param hook string     the hook's name, for the message
---@param socket string   its socket path
---@param request table   the payload
---@param timeout string  seconds to wait
---@return table          the decoded reply
local function ask(hook, socket, request, timeout)
  -- ipc's own fatal exits the process, so pcall cannot catch it; only a
  -- genuine transport failure reaches here. (Under a stubbed fatal in tests it
  -- raises instead, and this would re-wrap it.)
  local ok, reply = pcall(ipc.call, socket, request, timeout)
  if not ok then
    -- The transport's own account of the failure, relayed: it is Lua's or the
    -- socket's wording, and reflowing it into Keystone's sentence would scatter
    -- whatever structure it came with.
    errors.fatal({
      problem = "hook '" .. hook .. "' did not answer '" .. request.op
        .. "' (died, refused, or past the " .. timeout .. "s timeout)",
      verbatim = tostring(reply),
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#it-did-not-answer",
    })
  end
  return reply
end

--- Reject a self-description this engine cannot honor.
---
--- Every failure here is the author's to fix — a hook too new for the engine,
--- or one that cannot introduce itself — so each names the hook and both sides
--- of the disagreement.
---@param agreed number|nil  the version negotiated from the reply, if any
local function check_describe(name, reply, agreed, keystone_version)
  if not agreed then
    errors.fatal({
      problem = "hook '" .. name .. "' speaks " .. protocol.list_text(reply.protocols)
        .. "; this engine speaks " .. protocol.list_text(protocol.SUPPORTED),
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#it-disagrees-with-the-engine",
    })
    return
  end

  -- A version either side cannot state precisely lifts the floor rather than
  -- tripping it: an unversioned build has nothing to be measured against.
  local floor = version.parse(reply.min_keystone_version)
  local engine = version.parse(keystone_version)
  if floor and engine and not version.at_least(engine, floor) then
    errors.fatal({
      problem = "hook '" .. name .. "' needs Keystone " .. reply.min_keystone_version
        .. "; this engine is " .. keystone_version,
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#it-disagrees-with-the-engine",
    })
    return
  end

  if type(reply.targets) ~= "table" or #reply.targets == 0 then
    errors.fatal({
      problem = "hook '" .. name .. "' claims no languages",
      because = "A hook must answer 'describe' with a non-empty targets list.",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#it-disagrees-with-the-engine",
    })
    return
  end

  -- Absent is a position, not an omission — see M.discover. Present and empty
  -- is neither, and would key a cache on nothing.
  if reply.identity ~= nil and not json.is_null(reply.identity)
    and (type(reply.identity) ~= "string" or reply.identity == "") then
    errors.fatal({
      problem = "hook '" .. name .. "' sent an identity that is not a non-empty string",
      remedy = "Send a string that changes whenever your answers would, or omit it.",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
    })
    return
  end

  -- Last, so a hook that cannot introduce itself is answered on that before it
  -- is asked what else it wanted to say.
  hook_diagnostics.configuration(name, reply.diagnostics)
end

--- Fold the output formats a hook answers alike under one cache key.
---
--- A hook may render several formats from one picture — a raster serving PDF,
--- DOCX and ODT alike — and only it knows which. Declaring that lets the engine
--- recognize the second and third as questions it has already answered, so they
--- are served from the cache rather than asked again.
---
--- What arrives is a partition and nothing else: groups of formats, unnamed.
--- A name would be one hook's vocabulary on a field no protocol version can
--- reshape, and what reads as an obvious split for diagrams describes nothing
--- for a hook that answers with a table.
---
--- The key is every format in the group, sorted and joined. Regrouping is then
--- a different key rather than the same one meaning something else: a hook that
--- corrects `[["epub","pdf"]]` to two groups changes nothing about how it
--- renders, so nothing else would move, and the entry holding the PDF's picture
--- would be served to EPUB. A one-format group is that format's own name, which
--- is what an undeclared format keys by, so the two agree.
---
--- A format in two groups is refused. The two would disagree about which answer
--- serves it, and picking one silently is how a book ends up with the asset
--- built for something else.
---@param name string        the hook's name, for the message
---@param groups table|nil   what the hook sent as `formats`
---@return table             format → cache key, empty when nothing was declared
local function format_keys(name, groups)
  if groups == nil or json.is_null(groups) then return {} end

  if type(groups) ~= "table" or (#groups == 0 and next(groups) ~= nil) then
    errors.fatal({
      problem = "hook '" .. name .. "' sent formats that are not a list of groups",
      because = "Each group is a list of format names, and the groups are a list of"
        .. " those.",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
    })
    return {}
  end

  local keys = {}
  for index, formats in ipairs(groups) do
    if type(formats) ~= "table" or #formats == 0 then
      errors.fatal({
        problem = "hook '" .. name .. "' sent format group " .. index
          .. " with no formats in it",
        because = "A group is a list of format names.",
        remedy = "One format alone is [[\"pdf\"]] rather than [\"pdf\"].",
        see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
      })
      return {}
    end

    local members, in_group = {}, {}
    for _, format in ipairs(formats) do
      if type(format) ~= "string" then
        errors.fatal({
          problem = "hook '" .. name .. "' sent format group " .. index
            .. " holding something that is not a format name",
          see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
        })
        return {}
      end
      if keys[format] then
        errors.fatal({
          problem = "hook '" .. name .. "' puts '" .. format .. "' in two format groups",
          see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
        })
        return {}
      end
      -- Checked as each name is read, since keys is only written once the group
      -- is whole — a repeat inside one group would otherwise key on it twice.
      if in_group[format] then
        errors.fatal({
          problem = "hook '" .. name .. "' names '" .. format
            .. "' twice in format group " .. index,
          see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
        })
        return {}
      end
      in_group[format] = true
      members[#members + 1] = format
    end

    -- Sorted, so a hook building this list from an unordered map keys the same
    -- way run to run. Unsorted, the order it happened to emit would be part of
    -- the key, and every entry would miss for no visible reason.
    table.sort(members)
    local key = table.concat(members, ",")

    for _, format in ipairs(formats) do
      keys[format] = key
    end
  end
  return keys
end

--- Build the language→hook routing table by asking every socket in `dir`.
---
--- Returns an empty table when nothing is listening, which is the normal case:
--- most projects wire no hook, and the caller installs no handler.
---
--- Discovery happens once per filter process and is the only place a hook's
--- absence or breakage surfaces, so a build with a dead hook fails here rather
--- than block by block.
---
--- A hook's `identity` rides along: a string it computes from whatever its
--- answers depend on — its own version, the settings it was configured with.
--- The engine never reads it, only keys on it, so a hook that changes says so
--- without the engine learning what changed.
---
--- Answering without one leaves the engine unable to tell a stale answer from
--- a fresh one, so it keeps none of them. Rendering everything again is a cost;
--- shipping a book built from an answer that no longer holds is a defect.
---@param dir string              directory holding hook sockets
---@param list_directory function pandoc.system.list_directory (injected for testability)
---@param path_join function      pandoc.path.join (injected for testability)
---@param opts table              { timeout = string, keystone_version = string }
---@return table  { [language] = { socket, hook, protocol, formats, identity } } per route
function M.discover(dir, list_directory, path_join, opts)
  local entries = list_directory(dir)
  table.sort(entries)

  local routes = {}
  for _, entry in ipairs(entries) do
    local name = entry:match("^(.+)" .. SOCKET_SUFFIX .. "$")
    if name then
      local socket = path_join({ dir, entry })
      local reply = ask(name, socket, { op = "describe" }, opts.timeout)
      local agreed = protocol.select(reply.protocols)
      check_describe(name, reply, agreed, opts.keystone_version)
      local group_keys = format_keys(name, reply.formats)

      -- First claim wins, so precedence follows the sorted filenames above.
      for _, target in ipairs(reply.targets) do
        if not routes[target] then
          routes[target] = {
            socket = socket, hook = name, protocol = agreed, formats = group_keys,
            identity = reply.identity,
          }
        end
      end
    end
  end
  return routes
end

--- The identity of one transform: the same block, sent to the same hook for an
--- output it answers the same way, always produces the same key.
---
--- Built from the inputs rather than from the request they become, because the
--- wire shape belongs to a protocol version, and a key that moved with it would
--- discard every stored answer on an upgrade that changed no content.
---
--- The format enters as the key the hook gave its group, so a hook serving
--- several formats from one picture is asked once for all of them. Absent a
--- declaration that is the format itself, which is what it has always been.
---
--- The hook's identity enters too, so a hook whose answers have changed reads
--- as a hook that has not been asked yet. Nothing is stored under a key with
--- no identity in it — see M.discover — but one is still built, because the
--- assets a reply carries are namespaced by it either way.
---@param route table  a routing entry from discover()
---@param input table  { target = language, format = output format, content = the block }
---@return string      40-character hex digest
function M.request_key(route, input)
  local format = (route.formats or {})[input.format] or input.format
  return kast.hash.sha1(table.concat({
    route.hook, route.identity or "", input.target, format, input.content,
  }, "\0"))
end

--- Whether a hook's answers may be remembered between builds.
---@param route table  a routing entry from discover()
---@return boolean     false when the hook declared no identity
function M.cacheable(route)
  return route.identity ~= nil
end

--- Send a block to the hook that claims its language and return its reply.
---@param route table     a routing entry from discover()
---@param input table     { target = language, format = output format, content = the block }
---@param timeout string  seconds to wait
---@return table          the hook's reply, checked
function M.transform(route, input, timeout)
  local speaks = protocol.for_version(route.protocol)
  local where = "hook '" .. route.hook .. "' on a '" .. input.target .. "' block"

  -- Which block, for the failures that are about one. `ask` keeps its own
  -- message clear of this: a hook that died was not answering any block in
  -- particular, and naming the one that happened to be next would read as
  -- blame. A rejected reply is the opposite — the block is the subject, and one
  -- fence of twenty looks like the rest without it.
  local excerpt = text.excerpt(input.content, EXCERPT_LIMIT)
  if excerpt ~= "" then
    where = where .. ' starting "' .. excerpt .. '"'
  end

  local reply = ask(route.hook, route.socket, speaks.transform_request(input), timeout)

  protocol.check_transform(route.protocol, reply, where)

  -- Assets cross as text because JSON carries text. Decoding here means no
  -- caller handles the encoded form, and the cache stores bytes an author can
  -- open.
  for _, asset in ipairs(reply.assets or {}) do
    asset.bytes = kast.mediabag.decode(asset.media_type, asset.data)
    if not asset.bytes then
      errors.fatal({
        problem = where .. " sent '" .. asset.name .. "' with no decodable bytes",
        because = "Asset data is base64.",
        see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
      })
    end
  end
  return reply
end

return M
