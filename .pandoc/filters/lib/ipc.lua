-- ipc.lua — Request/response over a Unix domain socket.
--
-- The seam between the engine and a hook: a sidecar process the author wires
-- in, reachable only through a socket a compose file mounts. A caller hands
-- over a table and receives one, never learning how either crossed.
--
-- Leaving the process is what this module owns. The encoding on the way out is
-- json's, since a cache entry is written in the same shape and one codec is
-- what keeps the two agreeing.
--
-- socat is the client rather than a socket library because Lua has none, and
-- because the exchange is one round trip: write the request, half-close, read
-- the reply. It exits non-zero when the socket is absent, which surfaces as an
-- error here rather than an empty reply that would look like a hook with
-- nothing to say.
--
-- The timeout arrives as an argument. It is a build setting the author can
-- raise, so publish.sh owns its default and the calling filter passes it down;
-- a constant here would be a second owner nobody could see. Both socat
-- timeouts carry it: -T bounds silence, and -t bounds the wait after the
-- half-close at a default of half a second — short enough to discard the reply
-- of any hook that renders something.

local errors = ks_require("errors")
local json = ks_require("json")

local M = {}

-- Seam for tests, mirroring env_io._getenv and errors._exit: the one call that
-- leaves the process, overridable so a spec exercises the protocol without one.
M._pipe = function(command, args, stdin)
  return pandoc.pipe(command, args, stdin)
end

--- Send `request` to the hook listening at `socket_path` and return its reply.
---
--- Both directions are tables; the encoding is this module's business. A
--- transport failure — no socket, a timeout, a hook that dies mid-reply —
--- raises, because there is no partial answer worth returning.
---
--- A reply that decodes to anything but an object fails here too, so callers
--- can read fields off the result without each re-checking that they can. The
--- socket names the culprit, which is all this layer knows about it.
---@param socket_path string  absolute path to the hook's socket
---@param request table       the request payload
---@param timeout string      seconds to wait for the reply
---@return table              the decoded reply
function M.call(socket_path, request, timeout)
  local reply = M._pipe("socat", {
    "-t", timeout, "-T", timeout, "-", "UNIX-CONNECT:" .. socket_path,
  }, json.encode(request))

  local decoded = json.decode(reply)
  if type(decoded) ~= "table" then
    errors.fatal({
      problem = "the hook at " .. socket_path .. " replied with something that is not an object",
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#its-reply-was-unusable",
    })
  end
  return decoded
end

return M
