-- errors.lua — The single path for author- and config-facing diagnostics
--
-- Every filter and handler reports through here instead of hand-rolling
-- io.stderr:write / error(), so severity policy, message presentation, element
-- context, and process exit each have one owner.
--
--   warn(callout)     non-fatal — print, notify the sink, keep going
--   fatal(callout)    terminal — print, then exit cleanly (no traceback)
--   fatal_each(list)  several terminal problems at once, then one exit
--   check(callout)    whether a callout renders, without emitting it
--   bind(describe)    sugar for handlers: a report bound to one element
--   on_warning(fn)    register the warnings-as-errors sink (see below)
--   exit(code)        the one wrapper over os.exit (see below)
--
-- A CALLOUT TABLE names the pieces of a diagnostic; this lib assembles them.
-- Callers never write a label, a gutter, a connector, or a line break:
--
--   errors.fatal {
--     problem = "papersize '" .. size .. "' is not a page size Keystone names",
--     choices = pagesizes.names(),
--     remedy  = "For any other trim, give the dimensions to geometry instead,"
--            .. " e.g. geometry: paperwidth=5in,paperheight=5in",
--   }
--
--   problem    what went wrong — a fragment that reads on from "ERROR: ",
--              so it opens lowercase and ends in no terminator
--   offenders  the items that caused it, one per line — the caller's own
--              enumeration, so it keeps the gutter every other line has
--   verbatim   text the caller did not write: Pandoc's diagnostic, a loader's
--              message, the reason an operating system gave. Reproduced as it
--              arrived, never reflowed and never re-cased, behind a quote bar
--              that says whose words these are
--   because    the rule the problem breaks — a sentence
--   effect     the consequence the problem had: a fallback applied, an
--              input skipped, an artifact not written — a sentence
--   choices    the values that would have been accepted
--   remedy     what to do about it — a sentence
--   see        one URL worth following, on a line of its own — usually the
--              manual
--   describe   the element-context thunk (below); set by bind()
--
-- No callout can break the frame, whichever one carries the text — see
-- printable() below.
--
-- The casing each takes, and the rule that settles which of `because` and
-- `effect` a sentence belongs to, are the manual's:
-- https://keystone.knight-owl.dev/engine/diagnostics/
--
-- Every prose callout also takes a list, joined with spaces before wrapping —
-- a caller splits a long string across `..` purely for source readability and
-- the break carries no meaning. Deliberate line control belongs to `offenders`
-- and `verbatim`, which print their lines as given.
--
-- The STRING FORM — fatal("…") — is the forker-facing API: a handler receives a
-- report handle and the manual shows it called with a string. It is read as
-- `{ problem = <string> }`. That is the correct split rather than a shim to
-- retire: a callout table is first-party, where Keystone owns the prose and its
-- rules; a bare string carries prose Keystone neither owns nor polices.
--
-- `describe` is an OPTIONAL thunk returning an element-context table
-- ({ classes, identifier, attributes, snippet }, from kast.inspect.describe).
-- It is a thunk, not a value, so the cost of building it (a stringify walk) is
-- paid only when a diagnostic actually fires — the happy path stays free.
-- Top-level filters with no single owning element omit it.
--
-- Vocabulary, for every author-facing string — the diagnostics here and the
-- manual alike: what an empty or unrecognized value resolves to is a FALLBACK,
-- never "the default". "Default" names the value the shipped pandoc.yaml or
-- project.conf carries, and the two legitimately differ, so one word for both
-- leaves the author unable to check either. Internal identifiers keep the
-- engine's own naming (registry.default, fontsize.default); this governs what
-- is printed and published.
--
-- fatal() vs raw error(): route AUTHOR- and CONFIG-facing failures through
-- fatal() — a bad attribute, an undeclared mark, an invalid metadata value —
-- so the author gets a clean message, not a Lua traceback into filter source.
-- Reserve bare error() for INTERNAL-invariant bugs, where a traceback is the
-- right tool and catchability aids tests: a handler that didn't return a table,
-- a loader cycle, a mis-invoked filter (a required env var unset). A callout
-- naming a key this lib does not render, or carrying a value of the wrong
-- shape, is such a bug and raises: the piece would otherwise vanish from the
-- author's message with nothing to show for it. A callout that crossed into the
-- engine from outside is not such a bug — check() answers for one without
-- raising, so whoever sent it can be told instead. Handlers are pure
-- author-content surface — they always report(), never error()/io.stderr.
--
-- Clean fatal: error() cannot suppress Pandoc's "Error running filter …
-- stack traceback" — Pandoc's own message handler appends it regardless of
-- error()'s level. os.exit() terminates before Pandoc's pcall returns, so the
-- author sees only our message. os.exit lives here alone, so it has one
-- testable seam.
--
-- Warnings-as-errors is cross-process: the filters run as separate Lua states,
-- so a warning counter cannot aggregate here. In strict mode publish.sh exports
-- KEYSTONE_WARNING_SINK (a file path) and this lib self-wires a sink that
-- appends every warning to it (see the bootstrap at the foot of the file);
-- publish.sh interprets the flag, checks the file post-build, and owns the
-- fail-and-don't-promote reaction. This lib owns only the append mechanism.

local env_io = ks_require("env-io")
local text = ks_require("text")

local M = {}

-- Seam for os.exit — tests override it so a fatal raises (and is caught)
-- instead of killing the test runner.
M._exit = os.exit

-- Set by on_warning; nil until a caller opts in (no policy here by default).
local warning_sink = nil

-- Hard-coded rather than read from COLUMNS: rendering has to be a pure function
-- of the callouts, or the shared fixtures cannot assert the text a diagnostic
-- prints. 80 is the width every terminal is at least as wide as.
local WIDTH = 80

-- What marks a line as belonging to the diagnostic above rather than opening a
-- new one. Continuation of a wrapped prose callout sits here too, which is why
-- a callout that carries a label hangs under it instead (below) — otherwise a
-- wrapped value list and the next callout would be indistinguishable.
local GUTTER = "  "

-- Relayed text carries a quote bar, so an author can see at a glance which
-- lines are Keystone's and which belong to the tool it is reporting for. The
-- bar also gives the relayed text a left edge of its own, so a caret it carries
-- still lands under the token it marks.
local QUOTE_BAR = "│ "

-- The one word that introduces a set of ACCEPTED values, in every diagnostic
-- Keystone writes. A set the message names for another reason — the attributes
-- it ignored, the fields it wants — is not this, and rides `problem` or
-- `offenders`. It names the set rather than instructing, so it stays honest in a
-- warning that has already applied its fallback and has nothing to tell the
-- author to do.
local CHOICES_LABEL = "Valid: "

-- The callouts a caller may name, each bound to the shape it takes. One map,
-- not a name list beside a predicate list: three tables keyed alike is exactly
-- the drift this API exists to remove.
--
-- Listed rather than inferred so a typo, or a value of the wrong type, raises
-- here instead of reaching the renderer — where it would fault inside the error
-- path and bury the diagnostic it was meant to carry.
local function is_text(v) return type(v) == "string" end

local function is_text_or_list(v)
  if is_text(v) then return true end
  if type(v) ~= "table" then return false end
  -- Counted, not just walked: a map-shaped table has no array part, so ipairs
  -- would call it a list of nothing and the renderer would drop it in silence.
  local seen = 0
  for _, item in ipairs(v) do
    if not is_text(item) then return false end
    seen = seen + 1
  end
  for _ in pairs(v) do
    seen = seen - 1
  end
  return seen == 0
end

-- The shape travels with its own test, so neither can be changed alone.
local TEXT = { wants = is_text, shape = "a string" }
local TEXTS = { wants = is_text_or_list, shape = "a string or a list of strings" }
local THUNK = { wants = function(v) return type(v) == "function" end, shape = "a function" }

local CALLOUTS = {
  problem = TEXTS,
  offenders = TEXTS,
  verbatim = TEXTS,
  because = TEXTS,
  effect = TEXTS,
  choices = TEXTS,
  remedy = TEXTS,
  see = TEXT,
  describe = THUNK,
}

-- Reading order: what went wrong, which items did it, why that is a refusal,
-- what followed from it, what would have been accepted, what to do, where to
-- read more. `problem` leads on the severity line and `describe` renders as
-- context, so neither is here.
local ORDER = { "offenders", "verbatim", "because", "effect", "choices", "remedy", "see" }

-- Control characters, shown rather than acted on.
--
-- Everything a diagnostic relays — Pandoc's, a loader's, an operating system's,
-- a hook's — is text someone else wrote, and a control character in it is not
-- text. A carriage return puts what follows at column zero, over the gutter that
-- marks a line as part of this diagnostic; an escape sequence is whatever the
-- terminal makes of it. Either forges a line Keystone never wrote.
--
-- Caret notation rather than deletion: `^M` is what was there, and an author
-- chasing a tool's output needs to see it.
--
-- The frame's own business, so it sits here rather than at any boundary text
-- arrives through: what a callout HOLDS is a question about the bytes, and a
-- carriage return means the same whoever sent it. That covers the manuscript
-- too — an element-context snippet is author text, lifted out of the document
-- and interpolated into the first line.
--
-- Tab alone survives: it moves along the line and cannot leave it. A newline
-- here is not the separator — that is added after this runs, and every callout
-- carrying deliberate breaks has already been split on them. One still inside a
-- line is text pretending to be a break.
-- Caret notation offsets the C0 block into printable ASCII (NUL reads "^@",
-- ESC "^["); DEL sits above it and is spelled by convention.
local CARET_OFFSET = 64
local CARET_DEL = "?"

local function printable(line)
  return (line:gsub("[\0-\8\10-\31\127]", function(char)
    local byte = char:byte()
    if byte == 127 then return "^" .. CARET_DEL end
    return "^" .. string.char(byte + CARET_OFFSET)
  end))
end

--- True when a callout carries nothing to print. The shell renderer drops an
--- empty value in its render guards; this is where Lua does the same, so a
--- blank reaching one does not print a bare gutter in the other.
local function empty(value)
  if value == nil then return true end
  if type(value) ~= "table" then return value == "" end
  for _, item in ipairs(value) do
    if item ~= "" then return false end
  end
  return true
end

--- The text of a prose callout. A list is the caller having split one sentence
--- across source lines for readability, so it joins with spaces and wraps like
--- any other; the break carried no meaning to preserve.
local function prose(value)
  if type(value) == "table" then return table.concat(value, " ") end
  return value
end

-- Render the element-context suffix as a compact, grep-able CSS-like selector
-- plus a leading-text snippet, e.g. `  (in .vspace#intro "The night was…")`.
-- Formatting is the lib's job; the raw fields come from kast.inspect.describe.
-- Attributes are carried in the context table for other consumers but left out
-- of the line — the offending value is already named in the message.
local function render_context(ctx)
  -- Default the fields: describe() supplies them all today, but this is the
  -- error path — a future producer (source positions, say) handing back
  -- a partial table must never fault the diagnostic itself.
  local selector = {}
  for _, class in ipairs(ctx.classes or {}) do
    selector[#selector + 1] = "." .. class
  end
  if (ctx.identifier or "") ~= "" then
    selector[#selector + 1] = "#" .. ctx.identifier
  end

  local parts = {}
  if #selector > 0 then parts[#parts + 1] = table.concat(selector) end
  if (ctx.snippet or "") ~= "" then parts[#parts + 1] = '"' .. ctx.snippet .. '"' end
  if #parts == 0 then return "" end
  return " (in " .. table.concat(parts, " ") .. ")"
end

--- The lines one callout contributes, gutter and wrapping included.
local function render(key, value)
  if key == "offenders" or key == "verbatim" then
    local items = type(value) == "table" and value or { value }
    local mark = key == "verbatim" and QUOTE_BAR or ""
    local lines = {}
    for _, item in ipairs(items) do
      -- Every line, not every item: relayed text is multi-line by construction,
      -- and a line without the gutter reads as a new diagnostic rather than as
      -- part of this one. A trailing newline is where the string ended, not a
      -- line to print — a tool's captured output nearly always carries one.
      if item ~= "" then
        for line in (tostring(item):gsub("\n$", "")):gmatch("([^\n]*)") do
          lines[#lines + 1] = GUTTER .. mark .. line
        end
      end
    end
    return lines
  end

  if key == "choices" then
    local kept = {}
    if type(value) == "table" then
      -- An empty among the values would join to a leading or doubled comma.
      for _, item in ipairs(value) do
        if item ~= "" then kept[#kept + 1] = item end
      end
    end
    local values = type(value) == "table" and table.concat(kept, ", ") or value
    local hang = GUTTER .. string.rep(" ", #CHOICES_LABEL)
    return text.wrap(values, WIDTH, GUTTER .. CHOICES_LABEL, hang)
  end

  if key == "see" then
    -- A URL is one token and wrapping cannot help it; a reader copies the line.
    return { GUTTER .. "See " .. value }
  end

  return text.wrap(prose(value), WIDTH, GUTTER, GUTTER)
end

--- A validated copy of what the caller passed, with the string form read as a
--- bare problem. Copied rather than used in place so bind() can add its handle
--- without writing into a table the caller may reuse.
local function normalize(callout)
  -- The argument itself, before its keys: `report.warn(el.attributes["msg"])`
  -- with the attribute unset hands this a nil, and a traceback here buries the
  -- problem it was called about.
  if type(callout) ~= "string" and type(callout) ~= "table" then
    error("errors: a diagnostic takes a callout table or a string, got "
      .. type(callout))
  end

  local out = {}
  -- The string form is a shorthand for a problem, not a way past the checks
  -- below: a forker's `report.warn(msg)` gets the same refusal an empty table
  -- would.
  if type(callout) == "string" then
    out.problem = callout
    callout = out
  end
  for key, value in pairs(callout) do
    if not CALLOUTS[key] then
      error("errors: '" .. tostring(key) .. "' is not a callout")
    end
    -- Type as well as name. A wrong-typed value would otherwise reach the
    -- renderer and raise a Lua traceback from inside the error path, burying
    -- the author's actual problem under this lib's.
    if not CALLOUTS[key].wants(value) then
      error("errors: '" .. key .. "' takes " .. CALLOUTS[key].shape)
    end
    out[key] = value
  end
  -- Empty as well as absent: an empty problem renders a bare "ERROR:" with
  -- nothing after it, which tells the author less than no diagnostic at all.
  if out.problem == nil or text.trim(prose(out.problem)) == "" then
    error("errors: a diagnostic needs a problem")
  end
  return out
end

local function emit(severity, callout)
  local context = ""

  -- The error path must never fault: if the describe thunk throws or hands back
  -- a non-table, emit the message without context rather than crash and bury
  -- the diagnostic it was meant to carry.
  if callout.describe then
    -- render_context runs inside the pcall too: a partial context table is
    -- handled below, but a wrong-typed field would fault here otherwise — in
    -- the one place a fault buries the diagnostic it was carrying.
    local ok, rendered = pcall(function()
      local ctx = callout.describe()
      return type(ctx) == "table" and render_context(ctx) or ""
    end)
    if ok then context = rendered end
  end

  local lines = text.wrap(prose(callout.problem), WIDTH, severity .. ": ", GUTTER)

  -- The selector is one grep-able unit, so it rides the last line of the
  -- problem when it fits and takes its own otherwise. Wrapping it with the
  -- problem would split it across lines, which is the one thing it cannot
  -- survive.
  if context ~= "" then
    local tail = lines[#lines]
    if text.columns(tail) + text.columns(context) <= WIDTH then
      lines[#lines] = tail .. context
    else
      lines[#lines + 1] = GUTTER .. text.trim(context)
    end
  end

  for _, key in ipairs(ORDER) do
    if callout[key] ~= nil and not empty(callout[key]) then
      for _, line in ipairs(render(key, callout[key])) do
        lines[#lines + 1] = line
      end
    end
  end

  -- Every line the lib writes passes here, whatever callout it came from and
  -- whoever wrote the text in it.
  for index, line in ipairs(lines) do
    lines[index] = printable(line)
  end

  io.stderr:write(table.concat(lines, "\n") .. "\n")
end

--- Seam for the rendered write. Tests replace this to capture the callout a
--- caller declared without printing it — below the string form and the key and
--- type checks, so a spec still exercises the path an author's build takes and a
--- misspelled callout raises under test exactly as it would in production.
M._emit = emit

--- Report a non-fatal problem: the build continues with a fallback.
---@param callout table|string  the callout table, or a bare problem string
function M.warn(callout)
  local declared = normalize(callout)
  M._emit("WARN", declared)
  -- The sink answers "which warnings tripped", so it takes the problem alone:
  -- publish.sh bullets each line it finds, and the guidance a remedy carries is
  -- already on screen above the recap.
  --
  -- Through printable() for the same reason the rendered lines are, and one
  -- more: publish.sh reads the file back a line at a time, so a newline in a
  -- problem would become a second warning in the recap that nothing reported.
  if warning_sink then warning_sink(printable(prose(declared.problem))) end
end

--- Report a terminal problem and exit cleanly, without a Lua traceback.
--- Does not return — it exits (or, under test, raises). Callers rely on this:
--- several report the error and then fall through to code that assumes the
--- rejected value was valid.
---@param callout table|string  the callout table, or a bare problem string
function M.fatal(callout)
  M._emit("ERROR", normalize(callout))
  M.exit(1)
end

--- Report several terminal problems, then exit once.
---
--- A process exits once, so an aggregate refusal cannot be a run of fatal()
--- calls — and reporting only the first would fix a misconfigured project one
--- build at a time. Each callout renders as its own block, since one cannot be
--- folded into another.
---
--- Does not return — it exits (or, under test, raises).
---@param callouts table  a list of callout tables, at least one
function M.fatal_each(callouts)
  -- Exiting with nothing printed is the one outcome worse than any message
  -- here, and an empty list is the caller's bug rather than anything a sender
  -- did.
  if #callouts == 0 then
    error("errors: fatal_each needs at least one callout")
  end
  for _, callout in ipairs(callouts) do
    M._emit("ERROR", normalize(callout))
  end
  M.exit(1)
end

--- Whether a callout renders, answered without emitting it.
---
--- For callouts that crossed into the engine from outside — a hook's, over the
--- wire. normalize() raises on a name or a shape it does not know, which is the
--- right answer for first-party code and the wrong one for foreign input: the
--- caller has to be able to report back rather than die of what it was sent.
---
--- Asking is not reporting and then catching. fatal ends the process on a
--- callout that was fine, and warn prints one the caller may have wanted to hold
--- back — which is the whole of what this is for.
---@param callout table|string  the callout table, or a bare problem string
---@return boolean              whether this lib can render it
function M.check(callout)
  return (pcall(normalize, callout))
end

--- The sole wrapper over os.exit. Everything that must end the process routes
--- through here so the exit has one owner and one test seam.
---@param code integer  process exit code
function M.exit(code)
  M._exit(code)
end

--- Register the warnings-as-errors sink. Called with each warning's problem
--- as it is emitted. In strict mode the sink is wired automatically (see the
--- KEYSTONE_WARNING_SINK bootstrap below); this stays a no-op otherwise.
---@param fn function|nil  sink callback, or nil to clear
function M.on_warning(fn)
  warning_sink = fn
end

--- A sink that appends each warning message to a file — the cross-process
--- persistence warnings-as-errors needs. Exposed (underscored) so a spec can
--- exercise the append without reaching into the module's env bootstrap.
---@param path string  file to append warning messages to
---@return function    sink callback for on_warning
function M._file_sink(path)
  return function(msg)
    -- Best-effort: this is already the error path, so a failed open must not
    -- fault it further — the message printed to stderr regardless.
    local f = io.open(path, "a")
    if f then
      f:write(msg .. "\n")
      f:close()
    end
  end
end

--- Bind a describe thunk to a report handle for a single element, so handlers
--- call report.warn{…} / report.fatal{…} without repeating the context.
---@param describe function  thunk → element-context table
---@return table  { warn = fn, fatal = fn }
function M.bind(describe)
  local function bound(callout)
    local declared = normalize(callout)
    -- A caller naming its own describe is overriding the handle deliberately.
    if declared.describe == nil then declared.describe = describe end
    return declared
  end
  return {
    warn = function(callout) M.warn(bound(callout)) end,
    fatal = function(callout) M.fatal(bound(callout)) end,
  }
end

-- Warnings-as-errors bootstrap. publish.sh interprets the
-- KEYSTONE_WARNINGS_AS_ERRORS flag once and, in strict mode, exports
-- KEYSTONE_WARNING_SINK (a file path). Every Lua state loads this lib fresh —
-- each filter (the main pass and the EPUB pre-scan) plus the standalone
-- `pandoc lua` font-path invocation — so self-wiring here routes all their
-- warnings into the one file publish.sh checks post-build. Presence of the path
-- is the whole signal; the lib owns no policy, just this mechanism.
local sink_path = env_io.optional_env("KEYSTONE_WARNING_SINK")
if sink_path and sink_path ~= "" then
  M.on_warning(M._file_sink(sink_path))
end

return M
