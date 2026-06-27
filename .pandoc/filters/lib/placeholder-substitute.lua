---@diagnostic disable: undefined-global
-- placeholder-substitute.lua — Tokenize and substitute placeholders
-- in running header/footer inline content.
--
-- Hands the tree walk to KAST's walk helper (over Pandoc's native
-- traversal — the same mechanism shortcuts.lua uses) and supplies only
-- a `Str` handler.
-- Pandoc recurses into Emph / Strong / Span / Strikeout / every
-- other inline container, reconstructs each via its own constructors,
-- and splices when the Str handler returns a list. So this filter
-- owns the substitution-specific logic — tokenizer, dispatch,
-- per-Str transform — and nothing about traversal.
--
-- The Str handler scans each text element for `{name}` / `{{` /
-- `}}` tokens via a single-pass sentinel-masked tokenizer, then
-- dispatches each token per the placeholder registry:
--
--   static  → the inline tree of `meta[entry.meta_key]` (preserving
--             any Pandoc formatting the metadata value carries)
--   dynamic → a Pandoc RawInline carrying the package-agnostic
--             `\keystone*mark` shim macro
--   unknown → stderr WARNING + literal `{name}` pass-through (so a
--             typo surfaces in the build log without breaking the
--             output)
--
-- Substitution is inline-level only — no string concatenation around
-- LaTeX primitives, no manual escape handling. Replacement inlines
-- flow through `kast.latex.inlines()` later for the LaTeX flatten,
-- which is the existing safe-LaTeX path.
--
-- AST construction, serialization-adjacent inspection, and traversal go
-- through KAST (acquired via the global ks_require, the same way handlers and
-- filters reach it). The placeholder `registry` is genuinely caller-owned —
-- a closed enum page-furniture supplies — so it is still passed in via the
-- `deps` table at call time, matching the wire-from-the-top convention.

local M = {}

local kast = ks_require("ast")

-- Sentinel chars used to mask `{{` / `}}` escapes during tokenization
-- so the find-loop's `{name}` pattern can't mis-bind to an escape's
-- leading `{`. Pandoc surfaces inline text as plain Str elements that
-- never contain control bytes, so \1 / \2 are safe to claim here. The
-- restore pass runs only on text fragments — token names are
-- alphanumeric by pattern, so they never carry sentinels.
local SENTINEL_OPEN  = "\1"
local SENTINEL_CLOSE = "\2"

-- Tokenize the input text into a list of {kind, value} fragments:
--   { kind = "text",  value = "<literal text>" }
--   { kind = "token", value = "<placeholder name>" }
-- Handles:
--   {{ → literal { (escape)
--   }} → literal } (escape)
--   {name} where name matches [A-Za-z][A-Za-z0-9_-]* → token
--   lone { or { followed by an invalid name → literal text (passes
--     through to the dispatcher, which renders it as-is)
local function tokenize(text)
  -- Stage 1: mask escapes with sentinels so the next pass can find
  -- `{name}` without disambiguating against `{{` mid-loop.
  text = text:gsub("{{", SENTINEL_OPEN):gsub("}}", SENTINEL_CLOSE)

  -- Stage 2: walk the text by token boundary. Each iteration emits
  -- any text that precedes the next `{name}` match (with sentinels
  -- restored to literal braces), then the token itself.
  local out = {}
  local cursor = 1
  while true do
    local i, j, name = text:find("{([A-Za-z][A-Za-z0-9_-]*)}", cursor)

    local stop = i and (i - 1) or #text
    if stop >= cursor then
      local chunk = text:sub(cursor, stop)
        :gsub(SENTINEL_OPEN, "{")
        :gsub(SENTINEL_CLOSE, "}")
      if chunk ~= "" then
        table.insert(out, { kind = "text", value = chunk })
      end
    end

    if not i then break end
    table.insert(out, { kind = "token", value = name })
    cursor = j + 1
  end

  return out
end

-- Dispatch a single token name to its replacement inline list.
-- Unknown names produce a stderr WARNING and a literal pass-through
-- so the author sees the typo both in the build log and the PDF.
local function dispatch_token(name, meta, deps)
  local entry = deps.registry[name]
  if entry == nil then
    io.stderr:write(string.format(
      "WARNING: unrecognized placeholder '{%s}' in running text; "
      .. "passing through as literal\n",
      name))
    return { kast.Str("{" .. name .. "}") }
  end

  if entry.kind == "static" then
    local val = meta[entry.meta_key]
    if val == nil or kast.meta.is_blank(val) then
      return {}  -- absent or blank → contribute nothing
    end
    -- MetaInlines surface as iterable tables of inline elements;
    -- MetaString surfaces as a plain Lua string. Handle both.
    if type(val) == "table" then
      local copy = {}
      for j, inl in ipairs(val) do copy[j] = inl end
      return copy
    elseif type(val) == "string" then
      return { kast.Str(val) }
    end
    return {}
  end

  -- kind == "dynamic"
  return { kast.RawInline("latex", entry.macro) }
end

-- Process one Str element's text: tokenize + dispatch + assemble.
-- Returns a list of inlines that replace the original Str.
local function process_str(text, meta, deps)
  local fragments = tokenize(text)
  local out = {}
  for _, frag in ipairs(fragments) do
    if frag.kind == "text" then
      if frag.value ~= "" then
        table.insert(out, kast.Str(frag.value))
      end
    else  -- "token"
      for _, inl in ipairs(dispatch_token(frag.value, meta, deps)) do
        table.insert(out, inl)
      end
    end
  end
  return out
end

--- Substitute placeholder tokens in an inline list.
---
--- Delegates the tree walk to KAST's `walk` (Pandoc's native traversal
--- under the hood) — the same machinery shortcuts.lua uses for its
--- Div / Span dispatch. Pandoc recurses into every inline container,
--- reconstructs each via its own constructors (preserving the protected
--- metatable the writer relies on), and splices when the Str handler
--- returns a list. We don't enumerate container types or write a
--- recursive walker; Pandoc handles every current and future inline
--- container without us tracking the schema.
---
--- Wrapping the input in a Plain block is the idiom for "walk this list
--- of inlines"; the block is unwrapped on the way out.
---
--- Nil-tolerant: a nil input passes through as nil so callers that
--- have already checked `is_blank` (and decided not to substitute)
--- can hand off whatever they hold without an extra guard.
---@param inlines table?  Pandoc inline list (MetaInlines or similar)
---@param meta table      Pandoc Meta table (for static lookups)
---@param deps table      { registry }
---@return table?         New inline list (or nil when input was nil)
function M.substitute(inlines, meta, deps)
  if inlines == nil then return inlines end
  local blocks = kast.walk({ kast.Plain(inlines) }, {
    Str = function(el)
      return process_str(el.text or "", meta, deps)
    end,
  })
  return blocks[1].content
end

return M
