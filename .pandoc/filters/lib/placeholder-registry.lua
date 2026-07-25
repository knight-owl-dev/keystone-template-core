-- placeholder-registry.lua — Closed enum of running-content placeholders
--
-- Authors compose running header and footer content using `{name}` token
-- syntax inside `header-text` / `footer-text` (and their parity-suffixed
-- siblings). Each placeholder name in this registry maps to one of two
-- substitution strategies:
--
--   kind = "static"   — substituted at filter time from the named
--                       metadata key. The replacement is the inline tree
--                       of `meta[<meta_key>]` (preserving any Pandoc
--                       formatting the author wrote, e.g. an italicized
--                       title remains italic when injected into the
--                       header). Resolves once at build time; does not
--                       update per page.
--
--   kind = "dynamic"  — emitted as a package-agnostic LaTeX shim macro
--                       (`\keystone*mark`). The active layout include
--                       is responsible for `\providecommand`ing each
--                       shim to whatever primitive its layout package
--                       exposes; this registry does not know or care
--                       which. The shim expands at LaTeX render time,
--                       so `{page}` and `{chapter}` update as the
--                       document paginates.
--
-- This module returns the registry table directly — no helper
-- functions, no filesystem discovery. Consumers look up entries with
-- `registry[name]` (one hash hit; `entry == nil` is the unknown-name
-- branch). The closed-enum shape is intentional: extending the built-in
-- set is a one-line edit here.
--
-- Keep in sync: when adding or removing a placeholder, also update:
--   • src/shared/pandoc.yaml      (author-facing token grammar docs)
--   • src/runtime/.pandoc/includes/page-layout-fancyhdr.tex   (dynamic shims)
--   • src/runtime/.pandoc/includes/page-layout-scrlayer.tex   (dynamic shims)
--   • docs/targets.md              (Running-content placeholders section)

local registry = {
  -- Static placeholders — substituted from metadata at filter time.
  title   = { kind = "static",  meta_key = "title" },
  author  = { kind = "static",  meta_key = "author" },
  date    = { kind = "static",  meta_key = "date" },

  -- Dynamic placeholders — emit a package-agnostic shim macro that
  -- the layout include resolves to package-appropriate primitives.
  page    = { kind = "dynamic", macro = "\\keystonepagemark" },
  chapter = { kind = "dynamic", macro = "\\keystonechaptermark" },
  section = { kind = "dynamic", macro = "\\keystonesectionmark" },
}

return registry
