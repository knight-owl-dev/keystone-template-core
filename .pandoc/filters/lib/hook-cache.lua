-- hook-cache.lua — Remembering what a hook already answered.
--
-- Rendering is the slow part of a hook, and a hook that says what its answers
-- depend on makes it the repeatable part: the same block, for the same format,
-- from the same hook at the same identity, yields the same reply. The engine
-- remembers it so a hook need not — content in, assets out, no notion of which
-- pass or which run it is serving.
--
-- The cache earns its place three times over. Pandoc walks the filters twice
-- for EPUB, so one render covers both passes. A rebuilt book skips the socket
-- entirely. And an author who points KEYSTONE_HOOKS_CACHE inside artifacts/
-- can open what the hook actually produced.
--
-- All of it is optional. A hook that declares no identity cannot be told apart
-- from a later version of itself, so nothing of its is kept: callers pass no
-- directory and every function here becomes a no-op. See hooks.discover.
--
-- An entry is a directory: an index naming the assets, and the assets beside
-- it as files rather than encoded inside it. Storing bytes as bytes is what
-- makes that third use work.

local errors = ks_require("errors")
local json = ks_require("json")

local M = {}

local INDEX = "reply.json"
local USED = "used"
local ASSETS = "asset"


-- Seams for tests: the filesystem is the whole of this module's behavior.
M._open = io.open
-- Resolved at call time rather than captured: the loader caches this module
-- table and a spec swaps the pandoc global between cases. _open is captured
-- because io is not the mocked one.
--
-- directory is a valid argument (pandoc 3.x); the bundled type stub declares
-- none, so silence its false "redundant parameter" warning.
---@diagnostic disable-next-line: redundant-parameter
M._list = function(dir) return pandoc.system.list_directory(dir) end
M._mkdir = function(dir) pandoc.system.make_directory(dir, true) end
M._remove = function(path) pandoc.system.remove_directory(path, true) end

local function read_file(path)
  local handle = M._open(path, "rb")
  if not handle then return nil end
  local contents = handle:read("a")
  handle:close()
  return contents
end

-- make_directory raises rather than returning a status, and the raise reaches
-- the author as a filter traceback that names neither the cache nor the path.
-- Reported the way a failed write is, so an unwritable cache reads the same
-- however it is reached.
local function make_dir(path)
  local made, reason = pcall(M._mkdir, path)
  if not made then
    errors.fatal({
      problem = "could not write the hook cache at " .. path,
      verbatim = tostring(reason),
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook",
    })
  end
end

local function write_file(path, contents)
  -- io.open's second return is the reason, and it is what separates a read-only
  -- mount from a wrong owner — the same thing make_dir relays.
  local handle, reason = M._open(path, "wb")
  if not handle then
    errors.fatal({
      problem = "could not write the hook cache at " .. path,
      verbatim = reason and tostring(reason) or nil,
      see = "https://keystone.knight-owl.dev/errors/hook-failed/#the-cache-rather-than-the-hook",
    })
    return
  end
  handle:write(contents)
  handle:close()
end

--- Note that an entry was wanted, so eviction can tell live from stale.
---
--- Recency is written down because it cannot be read back: the host exposes
--- no file timestamps, so an mtime the filesystem already keeps is not
--- available to us.
local function touch(entry)
  write_file(entry .. "/" .. USED, tostring(os.time()))
end

--- Drop the least recently wanted entries until the cache fits `cap`.
---
--- Weighing the cache means reading every index, so this is a once-per-run job
--- for the caller to place at the end — doing it per entry would turn storing
--- n replies into reading n² of them.
---
--- Evicting cannot disturb a build in flight. An asset the document references
--- is in the resource store by then, which holds the bytes rather than a path
--- to them, so what is dropped here is only the copy a later run would have
--- reused. Entries from this run carry the newest stamps in any case, so they
--- are the last to go.
---
--- Sizes are recorded at store time for the same reason recency is: the host
--- cannot measure a file, and reading every asset back to weigh it would cost
--- more than the eviction saves.
---@param dir string|nil  the cache directory, or nil when caching is off
---@param cap number      bytes the cache may occupy
function M.prune(dir, cap)
  if not dir then return end

  local entries = {}
  local total = 0

  -- A readable index is what proves an entry is this module's own, and
  -- eviction removes recursively — so anything without one is passed over
  -- rather than identified by the shape of its name. An author who points the
  -- cache into artifacts/ browses this directory; a stray file, or one of
  -- theirs, must survive a prune.
  --
  -- That leaves debris from a build killed mid-write unweighed and unswept. It
  -- is a few kilobytes and a rebuild of the same block overwrites it, which is
  -- a cheaper price than pointing rm at a directory on a guess. Clearing the
  -- cache sweeps the rest, and where the author put it decides that command.
  for _, name in ipairs(M._list(dir)) do
    local index = read_file(dir .. "/" .. name .. "/" .. INDEX)
    local reply = index and json.decode(index)
    if type(reply) == "table" then
      local size = reply.size or 0
      total = total + size
      entries[#entries + 1] = {
        name = name,
        size = size,
        used = tonumber(read_file(dir .. "/" .. name .. "/" .. USED) or "0") or 0,
      }
    end
  end

  if total <= cap then return end

  table.sort(entries, function(a, b) return a.used < b.used end)
  for _, entry in ipairs(entries) do
    if total <= cap then return end
    M._remove(dir .. "/" .. entry.name)
    total = total - entry.size
  end
end

--- Recall a reply, or nothing when this block has not been seen.
---
--- A partial entry — an index without its assets, half-written by a build that
--- died — reads as a miss, so the hook is asked again rather than the document
--- being built from a fragment.
---@param dir string|nil  the cache directory, or nil when caching is off
---@param key string      the request key
---@return table|nil      the remembered reply
function M.load(dir, key)
  if not dir then return nil end

  local entry = dir .. "/" .. key
  local index = read_file(entry .. "/" .. INDEX)
  if not index then return nil end

  local reply = json.decode(index)
  if type(reply) ~= "table" then return nil end

  for _, asset in ipairs(reply.assets or {}) do
    asset.bytes = read_file(entry .. "/" .. ASSETS .. "/" .. asset.name)
    if not asset.bytes then return nil end
  end

  touch(entry)
  return reply
end

--- Remember a reply against its key.
---
--- The index carries every field except the bytes, which sit beside it as
--- files. Nothing is stored twice: the bytes are read back from those files.
---@param dir string|nil  the cache directory, or nil when caching is off
---@param key string      the request key
---@param reply table     the hook's reply, with decoded asset bytes
function M.store(dir, key, reply)
  if not dir then return end

  local entry = dir .. "/" .. key
  local index = { body = reply.body, assets = {}, size = #reply.body }

  if reply.assets and #reply.assets > 0 then
    make_dir(entry .. "/" .. ASSETS)
    for position, asset in ipairs(reply.assets) do
      index.assets[position] = { name = asset.name, media_type = asset.media_type }
      index.size = index.size + #asset.bytes
      write_file(entry .. "/" .. ASSETS .. "/" .. asset.name, asset.bytes)
    end
  else
    make_dir(entry)
  end

  write_file(entry .. "/" .. INDEX, json.encode(index))
  touch(entry)
end

return M
