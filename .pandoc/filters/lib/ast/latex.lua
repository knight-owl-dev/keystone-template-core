-- ast/latex.lua — AST → LaTeX serialization and LaTeX string helpers. Part of
-- KAST; see docs/pandoc-integration/kast.md.
--
-- Converts Pandoc AST elements to LaTeX strings via pandoc.write(). Unlike
-- meta.stringify(), this preserves inline formatting (bold, italic, links)
-- and escapes LaTeX special characters (&, %, #). All serialization trims
-- trailing whitespace from pandoc.write output. The escaping, trimming, and
-- label-safety invariants live here so no caller re-implements them.

local M = {}

--- Render inline elements (Str, Space, Emph, Strong, Link, …) as a LaTeX
--- string. Inlines are leaf-level text runs that live *inside* a paragraph —
--- they never produce paragraph breaks. Use this when you need a LaTeX
--- fragment for interpolation into a macro argument, e.g. a title, caption,
--- or ornament: `\lettrine{` .. inlines(content) .. `}`.
--- Wraps the inlines in a Plain block (not Para) so pandoc.write emits raw
--- text without \par or blank-line separators.
---@param inlines table list of Pandoc Inline elements
---@return string latex
function M.inlines(inlines)
  if not inlines or #inlines == 0 then return "" end
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "latex"):gsub("%s+$", ""))
end

--- Render block elements (Para, BulletList, CodeBlock, BlockQuote, …) as a
--- LaTeX string. Blocks are structural containers that can hold paragraphs,
--- lists, and other nested structures — pandoc.write renders them with \par
--- separators and full environment markup. Use this when you need to render
--- a div's entire body, e.g. the content inside `\begin{asidebox}…\end{asidebox}`.
---@param blocks table list of Pandoc Block elements
---@return string latex
function M.blocks(blocks)
  if not blocks or #blocks == 0 then return "" end
  return (pandoc.write(pandoc.Pandoc(blocks), "latex"):gsub("%s+$", ""))
end

--- Wrap a pre-rendered body in a LaTeX environment, emitting
--- `\begin{<name>}[<opts>]{<arg>}…` then the body then `\end{<name>}`,
--- newline-separated. The optional `[...]` group precedes the required
--- `{...}` groups, matching LaTeX's argument convention — so handlers don't
--- hand-assemble `\begin`/`\end` strings.
---
--- Unlike `inlines`/`blocks`, this is a pure string builder: `name`, `opts`,
--- and `args` are emitted VERBATIM, with no LaTeX escaping. Any of them
--- derived from user content must be escaped by the caller first (via
--- `inlines` for text, `check_label` for ids) — otherwise a stray `}` breaks
--- compilation.
---@param name string     environment name (no braces)
---@param body string     pre-rendered LaTeX body (e.g. from M.blocks)
---@param spec table|nil  { opts = string[]|nil, args = string[]|nil }
---  opts → joined with ", " inside one optional [...] group (omitted if empty)
---  args → each emitted as its own required {...} group, in order
---@return string latex
function M.env(name, body, spec)
  spec = spec or {}
  local head = "\\begin{" .. name .. "}"
  if spec.opts and #spec.opts > 0 then
    head = head .. "[" .. table.concat(spec.opts, ", ") .. "]"
  end
  if spec.args then
    for _, arg in ipairs(spec.args) do
      head = head .. "{" .. arg .. "}"
    end
  end
  return head .. "\n" .. body .. "\n\\end{" .. name .. "}"
end

--- Emit a LaTeX command invocation: `\<name>[<opts>]{<arg>}…`. This is the
--- invocation counterpart to `M.env` (which emits `\begin`/`\end`) — the two
--- cover the whole "call a LaTeX macro" surface so handlers never hand-assemble
--- `"\\" .. name .. "{" .. arg .. "}"`. With no spec it emits a bare `\name`,
--- which is the right shape for argument-less control sequences.
---
--- Like `M.env`, this is a pure string builder: `name`, `opts`, and `args` are
--- emitted VERBATIM with no LaTeX escaping. Anything derived from user content
--- must be escaped by the caller first (via `inlines` for text, `check_label`
--- for ids). A starred variant goes in `name` directly (e.g. `"vspace*"`).
---@param name string     control-sequence name, no leading backslash
---@param spec table|nil  { opts = string[]|nil, args = string[]|nil }
---  opts → joined with ", " inside one optional [...] group (omitted if empty)
---  args → each emitted as its own required {...} group, in order
---@return string latex
function M.command(name, spec)
  spec = spec or {}
  local out = "\\" .. name
  if spec.opts and #spec.opts > 0 then
    out = out .. "[" .. table.concat(spec.opts, ", ") .. "]"
  end
  if spec.args then
    for _, arg in ipairs(spec.args) do
      out = out .. "{" .. arg .. "}"
    end
  end
  return out
end

--- Define a LaTeX command: `\newcommand{\<name>}{<body>}`. The leading
--- backslash on the defined name is supplied here so call sites read as
--- "define `keystonewatermarktext` as <body>" rather than escaping braces.
---
--- Pure string builder, same contract as `M.env`/`M.command`: `body` is
--- emitted VERBATIM. Bodies derived from user content must be escaped by the
--- caller first (via `inlines`); numeric or literal bodies pass straight
--- through.
---@param name string  control-sequence name being defined, no leading backslash
---@param body string  replacement text, verbatim
---@return string latex
function M.newcommand(name, body)
  return "\\newcommand{\\" .. name .. "}{" .. body .. "}"
end

--- Emit `\input{<path>}` to pull in a `.tex` include. Unlike `command`/`env`,
--- the argument is always a file path, so this escapes it via `escape_path`
--- (handling # and %) rather than deferring to the caller — there is no other
--- valid escaping for an input path. This is the established
--- "Lua composes values → a neutral .tex consumes them" seam.
---@param path string  path to the .tex file, relative to the build root
---@return string latex
function M.input(path)
  return "\\input{" .. M.escape_path(path) .. "}"
end

--- Escape a file path for LaTeX commands like \includegraphics{}.
--- # and % break LaTeX tokenization; other specials are handled by grffile.
---@param p string file path
---@return string escaped
function M.escape_path(p)
  return (p:gsub("%%", "\\%%"):gsub("#", "\\#"))
end

--- Validate a string for use inside \label{} and \ref{}.
--- LaTeX labels break on special characters (&, %, #, $, {, }, ~, ^, \)
--- because the tokenizer interprets them before \label sees the text.
--- Safe characters: letters, digits, hyphen, colon, dot, underscore —
--- covering Pandoc's auto-generated IDs and common manual patterns
--- like fig:example or sec.intro.
--- Returns true on success, or nil + a diagnostic message listing the
--- offending characters (Lua error convention).
---@param s string  candidate label text
---@return boolean|nil ok   true if safe, nil if not
---@return string|nil   err  diagnostic message when invalid
function M.check_label(s)
  if s:match("^[%w_%.%:%-]+$") then return true end
  local bad = {}
  local seen = {}
  for ch in s:gmatch("[^%w_%.%:%-]") do
    if not seen[ch] then
      seen[ch] = true
      bad[#bad + 1] = ch
    end
  end
  return nil, "id '" .. s .. "' contains characters unsafe for \\label"
    .. " (only letters, digits, - : . _ allowed) — found: " .. table.concat(bad, " ")
end

-- Digits are spelled out rather than dropped, so a digit-bearing key stays
-- readable in the derived command.
local DIGIT_WORDS = {
  ["0"] = "zero", ["1"] = "one", ["2"] = "two", ["3"] = "three", ["4"] = "four",
  ["5"] = "five", ["6"] = "six", ["7"] = "seven", ["8"] = "eight", ["9"] = "nine",
}

--- Reduce an arbitrary string to a valid LaTeX control-word body (letters only).
--- A control word is [A-Za-z], so digits are spelled out ("1" → "one") and every
--- other non-letter dropped. The caller prepends the backslash and any prefix.
---@param name string  arbitrary text
---@return string  letters-only control-word body
function M.control_word(name)
  return (name:gsub("%d", DIGIT_WORDS):gsub("%A", ""))
end

return M
