---@diagnostic disable: undefined-global
-- hooks.lua — Replace code blocks a hook claims with the content it returns
--
-- Authors fence a diagram, a chart, or anything else a sidecar can render, in
-- its own language. This filter hands the block to whichever hook claims that
-- language and splices back what comes out — ordinary authored content, so
-- everything downstream treats it as though the author had written it.
--
-- Only the code block is replaced, never a div around it. A wrapping shortcut
-- therefore keeps its attributes and expands normally, which is why this runs
-- before shortcuts.lua: what a hook returns is author-level markup and still
-- needs author-level expansion.
--
-- Running first also draws a boundary: a shortcut's body is injected during
-- expansion, which happens later, so a fence written into a shortcut
-- definition reaches no hook. That is the intended line. Hooks transform what
-- an author wrote in a chapter; a definition that rendered through an external
-- process would do so at every use, and hide that cost from the call site.
--
-- publish.sh stages this filter only when a socket is actually present, so a
-- project that wires no hook never loads it.
--
-- Called by publish.sh as a Pandoc filter, ahead of every other filter.
--
-- Environment (set by publish.sh):
--   KEYSTONE_FORMAT          — the output format the author asked for (pdf,
--                              epub, docx, odt). Not the writer name: a hook
--                              chooses an asset for the document being made,
--                              and "pdf" is what distinguishes print from
--                              screen
--   KEYSTONE_HOOKS_CACHE     — where replies are remembered
--   KEYSTONE_HOOKS_CACHE_MAX — megabytes it may hold before the least recently
--                              used entries are dropped
--   KEYSTONE_HOOKS_DIR       — directory holding hook sockets
--   KEYSTONE_HOOKS_TIMEOUT   — seconds a hook has to answer

local path = pandoc.path

local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end

-- Install the memoized module loader, then acquire KAST and the hook libs.
-- See https://keystone.knight-owl.dev/engine/kast/
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")
local cache = ks_require("hook-cache")
local env_io = ks_require("env-io")
local hooks = ks_require("hooks")

local timeout = env_io.require_env("KEYSTONE_HOOKS_TIMEOUT")
local format = env_io.require_env("KEYSTONE_FORMAT")
local cache_dir = env_io.require_env("KEYSTONE_HOOKS_CACHE")

-- The author sets a size in megabytes; the cache weighs entries in bytes.
local cache_cap = tonumber(env_io.require_env("KEYSTONE_HOOKS_CACHE_MAX")) * 1024 * 1024

-- One discovery pass per filter process. Every hook is contacted here, so a
-- broken one fails the build before any block is walked.
local routes = hooks.discover(
  env_io.require_env("KEYSTONE_HOOKS_DIR"),
  pandoc.system.list_directory,
  path.join,
  { timeout = timeout, keystone_version = env_io.optional_env("KEYSTONE_VERSION") })

--- Store a reply's assets and return the names they were filed under.
---
--- Names are namespaced by the request key because they are the hook's to
--- choose: two unrelated diagrams whose hooks both answer "diagram.svg" would
--- otherwise collide, one silently replacing the other.
---
local function store_assets(assets, key)
  local stored_names = {}
  for _, asset in ipairs(assets or {}) do
    local stored = key .. "/" .. asset.name
    kast.mediabag.insert(stored, asset.media_type, asset.bytes)
    stored_names[asset.name] = stored
  end
  return stored_names
end

-- Whether anything new reached the cache this run. A build served entirely
-- from it has not grown it, so there is nothing to weigh at the end.
local stored_anything = false

--- The hook's answer for this block, asking only if it is not already known.
---
--- A hook that declared no identity is asked every time: the cache directory
--- goes in as nil, which hook-cache reads as caching off. hooks.discover owns
--- why.
local function answer(route, input, key)
  local dir = hooks.cacheable(route) and cache_dir or nil

  local remembered = cache.load(dir, key)
  if remembered then return remembered end

  local reply = hooks.transform(route, input, timeout)
  cache.store(dir, key, reply)
  stored_anything = stored_anything or dir ~= nil
  return reply
end

--- Point references in `blocks` at the assets they name.
---
--- A hook writes the plain name it chose; only here is the stored one known.
--- A reference to something the reply never sent is left alone — that is an
--- ordinary path into the project, not a name this response owns.
---
--- Images alone, because images alone resolve against the store: Pandoc writes
--- every other reference verbatim and packages nothing for it. An asset a reply
--- sends but merely links to would dangle no matter what this rewrote.
---
--- A reply carrying no assets, or content referencing none, passes through
--- untouched — what a hook returns is arbitrary, and assets are optional.
local function resolve_assets(blocks, stored_names)
  return kast.walk(blocks, {
    Image = function(image)
      local stored = stored_names[image.src]
      if stored then image.src = stored end
      return image
    end,
  })
end

function CodeBlock(el)
  local route = routes[el.classes[1]]
  if not route then return nil end

  local input = { target = el.classes[1], format = format, content = el.text }
  local key = hooks.request_key(route, input)
  local reply = answer(route, input, key)

  return resolve_assets(
    kast.read(reply.body, "markdown").blocks,
    store_assets(reply.assets, key))
end

-- Terminal handler: Pandoc runs it once the walk is done, which is where
-- eviction belongs. Weighing the cache costs a read per entry, so doing it
-- here rather than per stored reply keeps a build linear in its diagrams.
function Pandoc(doc)
  if stored_anything then
    cache.prune(cache_dir, cache_cap)
  end
  return doc
end
