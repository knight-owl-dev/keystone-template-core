-- pagesizes.lua — The page sizes Keystone names, and the geometry options that
-- set them.
--
-- A size reaches LaTeX as a `geometry` option. Pandoc's template routes
-- `papersize` into the \documentclass list, where the standard classes resolve
-- six sizes and warn `Unused global option` on the rest — a warning a correct
-- size and a typo produce alike, and one --fail-if-warnings acts on. Through
-- geometry both class families yield the same paper and text dimensions with no
-- warning, so which sizes a strict build accepts stops depending on the target.
--
-- `option()` yields geometry's `<name>paper` spelling rather than a width and
-- height pair. `classoption: landscape` is a global option geometry also reads:
-- it swaps a named size, while an explicit paperwidth/paperheight overrides it
-- silently.
--
-- The vocabulary is geometry's, so every target shares it. KOMA also resolves
-- a7/a8/b7/c7/d4; admitting those would restore the split this module removes,
-- where a size builds on scrbook and fails on book. `geometry` takes their
-- dimensions directly.

local M = {}

-- The sizes Keystone names. geometry resolves every one, and knows others
-- besides — the JIS B series (`b5j`) among them.
local SIZES = {
  "a0", "a1", "a2", "a3", "a4", "a5", "a6",
  "b0", "b1", "b2", "b3", "b4", "b5", "b6",
  "c0", "c1", "c2", "c3", "c4", "c5", "c6",
  "ansia", "ansib", "ansic", "ansid", "ansie",
  "letter", "legal", "executive",
}

-- The size a blank `papersize` resolves to. The class's own default differs by
-- family — letter on the standard classes, A4 on KOMA — which would leave the
-- page depending on the target.
M.default = "letter"

-- The margin `geometry: auto` resolves to. geometry's default is the same
-- ratio; stating it keeps the page from moving should that default change. On a
-- two-sided class geometry splits the remainder 2:3 inner:outer — the spread
-- canon — reading the same sidedness the target declares.
M.auto_scale = "scale=0.7"

-- geometry options that set the page itself. The `<name>paper` shorthands are
-- matched separately, against the vocabulary. `layout*` is absent on purpose:
-- it sizes a nested area within the page and leaves the paper alone, so it
-- coexists with `papersize` rather than competing with it.
local PAPER_KEYS = {
  "paperwidth", "paperheight", "papersize", "paper", "papername",
  "screen",
}

local function index(list)
  local set = {}
  for _, name in ipairs(list) do set[name] = true end
  return set
end

local SIZE_SET = index(SIZES)
local PAPER_KEY_SET = index(PAPER_KEYS)

--- True when `name` is a size Keystone names.
---@param name string  a stringified `papersize` value
---@return boolean
function M.is_known(name)
  return SIZE_SET[name] == true
end

--- The geometry option that selects `name` — its `<name>paper` spelling.
--- Caller has already established the name is known.
---@param name string  a known size name
---@return string      the geometry option
function M.option(name)
  return name .. "paper"
end

--- The named sizes, for diagnostics. Declaration order, so a reader scans by
--- series.
---@return table  size name strings
function M.names()
  local names = {}
  for i, name in ipairs(SIZES) do names[i] = name end
  return names
end

--- True when a geometry option string sets the page size. Matches a bare
--- `<name>paper` shorthand and any paper key, with or without a value.
--- Whitespace around a `=` is tolerated because the author's value passes to
--- geometry as written.
---@param option string  one geometry option, already split on commas
---@return boolean
function M.is_paper_option(option)
  local name = option:match("^%s*([%w]+)%s*=") or option:match("^%s*([%w]+)%s*$")
  if not name then return false end
  name = name:lower()
  if PAPER_KEY_SET[name] then return true end
  local size = name:match("^(%w+)paper$")
  return size ~= nil and M.is_known(size)
end

--- The paper-setting options among `options`, in order. Empty when the geometry
--- speaks only about margins, where a `papersize` alongside it agrees rather
--- than competes. Takes the split list `kast.meta.items` returns, so a caller
--- that also emits those options splits once.
---@param options table  geometry option strings, from `kast.meta.items`
---@return table         the offending option strings
function M.paper_options(options)
  local found = {}
  for _, option in ipairs(options) do
    if M.is_paper_option(option) then found[#found + 1] = option end
  end
  return found
end

return M
