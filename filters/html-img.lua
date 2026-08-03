-- html-img.lua
-- Convert raw HTML <img> tags to \includegraphics for LaTeX/PDF output.
-- HTML output is passed through unchanged.
--
-- Supported attributes (from the <img> tag):
--   src   -> file path for \includegraphics
--   height (inline style or attribute, e.g. "1.5em", "2em") -> [height=...]
--   width  (inline style or attribute)                       -> [width=...]
--   alt    -> used as \alt text (no-op in PDF, kept for completeness)
--
-- Vertical alignment (style="vertical-align: bottom/middle/top") is mapped to
-- a \raisebox offset so the icon sits nicely beside text:
--   bottom  ->  0em   (default, baseline-aligned)
--   middle  -> -0.25em
--   top     -> -0.5em  (approximation; depends on line height)
--
-- Usage: add "filters/html-img.lua" to the filters list in _quarto.yml

local function parse_attr(html)
  local attrs = {}
  -- extract src
  attrs.src = html:match('[Ss][Rr][Cc]%s*=%s*["\']([^"\']+)["\']')
  -- extract alt
  attrs.alt = html:match('[Aa][Ll][Tt]%s*=%s*["\']([^"\']*)["\']') or ""
  -- extract style attribute content
  local style = html:match('[Ss][Tt][Yy][Ll][Ee]%s*=%s*["\']([^"\']*)["\']') or ""
  -- height from style (e.g. height: 1.5em)
  attrs.height = style:match('[Hh]eight%s*:%s*([%d%.]+[%a%%]+)')
  -- width from style
  attrs.width  = style:match('[Ww]idth%s*:%s*([%d%.]+[%a%%]+)')
  -- fallback: height/width as direct attributes
  if not attrs.height then
    attrs.height = html:match('[Hh]eight%s*=%s*["\']([^"\']+)["\']')
  end
  if not attrs.width then
    attrs.width = html:match('[Ww]idth%s*=%s*["\']([^"\']+)["\']')
  end
  -- vertical-align from style
  attrs.valign = style:match('[Vv]ertical%-[Aa]lign%s*:%s*([%a]+)')
  return attrs
end

local function valign_to_raise(valign)
  if valign == "bottom" then return "0em"
  elseif valign == "middle" then return "-0.25em"
  elseif valign == "top"    then return "-0.5em"
  else                           return "-0.2em"  -- sensible default
  end
end

local function img_to_latex(attrs)
  if not attrs.src then return nil end

  -- build \includegraphics options
  -- if neither width nor height is specified, default to 80% of text width
  local opts = {}
  if attrs.height then
    table.insert(opts, "height=" .. attrs.height)
  end
  if attrs.width then
    table.insert(opts, "width=" .. attrs.width)
  end
  if not attrs.height and not attrs.width then
    table.insert(opts, "width=1.0\\textwidth")
  end
  local opt_str = "[" .. table.concat(opts, ",") .. "]"

  local raise = valign_to_raise(attrs.valign)
  local tex

  if raise ~= "0em" then
    tex = string.format(
      "\\raisebox{%s}{\\includegraphics%s{%s}}",
      raise, opt_str, attrs.src
    )
  else
    tex = string.format("\\includegraphics%s{%s}", opt_str, attrs.src)
  end
  return tex
end

function RawInline(el)
  -- Only act on raw HTML when producing LaTeX
  if el.format ~= "html" then return nil end
  if not FORMAT:match("latex") then return nil end

  local html = el.text
  -- Match self-closing or open <img ...> tags
  if not html:match("^%s*<[Ii][Mm][Gg]") then return nil end

  local attrs = parse_attr(html)
  -- Swap SVG src for PNG (LaTeX cannot render SVG)
  if attrs.src and attrs.src:match("%.svg$") then
    attrs.src = attrs.src:gsub("%.svg$", ".png")
  end

  local tex = img_to_latex(attrs)
  if tex then
    return pandoc.RawInline("latex", tex)
  end
end
