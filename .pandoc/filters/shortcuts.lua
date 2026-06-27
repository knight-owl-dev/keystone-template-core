---@diagnostic disable: undefined-global
-- shortcuts.lua — Expand named style shortcuts into handler classes + attributes
--
-- Authors define named aliases in shortcuts.yaml. publish.sh preprocesses the
-- YAML into a Lua table file via yq; this filter loads it at module level,
-- validates all entries, pre-resolves chains, and expands matching Div/Span
-- classes during the AST walk.
--
-- Chain resolution: a shortcut can reference another shortcut (forming a chain).
-- Chains are resolved at load time so Div/Span lookups are O(1). Interfaces
-- accumulate top-down with first-writer-wins semantics.
--
-- Interface system: every shortcut declares an `interface` map that binds named
-- attributes to handler targets with optional defaults. Bind targets use the
-- `class` keyword for outer routing (class.attr → the shortcut's handler) or
-- a body div class name for body routing (figure.width → the figure div in
-- body). Inline attributes matching interface names are accepted as author
-- overrides; unrecognized inline attributes produce a warning.
--
-- Body injection: a shortcut can define a `body` property — Markdown content
-- that gets parsed via kast.read() and injected into empty Divs during
-- expansion. Body follows first-writer-wins through chains. Spans and Divs
-- with existing author content are unaffected. Interface entries with non-class
-- bind targets are forwarded as attributes on matching body divs before
-- recursive expansion. The optional `content` key names the specific body div
-- that receives author content (explicit slot); without it, the first empty
-- div is used (implicit slot). Content follows first-writer-wins through chains.
--
-- Chain bind resolution: when a chain shortcut uses `class.X`, the parent
-- must expose `X` in its interface. The bind is resolved through the parent's
-- interface at load time, so expand-time routing stays O(1).
--
-- Environment (set by publish.sh):
--   KEYSTONE_SHORTCUTS — path to the preprocessed shortcuts Lua table (always set)

local path = pandoc.path

-- Resolve filters/ directory. See docs/pandoc-integration/README.md#path-resolution.
local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end
local divs_dir = path.join({ script_dir, "divs" })

-- Install the memoized module loader, then acquire KAST. See
-- docs/pandoc-integration/kast.md.
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")

local handler_classes_lib = ks_require("handler-classes")
local ns = ks_require("handler-namespace")

-- ── Module-level init ────────────────────────────────────────────────

local shortcuts_path = os.getenv("KEYSTONE_SHORTCUTS")
if not shortcuts_path or shortcuts_path == "" then
  -- No shortcuts file — define no-op handlers and return
  function Div() end
  function Span() end
  return
end

-- Sandbox: text-only chunks ("t"), empty environment (pure data, no globals needed)
local shortcuts_chunk, shortcuts_err = loadfile(shortcuts_path, "t", {})
if not shortcuts_chunk then
  error(shortcuts_err)
end
local raw_shortcuts = shortcuts_chunk()

-- Null or empty table → no-op (null YAML produces nil via yq)
if not raw_shortcuts or not next(raw_shortcuts) then
  function Div() end
  function Span() end
  return
end

-- ── Discover handler namespace ───────────────────────────────────────

local handler_classes = handler_classes_lib.discover(
  divs_dir, pandoc.system.list_directory, path.join)

-- ── Reserved keys ────────────────────────────────────────────────────

local RESERVED_KEYS = { class = true, body = true, content = true, interface = true }

--- Split a bind target ("class.family") into its class and attribute parts.
local function split_bind(bind)
  return bind:match("^(.+)%.(.+)$")
end

-- ── Validate + resolve chains ────────────────────────────────────────

-- Every shortcut must have a string "class" attribute
for name, attrs in pairs(raw_shortcuts) do
  local cls = attrs["class"]
  if not cls then
    error("shortcuts: '" .. name .. "' is missing required 'class' attribute")
  end
  if type(cls) ~= "string" then
    error("shortcuts: '" .. name .. "' has non-string class value (" .. type(cls) .. ")")
  end
end

-- ks- prefix is reserved for handler namespacing — no shortcut may use it
for name in pairs(raw_shortcuts) do
  if ns.is_reserved(name) then
    error("shortcuts: '" .. name .. "' uses reserved 'ks-' prefix")
  end
end

-- Validate interface structure
for name, attrs in pairs(raw_shortcuts) do
  -- Reject old-format bare attributes (anything that's not class, body, or interface)
  for k in pairs(attrs) do
    if not RESERVED_KEYS[k] then
      error("shortcuts: '" .. name .. "' has unknown key '" .. k
        .. "' — migrate to interface format: move attributes into an interface map"
        .. " with bind/default entries")
    end
  end

  local iface = attrs["interface"]
  if iface ~= nil and type(iface) ~= "table" then
    error("shortcuts: '" .. name .. "' has non-table interface (" .. type(iface) .. ")")
  end
  if type(iface) == "table" then
    for iname, ientry in pairs(iface) do
      if type(iname) ~= "string" or iname == "" then
        error("shortcuts: '" .. name .. "' interface has non-string key"
          .. " — interface must be a map, not a list")
      end
      if type(ientry) ~= "table" then
        error("shortcuts: '" .. name .. "' interface entry '" .. iname
          .. "' must be a table with 'bind' key")
      end
      local bind = ientry["bind"]
      if not bind then
        error("shortcuts: '" .. name .. "' interface entry '" .. iname
          .. "' is missing required 'bind' key")
      end
      if type(bind) ~= "string" then
        error("shortcuts: '" .. name .. "' interface entry '" .. iname
          .. "' has non-string bind value")
      end
      local bind_class, bind_attr = split_bind(bind)
      if not bind_class then
        error("shortcuts: '" .. name .. "' interface entry '" .. iname
          .. "' has invalid bind format '" .. bind
          .. "' — expected 'class.attribute' or 'body-div.attribute'")
      end
      -- Non-class bind targets require a body (they route to body divs)
      if bind_class ~= "class" and not attrs["body"] then
        error("shortcuts: '" .. name .. "' interface entry '" .. iname
          .. "' binds to '" .. bind .. "' but shortcut has no body"
          .. " — use 'class." .. bind_attr
          .. "' to route to the outer handler")
      end
    end
  end
end

-- Validate content key
for name, attrs in pairs(raw_shortcuts) do
  local content = attrs["content"]
  if content ~= nil then
    if type(content) ~= "string" then
      error("shortcuts: '" .. name .. "' has non-string content value ("
        .. type(content) .. ")")
    end
    if not attrs["body"] then
      error("shortcuts: '" .. name .. "' defines content slot '" .. content
        .. "' but has no body")
    end
  end
end

-- ── Copy interface entries (deep copy bind + default) ────────────────

local function copy_interface(iface)
  local result = {}
  if iface then
    for k, v in pairs(iface) do
      result[k] = { bind = v["bind"], default = v["default"] }
    end
  end
  return result
end

-- ── Resolve shortcuts ────────────────────────────────────────────────
-- Resolve each shortcut to its terminal handler class + merged interface.
-- Walk the chain top-down; first-writer-wins for interface conflicts.

local resolved = {}

local function resolve(name, visited)
  if resolved[name] then return resolved[name] end

  visited = visited or {}
  if visited[name] then
    error("shortcuts: cycle detected involving '" .. name .. "'")
  end
  visited[name] = true

  local attrs = raw_shortcuts[name]
  local target_class = attrs["class"]
  local target_canonical = ns.canonical(target_class)
  local result_interface = copy_interface(attrs["interface"])
  local result_body = attrs["body"]
  local result_content = attrs["content"]

  if handler_classes[target_canonical] then
    -- Terminal: target is a handler class (with or without ks- prefix)
    resolved[name] = { handler_class = target_canonical, interface = result_interface, body = result_body, content = result_content }
  elseif raw_shortcuts[target_class] then
    -- Chain: target is another shortcut — resolve recursively
    local downstream = resolve(target_class, visited)

    -- Resolve class.X binds through the parent shortcut's interface.
    -- class.X means "route to wherever my class routes X" — the parent must
    -- expose X, and its bind target replaces ours.
    for iname, ientry in pairs(result_interface) do
      local bind_class, bind_attr = split_bind(ientry.bind)
      if bind_class == "class" then
        local parent_entry = downstream.interface[bind_attr]
        if not parent_entry then
          error("shortcuts: '" .. name .. "' binds to 'class." .. bind_attr
            .. "' but '" .. target_class .. "' does not expose '"
            .. bind_attr .. "' in its interface")
        end
        result_interface[iname] = {
          bind = parent_entry.bind, default = ientry.default or parent_entry.default
        }
      end
    end

    -- Merge: downstream provides base, current entries override (first-writer-wins)
    local merged = copy_interface(downstream.interface)
    for k, v in pairs(result_interface) do
      merged[k] = { bind = v.bind, default = v.default }
    end
    local merged_body = result_body or downstream.body
    local merged_content = result_content or downstream.content
    resolved[name] = { handler_class = downstream.handler_class, interface = merged, body = merged_body, content = merged_content }
  else
    error("shortcuts: '" .. name .. "' references unknown class '" .. target_class .. "'"
      .. (target_class ~= target_canonical and " (resolved: '" .. target_canonical .. "')" or ""))
  end

  return resolved[name]
end

for name in pairs(raw_shortcuts) do
  resolve(name)
end

-- ── Pandoc native fields ─────────────────────────────────────────────
-- Pandoc's Attr type splits into three fields: identifier, classes, and
-- attributes (key-value pairs). The `class` key may appear in
-- el.attributes — skip it so it doesn't trigger "unrecognized attribute"
-- warnings. (`id` and `#` both populate el.identifier, never el.attributes.)
local pandoc_native_keys = { class = true }

-- ── Interface routing helpers ────────────────────────────────────────

--- Partition element data into interface overrides and unknown keys.
--- Attributes matching interface names become overrides; the rest are unknown.
--- When the interface declares an `identifier` entry, el.identifier is
--- included (Pandoc stores it as a native field, not an attribute).
---@param el table               Element (attributes + identifier)
---@param interface table        Resolved interface map
---@return table, string[]       overrides map, sorted unknown key list
local function classify_inline_attrs(el, interface)
  local overrides = {}
  local unknown = {}
  for k, v in pairs(el.attributes) do
    if not pandoc_native_keys[k] then
      if interface[k] then
        overrides[k] = v
      else
        unknown[#unknown + 1] = k
      end
    end
  end
  if interface["identifier"] and el.identifier ~= "" then
    overrides["identifier"] = el.identifier
    el.identifier = ""
  end
  table.sort(unknown)
  return overrides, unknown
end

--- Route interface entries to outer attributes and body routing targets.
--- Entries with bind target `class.X` route to the outer handler element.
--- All other bind targets route to matching body divs. Bind targets ending
--- in `.identifier` set the Pandoc-native identifier field on the target
--- element, tracked separately from key-value attributes.
---@param interface table    Resolved interface map
---@param overrides table    Inline override values keyed by interface name
---@return table outer_attrs  Handler attributes for the outer element
---@return table body_routing Attributes for body divs: { class = { attr = val } }
---@return string|nil outer_id Identifier for the outer element (class.identifier)
---@return table body_ids     Identifiers for body divs: { class = identifier }
local function route_interface(interface, overrides)
  local outer_attrs = {}
  local body_routing = {}
  local outer_id = nil
  local body_ids = {}
  for iname, ientry in pairs(interface) do
    local value = overrides[iname] or ientry.default
    if value then
      local bind_class, bind_attr = split_bind(ientry.bind)
      local is_outer = bind_class == "class"

      if bind_attr == "identifier" then
        -- Identifier routes to a dedicated field (Pandoc-native, not key-value)
        if is_outer then outer_id = value else body_ids[bind_class] = value end
      elseif is_outer then
        outer_attrs[bind_attr] = value
      else
        if not body_routing[bind_class] then body_routing[bind_class] = {} end
        body_routing[bind_class][bind_attr] = value
      end
    end
  end
  return outer_attrs, body_routing, outer_id, body_ids
end

--- Forward routed attributes and identifiers to matching divs in body blocks.
--- Bind targets already name the exact body div class (resolved at load time
--- for chains). The interface is the contract — forwarded values always win
--- over attributes baked into the body string. Identifier binds set the
--- Pandoc-native `identifier` field, not a key-value attribute.
local function forward_to_body(blocks, body_routing, body_ids)
  if not next(body_routing) and not next(body_ids) then
    return blocks
  end

  return kast.walk(blocks, {
    Div = function(d)
      -- Body divs are shortcut-authored — first class is the canonical identity
      local div_class = d.classes[1]
      if div_class then
        if body_routing[div_class] then
          for attr, val in pairs(body_routing[div_class]) do
            d.attributes[attr] = val
          end
        end
        if body_ids[div_class] then
          d.identifier = body_ids[div_class]
        end
      end
      return d
    end
  })
end

--- Fill a body slot with author content. When target_class is given, the
--- first Div whose primary class matches receives the content (explicit
--- slot). Otherwise falls back to the first empty Div (implicit slot).
---@param blocks table           Body blocks from kast.read
---@param author_content table   Author's original Div content
---@param target_class string|nil  Explicit content slot class (from `content` key)
---@return table, boolean  Updated blocks and whether a slot was found
local function slot_author_content(blocks, author_content, target_class)
  local slotted = false
  local result = kast.walk(blocks, {
    Div = function(d)
      if slotted then return d end
      if target_class then
        if d.classes[1] == target_class then
          d.content = author_content
          slotted = true
        end
      else
        if #d.content == 0 then
          d.content = author_content
          slotted = true
        end
      end
      return d
    end
  })
  return result, slotted
end

-- ── AST handlers ─────────────────────────────────────────────────────

local MAX_BODY_DEPTH = 10
local body_depth = 0

local function expand(el, is_div)
  for i, class in ipairs(el.classes) do
    local entry = resolved[class]
    if entry then
      local overrides, unknown = classify_inline_attrs(el, entry.interface)

      if #unknown > 0 then
        io.stderr:write("WARN: Shortcut '" .. class
          .. "' ignores unrecognized attributes (" .. table.concat(unknown, ", ")
          .. ").\n  These don't match any interface entry."
          .. " Check for typos or add them to the interface.\n")
      end

      local outer_attrs, body_routing, outer_id, body_ids = route_interface(
        entry.interface, overrides)

      -- Replace shortcut class with handler class
      el.classes[i] = entry.handler_class
      el.attributes = outer_attrs
      if outer_id then
        el.identifier = outer_id
      end

      -- Body handling for Divs: inject body content and expand nested shortcuts.
      -- Two modes:
      --   Empty div  → body replaces content (ornaments, fixed text)
      --   Author div → body wraps content (explicit slot or first empty div)
      if is_div and entry.body then
        local blocks = kast.read(entry.body, "markdown").blocks

        blocks = forward_to_body(blocks, body_routing, body_ids)

        if #el.content > 0 then
          local slotted
          blocks, slotted = slot_author_content(blocks, el.content, entry.content)
          if not slotted then
            if entry.content then
              error("shortcuts: '" .. class .. "' content slot targets '"
                .. entry.content .. "' but body has no div with that class")
            end
            return el
          end
        end

        -- Expand shortcuts in injected content (handles arbitrary nesting)
        if body_depth < MAX_BODY_DEPTH then
          body_depth = body_depth + 1
          blocks = kast.walk(blocks, {
            Div = function(d) return expand(d, true) end,
            Span = function(s) return expand(s, false) end,
          })
          body_depth = body_depth - 1
        else
          io.stderr:write("WARN: Maximum body nesting depth ("
            .. MAX_BODY_DEPTH .. ") exceeded while expanding shortcut '"
            .. class .. "'.\n  Check for cyclic body references"
            .. " in shortcuts.yaml.\n")
        end

        el.content = blocks
      end

      return el
    end
  end
end

function Div(el)
  return expand(el, true)
end

function Span(el)
  return expand(el, false)
end
