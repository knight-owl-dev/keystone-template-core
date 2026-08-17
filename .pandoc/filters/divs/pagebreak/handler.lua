-- Inserts a page break for ::: pagebreak blocks.
-- See README.md for usage. EPUB/HTML styling loaded from style.css.

local kast = ks_require("ast")

local function latex(_el)
  return kast.RawBlock("latex", "\\clearpage")
end

local function html(_el)
  return kast.RawBlock("html", '<div class="pagebreak"></div>')
end

local function docx(_el)
  return kast.RawBlock("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
end

local function odt(_el)
  return kast.RawBlock("opendocument", '<text:p text:style-name="Pagebreak"/>')
end

return {
  div = {
    latex = latex,
    html = html,
    epub = html,
    docx = docx,
    odt = odt,
  },
}
