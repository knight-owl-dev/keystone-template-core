-- Emit an author-declared running-header mark at a point in the document.
--
-- `[John Keats]{.set mark="poem-author"}` (or the div form) emits
-- `\InsertMark{poem-author}{John Keats}`; the running header reads it back via
-- the `{poem-author}` placeholder. This carries running content that no
-- heading tracks — a poetry anthology's current author, say — into the header.
-- The value persists until the next `.set` for that mark; empty content clears
-- it. See marks.lua for the declaration channel, page-furniture.lua for the
-- placeholder and `\NewMarkClass` wiring.
--
-- PDF-only: a mark is meaningless elsewhere and `.set` carries no prose, so
-- every non-latex format drops it.
--
-- Reads the declared set (KEYSTONE_MARKS) only to reject an undeclared `mark=`
-- — otherwise `\InsertMark` would fire against a class page-furniture never
-- created. Whether the declared names are themselves valid is its half.

local kast = ks_require("ast")
local marks = ks_require("marks")
local env_io = ks_require("env-io")

-- The declared set is stable for the whole build — resolve once at load.
local _, declared = marks.parse(env_io.optional_env("KEYSTONE_MARKS") or "")

-- Resolve the target mark. Absent (only via direct ks-set — the shortcut
-- requires it) or undeclared (a typo that would break the build) is fatal; a
-- blank mark is just an undeclared name, rejected as such.
local function mark_name(el, report)
  local name = el.attributes["mark"]
  if not name then
    report.fatal({
      problem = ".set requires a 'mark' attribute",
      see = "https://keystone.knight-owl.dev/errors/missing-required-field/",
    })
  end
  if not declared[name] then
    report.fatal({
      problem = string.format(".set mark '%s' is not declared", name),
      remedy = "Add it to marks: in pandoc.yaml.",
      see = "https://keystone.knight-owl.dev/errors/undeclared-mark/",
    })
  end
  return name
end

-- Build `\InsertMark{<mark>}{<value>}`. The value renders the element content
-- inline (a mark feeds a running head, which is inline material); kast.latex
-- escapes it. The mark name is a validated declared identifier, emitted as-is.
local function insert_mark(name, value)
  return kast.latex.command("InsertMark", { args = { name, value } })
end

-- Span: content is already inline.
local function set_span(el, report)
  local value = kast.latex.inlines(el.content)
  return { kast.RawInline("latex", insert_mark(mark_name(el, report), value)) }
end

-- Div: flatten the block content to inlines first — a `::: {.set}` body is a
-- paragraph, but the mark argument must be inline.
local function set_div(el, report)
  local value = kast.latex.inlines(kast.blocks_to_inlines(el.content))
  return { kast.RawBlock("latex", insert_mark(mark_name(el, report), value)) }
end

-- Outside PDF the mark has no effect, so drop the element — but still validate
-- `mark=`, so an undeclared mark is the same hard error in every format rather
-- than passing silently just because the author built EPUB first.
local function drop(el, report)
  mark_name(el, report)
  return kast.Remove()
end

return {
  div = { latex = set_div, default = drop },
  span = { latex = set_span, default = drop },
  required_attributes = { "mark" },
}
