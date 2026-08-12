-- native-classes.lua — Div/span/heading classes Pandoc honors on its own, with
-- no Keystone handler or shortcut, so the closed-vocabulary check must admit
-- them (see shortcuts.lua). The static analog of handler-classes for Pandoc's
-- built-in vocabulary.
--
-- Verified in Pandoc 3.9: `smallcaps`/`underline`/`ul` fold into native inlines
-- (`ul` is Pandoc's alias for underline) but keep the class on a block div;
-- `mark` survives as a Span; `unlisted` keeps a heading out of the table of
-- contents.
--
-- MANUAL LIST — Pandoc exposes no machine-readable native-class registry, so
-- this is hand-curated and revisited only reactively: when a newer Pandoc adds
-- a class an author uses, the closed-vocabulary check warns (errors under a
-- strict build) — the cue to add it here. Returns a set (class name → true),
-- like handler-classes.

local NAMES = { "smallcaps", "underline", "ul", "mark", "unlisted" }

local set = {}
for _, name in ipairs(NAMES) do
  set[name] = true
end

return set
