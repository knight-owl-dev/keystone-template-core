-- errors.lua — The single path for author- and config-facing diagnostics
--
-- Every filter and handler reports through here instead of hand-rolling
-- io.stderr:write / error(), so severity policy, message formatting, element
-- context, and process exit each have one owner.
--
--   warn(msg[, describe])   non-fatal — print, notify the sink, keep going
--   fatal(msg[, describe])  terminal — print, then exit cleanly (no traceback)
--   bind(describe)          sugar for handlers: a report bound to one element
--   on_warning(fn)          register the warnings-as-errors sink (see below)
--   exit(code)              the one wrapper over os.exit (see below)
--
-- `describe` is an OPTIONAL thunk returning an element-context table
-- ({ classes, identifier, attributes, snippet }, from kast.inspect.describe).
-- It is a thunk, not a value, so the cost of building it (a stringify walk) is
-- paid only when a diagnostic actually fires — the happy path stays free.
-- Top-level filters with no single owning element omit it.
--
-- fatal() vs raw error(): route AUTHOR- and CONFIG-facing failures through
-- fatal() — a bad attribute, an undeclared mark, an invalid metadata value —
-- so the author gets a clean message, not a Lua traceback into filter source.
-- Reserve bare error() for INTERNAL-invariant bugs, where a traceback is the
-- right tool and catchability aids tests: a handler that didn't return a table,
-- a loader cycle, a mis-invoked filter (a required env var unset). Handlers are
-- pure author-content surface — they always report(), never error()/io.stderr
-- (enforced by tests/scripts/errors-boundary.bats).
--
-- Clean fatal: error() cannot suppress Pandoc's "Error running filter …
-- stack traceback" — Pandoc's own message handler appends it regardless of
-- error()'s level. os.exit() terminates before Pandoc's pcall returns, so the
-- author sees only our message. os.exit lives here alone (enforced by
-- tests/scripts/errors-boundary.bats) so it has one testable seam.
--
-- Warnings-as-errors is cross-process: the filters run as separate Lua states,
-- so a warning counter cannot aggregate here. In strict mode publish.sh exports
-- KEYSTONE_WARNING_SINK (a file path) and this lib self-wires a sink that
-- appends every warning to it (see the bootstrap at the foot of the file);
-- publish.sh interprets the flag, checks the file post-build, and owns the
-- fail-and-don't-promote reaction. This lib owns only the append mechanism.

local env_io = ks_require("env-io")

local M = {}

-- Seam for os.exit — tests override it so a fatal raises (and is caught)
-- instead of killing the test runner.
M._exit = os.exit

-- Set by on_warning; nil until a caller opts in (no policy here by default).
local warning_sink = nil

-- Render the element-context suffix as a compact, grep-able CSS-like selector
-- plus a leading-text snippet, e.g. `  (in .vspace#intro "The night was…")`.
-- Formatting is the lib's job; the raw fields come from kast.inspect.describe.
-- Attributes are carried in the context table for other consumers but left out
-- of the line — the offending value is already named in the message.
local function render_context(ctx)
  -- Default the fields: describe() supplies them all today, but this is the
  -- error path — a future producer (e.g. #452's source positions) handing back
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

local function emit(severity, msg, describe)
  local line = severity .. ": " .. msg
  -- The error path must never fault: if the describe thunk throws or hands back
  -- a non-table, emit the message without context rather than crash and bury
  -- the diagnostic it was meant to carry.
  if describe then
    local ok, ctx = pcall(describe)
    if ok and type(ctx) == "table" then
      line = line .. render_context(ctx)
    end
  end
  io.stderr:write(line .. "\n")
end

--- Report a non-fatal problem: the build continues with a fallback.
---@param msg string             human-facing message (owns its own wording)
---@param describe function|nil  thunk → element-context table, or nil
function M.warn(msg, describe)
  emit("WARN", msg, describe)
  if warning_sink then warning_sink(msg) end
end

--- Report a terminal problem and exit cleanly, without a Lua traceback.
--- Does not return — it exits (or, under test, raises). Callers rely on this:
--- several report the error and then fall through to code that assumes the
--- rejected value was valid. Multi-line `msg` is fine (a filter may aggregate
--- many offenders into one report, then fail once here).
---@param msg string             human-facing message
---@param describe function|nil  thunk → element-context table, or nil
function M.fatal(msg, describe)
  emit("ERROR", msg, describe)
  M.exit(1)
end

--- The sole wrapper over os.exit. Everything that must end the process routes
--- through here so the exit has one owner and one test seam.
---@param code integer  process exit code
function M.exit(code)
  M._exit(code)
end

--- Register the warnings-as-errors sink. Called with each warning's message
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
--- call report.warn("…") / report.fatal("…") without repeating the context.
---@param describe function  thunk → element-context table
---@return table  { warn = fn, fatal = fn }
function M.bind(describe)
  return {
    warn = function(msg) M.warn(msg, describe) end,
    fatal = function(msg) M.fatal(msg, describe) end,
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
