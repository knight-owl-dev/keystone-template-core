-- marks.lua — The author-declared running-header mark domain.
--
-- resolve-metadata.sh reads `marks:` from pandoc.yaml once and exports the
-- names as the newline-separated KEYSTONE_MARKS. Two Lua consumers read that
-- single channel (a dispatch-time handler can't see Meta, so the env var is
-- the shared view of the declarations), and each reaches for one half of this
-- module:
--   • the .set handler calls parse() for the membership check — is a *used*
--     mark declared?
--   • page-furniture.lua calls resolve() to fold the declarations into the
--     placeholder system and emit their \NewMarkClass preamble.
--
-- Names are single tokens (the placeholder grammar forbids whitespace), so
-- splitting on whitespace recovers the list whatever separator the export
-- used; duplicates collapse — declaring a name twice is one mark class.
--
-- KAST is acquired via the global ks_require, the same way handlers and other
-- libs reach it (see placeholder-substitute.lua). The closed placeholder
-- registry is genuinely caller-owned, so resolve() takes it as a parameter
-- rather than importing it — matching the wire-from-the-top convention.

local kast = ks_require("ast")

local lib = {}

-- Mark-name grammar — the SAME explicit ASCII grammar placeholder-substitute.lua
-- tokenizes (`[A-Za-z][A-Za-z0-9_-]*`), deliberately not Lua's locale-dependent
-- %a/%w: a name that validated here but fell outside the tokenizer's ASCII class
-- would be a declared mark that `{name}` can never reference.
local MARK_NAME = "^[A-Za-z][A-Za-z0-9_-]*$"

--- Parse the KEYSTONE_MARKS env string into an ordered list and a set.
---
--- The list preserves declaration order (page-furniture emits \NewMarkClass
--- in it — set iteration order is unspecified and would churn the preamble);
--- the set is membership for the handler's "is this mark declared?" check.
---@param str string|nil  newline/whitespace-separated names (nil/empty → empty)
---@return table list  declared names in order, duplicates removed
---@return table set   { name = true, ... } membership
function lib.parse(str)
  local list, set = {}, {}
  for name in (str or ""):gmatch("%S+") do
    if not set[name] then
      set[name] = true
      list[#list + 1] = name
    end
  end
  return list, set
end

--- Resolve declared marks into placeholder entries plus their preamble.
---
--- Each declared name becomes a dynamic placeholder whose macro is
--- `\TopMark{name}` directly — no `\keystone*mark` shim. Author marks need
--- none: `\TopMark` is a kernel primitive both layout packages read
--- identically, whereas the built-in `{chapter}`/`{section}` shims exist only
--- to paper over fancyhdr-vs-scrlayer differences in how they wrap
--- `\leftmark`/`\rightmark`. The value also renders in the author's case (no
--- `\nouppercase` dance) because the whole InsertMark→TopMark chain is ours
--- and never uppercases.
---
--- Validation lives here, not in resolve-metadata.sh, because both halves are
--- Lua-domain: the token grammar and the built-in placeholder names. The .set
--- handler owns the complementary check (is a *used* mark declared?).
---@param str string|nil   KEYSTONE_MARKS value
---@param builtins table   the closed placeholder registry (collision set + copy base)
---@return table registry  copy of builtins plus a dynamic entry per declared mark
---@return table classes   { "\NewMarkClass{name}", ... } in declaration order
function lib.resolve(str, builtins)
  local declared = lib.parse(str)

  -- Copy so the declared entries never mutate the shared registry module.
  local registry = {}
  for name, entry in pairs(builtins) do
    registry[name] = entry
  end

  local classes = {}
  for _, name in ipairs(declared) do
    if not name:match(MARK_NAME) then
      error(string.format(
        "marks: '%s' is not a valid mark name — use letters, digits, hyphen, "
        .. "and underscore, starting with a letter", name))
    end
    if builtins[name] then
      error(string.format(
        "marks: '%s' collides with the built-in {%s} placeholder — rename it",
        name, name))
    end
    registry[name] = {
      kind = "dynamic",
      macro = kast.latex.command("TopMark", { args = { name } }),
    }
    classes[#classes + 1] = kast.latex.command("NewMarkClass", { args = { name } })
  end

  return registry, classes
end

return lib
