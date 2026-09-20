---@diagnostic disable: undefined-global
-- shortcuts.lua — Expand named style shortcuts into handler classes + attributes
--
-- Authors define named aliases in shortcuts.yaml. publish.sh preprocesses the
-- YAML into a Lua table file via yq; this filter loads it at module level,
-- validates all entries, pre-resolves chains, and expands matching Div/Span
-- classes during the AST walk.
--
-- Closed vocabulary: holding the full author-facing class set (shortcuts +
-- handler classes + Pandoc-native), this filter also flags any div/span class
-- that resolves to none of them — whether used in the manuscript (checked
-- during the walk) or defined in a shortcut body (checked at load) — a typo
-- that would otherwise leak into output.
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
-- overrides; unrecognized inline attributes produce a warning. An entry may be
-- `required: true` — no value and no default trips a fatal at expansion.
-- Handlers also declare `required_attributes`; the interface must guarantee each,
-- checked at load (see the alignment block below and handler-contracts.lua).
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

local script_dir = path.directory(PANDOC_SCRIPT_FILE)
if script_dir == "" then
  script_dir = path.join({ ".pandoc", "filters" })
end
local divs_dir = path.join({ script_dir, "divs" })

-- Install the memoized module loader, then acquire KAST. See
-- https://keystone.knight-owl.dev/engine/kast/
dofile(path.join({ script_dir, "lib", "loader.lua" }))(script_dir)
local kast = ks_require("ast")
local errors = ks_require("errors")

local handler_classes_lib = ks_require("handler-classes")
local handler_contracts = ks_require("handler-contracts")
local ns = ks_require("handler-namespace")
local text = ks_require("text")
local native_classes = ks_require("native-classes")
local env_io = ks_require("env-io")

-- ── Closed class vocabulary ──────────────────────────────────────────
-- Discover handler classes up front: the vocabulary check needs them even on
-- the no-shortcuts no-op path, where an author's class typo must still be
-- caught. `resolved` is populated on the active path (resolve() below) and
-- stays empty on the no-op paths; the checker closes over both tables either way.
local handler_classes = handler_classes_lib.discover(
  divs_dir, pandoc.system.list_directory, path.join)
local resolved = {}

--- Is a class part of the recognized vocabulary — a shortcut name, a handler
--- class (bare or ks-prefixed), or a Pandoc-native class?
local function is_recognized(class)
  return resolved[class]
    or handler_classes[ns.canonical(class)]
    or native_classes[class]
end

-- Suggestion pool for the closest-match hint, built once on the first miss.
local vocabulary_cache
local function vocabulary()
  if vocabulary_cache then return vocabulary_cache end
  vocabulary_cache = {}
  for name in pairs(resolved) do vocabulary_cache[#vocabulary_cache + 1] = name end
  for class in pairs(handler_classes) do vocabulary_cache[#vocabulary_cache + 1] = class end
  for class in pairs(native_classes) do vocabulary_cache[#vocabulary_cache + 1] = class end
  return vocabulary_cache
end

-- The closest known name to an unrecognized class, or nil when nothing is
-- close. Canonicalize (strip ks-) before matching so a broken private class like
-- `ks-fnt` is steered to the public name `font`, not `ks-font` — public names
-- are the stable surface. No-op for bare names.
--
-- The prose around it stays at each call site: a message assembled in a helper
-- is one the reader cannot see where it is written, and the style gate reads it
-- no better.
local function closest_class(class)
  return text.nearest(ns.canonical(class), vocabulary())
end

-- Why an unrecognized class is refused, shared by the two sites reporting it.
local NOT_A_CLASS = "It is not a handler, shortcut, or Pandoc-native class."

--- Warn on every class not in the vocabulary, naming it (with a close match
--- when one exists). Runs on the author's original classes before any shortcut
--- expansion, so a typo is reported even when a sibling class on the same
--- element resolves and is handled. Classless elements (id-only, like `{#refs}`)
--- loop zero times. `report` binds lazily on the first miss so the happy path
--- pays nothing.
local function check_vocabulary(el)
  local report
  for _, class in ipairs(el.classes) do
    if not is_recognized(class) then
      report = report or errors.bind(function() return kast.inspect.describe(el) end)
      local hint = closest_class(class)
      report.warn({
        problem = "unrecognized class '" .. class .. "'",
        because = NOT_A_CLASS,
        remedy = hint and ("Did you mean '" .. hint .. "'?") or nil,
        see = "https://keystone.knight-owl.dev/errors/unrecognized-class/",
      })
    end
  end
end

-- No-op handlers still enforce the vocabulary; they just don't expand.
local function install_check_only()
  Div = check_vocabulary
  Span = check_vocabulary
  Header = check_vocabulary
end

--- Warn on every unrecognized class in a shortcut body element, naming the
--- shortcut. A body is definition content authored in shortcuts.yaml; a typo'd
--- class there leaks into output like a manuscript typo, but the top-level walk
--- never sees it (expand()'s own recursive walk handles injected body content).
--- Reported at load (see below) rather than at expansion so it names the
--- offending shortcut and fires even for shortcuts that are never used.
local function check_body_classes(shortcut_name, el)
  for _, class in ipairs(el.classes) do
    if not is_recognized(class) then
      local hint = closest_class(class)
      errors.warn({
        problem = "shortcut '" .. shortcut_name
          .. "' body references unrecognized class '" .. class .. "'",
        because = NOT_A_CLASS,
        remedy = hint and ("Did you mean '" .. hint .. "'?") or nil,
        see = "https://keystone.knight-owl.dev/errors/unrecognized-class/",
      })
    end
  end
end

-- ── Module-level init ────────────────────────────────────────────────

local shortcuts_path = env_io.optional_env("KEYSTONE_SHORTCUTS")
if not shortcuts_path or shortcuts_path == "" then
  install_check_only()
  return
end

-- Sandbox: text-only chunks ("t"), empty environment (pure data, no globals needed)
local shortcuts_chunk, shortcuts_err = loadfile(shortcuts_path, "t", {})
if not shortcuts_chunk then
  -- Lua's own loader message, relayed rather than restated: it names the line
  -- and column, which is the part an author needs and the part Keystone cannot
  -- improve on.
  errors.fatal({
    problem = "the shortcuts table could not be loaded",
    verbatim = shortcuts_err,
  })
end
-- errors.fatal exits, so the chunk is non-nil here; the analyzer can't see
-- through the lib call the way it did the former bare error().
---@diagnostic disable-next-line: need-check-nil
local raw_shortcuts = shortcuts_chunk()

-- Null or empty table → no shortcuts to expand, but still enforce the vocabulary
-- (null YAML produces nil via yq)
if not raw_shortcuts or not next(raw_shortcuts) then
  install_check_only()
  return
end

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
    errors.fatal({
      problem = "shortcuts: '" .. name .. "' is missing required 'class' attribute",
    })
  end
  if type(cls) ~= "string" then
    errors.fatal({
      problem = "shortcuts: '" .. name .. "' has non-string class value (" .. type(cls) .. ")",
    })
  end
end

-- ks- prefix is reserved for handler namespacing — no shortcut may use it
for name in pairs(raw_shortcuts) do
  if ns.is_reserved(name) then
    errors.fatal({ problem = "shortcuts: '" .. name .. "' uses reserved 'ks-' prefix" })
  end
end

-- Validate interface structure
for name, attrs in pairs(raw_shortcuts) do
  -- Reject old-format bare attributes (anything that's not class, body, or interface)
  for k in pairs(attrs) do
    if not RESERVED_KEYS[k] then
      errors.fatal({
        problem = "shortcuts: '" .. name .. "' has unknown key '" .. k .. "'",
        remedy = "Migrate to the interface format: move attributes into an interface"
          .. " map with bind/default entries.",
      })
    end
  end

  local iface = attrs["interface"]
  if iface ~= nil and type(iface) ~= "table" then
    errors.fatal({
      problem = "shortcuts: '" .. name .. "' has non-table interface (" .. type(iface) .. ")",
    })
  end
  if type(iface) == "table" then
    for iname, ientry in pairs(iface) do
      if type(iname) ~= "string" or iname == "" then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface has a non-string key",
          because = "An interface is a map, not a list.",
        })
      end
      if type(ientry) ~= "table" then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' must be a table with 'bind' key",
        })
      end
      local bind = ientry["bind"]
      if not bind then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' is missing required 'bind' key",
        })
      end
      if type(bind) ~= "string" then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' has non-string bind value",
        })
      end
      local bind_class, bind_attr = split_bind(bind)
      if not bind_class then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' has invalid bind format '" .. bind .. "'",
          choices = { "class.attribute", "body-div.attribute" },
        })
      end
      -- Non-class bind targets require a body (they route to body divs)
      if bind_class ~= "class" and not attrs["body"] then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' binds to '" .. bind .. "' but the shortcut has no body",
          remedy = "Use 'class." .. bind_attr .. "' to route to the outer handler.",
        })
      end
      -- `required` is an optional boolean: a required field with no value and
      -- no default trips at expansion (see expand()). `required` + `default`
      -- is contradictory — the default always satisfies it, so `required` never
      -- fires — but output stays correct, so warn rather than fail (strict
      -- builds still reject it).
      local required = ientry["required"]
      if required ~= nil and type(required) ~= "boolean" then
        errors.fatal({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' has non-boolean required value (" .. type(required) .. ")",
        })
      end
      if required == true and ientry["default"] ~= nil then
        errors.warn({
          problem = "shortcuts: '" .. name .. "' interface entry '" .. iname
            .. "' sets both 'required' and 'default'",
          because = "The default satisfies it, so 'required' never fires.",
          remedy = "Keep one.",
        })
      end
    end
  end
end

-- Validate content key
for name, attrs in pairs(raw_shortcuts) do
  local content = attrs["content"]
  if content ~= nil then
    if type(content) ~= "string" then
      errors.fatal({
        problem = "shortcuts: '" .. name .. "' has non-string content value ("
          .. type(content) .. ")",
      })
    end
    if not attrs["body"] then
      errors.fatal({
        problem = "shortcuts: '" .. name .. "' defines content slot '" .. content
          .. "' but has no body",
      })
    end
  end
end

-- ── Copy interface entries (deep copy bind + default) ────────────────

local function copy_interface(iface)
  local result = {}
  if iface then
    for k, v in pairs(iface) do
      result[k] = { bind = v["bind"], default = v["default"], required = v["required"] }
    end
  end
  return result
end

-- ── Resolve shortcuts ────────────────────────────────────────────────
-- Resolve each shortcut to its terminal handler class + merged interface.
-- Walk the chain top-down; first-writer-wins for interface conflicts.
-- (`resolved` is declared with the vocabulary machinery above.)

local function resolve(name, visited)
  if resolved[name] then return resolved[name] end

  visited = visited or {}
  if visited[name] then
    errors.fatal({ problem = "shortcuts: cycle detected involving '" .. name .. "'" })
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
          errors.fatal({
            problem = "shortcuts: '" .. name .. "' binds to 'class." .. bind_attr
              .. "' but '" .. target_class .. "' does not expose '"
              .. bind_attr .. "' in its interface",
          })
        end
        -- Inherit the parent's default and required unless this entry sets its
        -- own; forwarding via class.X must not silently drop the parent's
        -- required: true (else alignment would false-fail on the forwarded attr).
        local required = ientry.required
        if required == nil then required = parent_entry.required end
        result_interface[iname] = {
          bind = parent_entry.bind,
          default = ientry.default or parent_entry.default,
          required = required,
        }
      end
    end

    -- Merge: downstream provides base, current entries override (first-writer-wins)
    local merged = copy_interface(downstream.interface)
    for k, v in pairs(result_interface) do
      merged[k] = { bind = v.bind, default = v.default, required = v.required }
    end
    local merged_body = result_body or downstream.body
    local merged_content = result_content or downstream.content
    resolved[name] = { handler_class = downstream.handler_class, interface = merged, body = merged_body, content = merged_content }
  else
    errors.fatal({
      problem = "shortcuts: '" .. name .. "' references unknown class '" .. target_class .. "'"
        .. (target_class ~= target_canonical and " (resolved: '" .. target_canonical .. "')" or ""),
    })
  end

  return resolved[name]
end

for name in pairs(raw_shortcuts) do
  resolve(name)
end

-- ── Validate handler-contract alignment ──────────────────────────────
-- Every place a handler is reached, its `required_attributes` must be
-- guaranteed. Two reach points per shortcut:
--   • its outer handler — attributes come only from the interface (bind
--     class.<attr>), so an entry with a default or required: true must exist;
--   • a bare handler class embedded in its body — a shortcut name there would
--     expand instead (covered transitively through that shortcut's own check),
--     but a bare ks-* class reaches its handler directly; its attributes come
--     from a body-routing entry (bind <bodydiv>.<attr>) or a value baked into
--     the body div.
-- Handlers assume presence; this guarantees it, for system and user shortcuts.
-- Only a bare ks-* handler used directly in the manuscript bypasses it.
-- Contracts are loaded once per handler class and memoized.
local contracts = {}
local function required_for(handler_class)
  if contracts[handler_class] == nil then
    local handler_path = path.join({ divs_dir, handler_class, "handler.lua" })
    contracts[handler_class] =
      handler_contracts.required_of(handler_contracts.load(handler_path, handler_class), handler_class)
  end
  return contracts[handler_class]
end

--- Walk a shortcut body's Div and Span elements, invoking visit(el) on each.
--- Both load-time body passes (contract alignment, vocabulary) share this.
local function walk_body(body, visit)
  kast.walk(kast.read(body, "markdown").blocks, {
    Div = function(d) visit(d) return d end,
    Span = function(s) visit(s) return s end,
  })
end

-- A body div/span whose first class is a bare handler reaches that handler
-- directly (a shortcut name would expand — covered transitively). Its required
-- attributes must be guaranteed by a body-routing entry or a baked value. Keyed
-- on the first class, as forward_to_body routes.
local function check_body_handler(shortcut_name, interface, el)
  local class = el.classes[1]
  if class and not resolved[class] and handler_classes[ns.canonical(class)] then
    local missing = handler_contracts.unmet(
      required_for(ns.canonical(class)), interface, class, el.attributes)
    if #missing > 0 then
      errors.fatal({
        problem = "shortcuts: '" .. shortcut_name .. "' body embeds handler '" .. class
          .. "' which requires " .. table.concat(missing, ", "),
        remedy = "Bake the value into the body, or add a default or 'required: true'"
          .. " to the interface entry binding '" .. class .. "." .. missing[1] .. "'",
      })
    end
  end
end

for name, entry in pairs(resolved) do
  local missing = handler_contracts.unmet(required_for(entry.handler_class), entry.interface)
  if #missing > 0 then
    errors.fatal({
      problem = "shortcuts: '" .. name .. "' routes to handler '" .. entry.handler_class
        .. "' which requires " .. table.concat(missing, ", "),
      remedy = "Add a default or 'required: true' to the interface entry binding"
        .. " 'class." .. missing[1] .. "'",
    })
  end

  if entry.body then
    walk_body(entry.body, function(el) check_body_handler(name, entry.interface, el) end)
  end
end

-- ── Validate shortcut body vocabulary ────────────────────────────────
-- Runs after resolution so the vocabulary is fully populated; each body's
-- div/span classes are checked (see check_body_classes).
for name, attrs in pairs(raw_shortcuts) do
  if attrs.body then
    walk_body(attrs.body, function(el) check_body_classes(name, el) end)
  end
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
  -- Lazily bound so the context walk runs only if this element actually
  -- triggers a diagnostic below.
  local report = errors.bind(function() return kast.inspect.describe(el) end)
  for i, class in ipairs(el.classes) do
    local entry = resolved[class]
    if entry then
      local overrides, unknown = classify_inline_attrs(el, entry.interface)

      if #unknown > 0 then
        report.warn({
          problem = "shortcut '" .. class .. "' ignores unrecognized attributes ("
            .. table.concat(unknown, ", ") .. ")",
          because = "They match no interface entry.",
          remedy = "Check for typos, or add them to the interface.",
          see = "https://keystone.knight-owl.dev/errors/unrecognized-attribute/",
        })
      end

      -- A required field with no author value and no default can't be filled —
      -- fatal, since the field is definitional (alignment at load guarantees a
      -- required entry exists for every handler-required attribute).
      local missing_required = {}
      for iname, ientry in pairs(entry.interface) do
        if ientry.required and overrides[iname] == nil and ientry.default == nil then
          missing_required[#missing_required + 1] = iname
        end
      end
      if #missing_required > 0 then
        table.sort(missing_required)
        report.fatal({
          problem = "shortcut '" .. class .. "' requires "
            .. table.concat(missing_required, ", "),
          remedy = "Set " .. (#missing_required > 1 and "them" or "it")
            .. " as an attribute.",
          see = "https://keystone.knight-owl.dev/errors/missing-required-field/",
        })
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
              report.fatal({
                problem = "shortcuts: '" .. class .. "' content slot targets '"
                  .. entry.content .. "' but body has no div with that class",
              })
            end
            return el
          end
        end

        -- Expand shortcuts in injected content (handles arbitrary nesting).
        -- Route through expand, NOT the top-level Div/Span: body classes are
        -- validated once at load (see the body-vocabulary check), and these
        -- blocks also carry author content the top-level walk already checked —
        -- routing through check_vocabulary here would double-report.
        if body_depth < MAX_BODY_DEPTH then
          body_depth = body_depth + 1
          blocks = kast.walk(blocks, {
            Div = function(d) return expand(d, true) end,
            Span = function(s) return expand(s, false) end,
          })
          body_depth = body_depth - 1
        else
          report.warn({
            problem = "maximum body nesting depth (" .. MAX_BODY_DEPTH
              .. ") exceeded while expanding shortcut '" .. class .. "'",
            remedy = "Check for cyclic body references in shortcuts.yaml.",
          })
        end

        el.content = blocks
      end

      return el
    end
  end
end

function Div(el)
  check_vocabulary(el)
  return expand(el, true)
end

function Span(el)
  check_vocabulary(el)
  return expand(el, false)
end

-- Headers aren't shortcut-expanded, but they carry classes (e.g. `.unnumbered`)
-- and route by class downstream in divs.lua, so their vocabulary is enforced
-- too. Validate only — returning nil leaves the header for divs.lua to route.
function Header(el)
  check_vocabulary(el)
end
