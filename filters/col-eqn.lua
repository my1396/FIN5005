-- Normalises \color{#RRGGBB} inside math so both output formats understand it.
--
--   LaTeX/PDF : \color[HTML]{RRGGBB}  -- xcolor supports the HTML model.
--   HTML      : \color[RGB]{r, g, b}  -- MathJax 3's `color` package supports
--                                        only the rgb, RGB, gray and named
--                                        models: it has no HTML model, and a
--                                        bare "#RRGGBB" is not a named colour,
--                                        so \color{#RRGGBB} silently fails.
--
-- Using the RGB model (rather than switching MathJax to the colorV2 extension,
-- whose \color takes a CSS colour but no [model] argument) keeps the \red and
-- \green macros in themes/mathjax.html working, as those rely on \color[RGB].

function Math(el)
  if FORMAT:match("latex") or FORMAT:match("pdf") then
    el.text = el.text:gsub("\\color{#(%x%x%x%x%x%x)}", "\\color[HTML]{%1}")
    return el
  elseif FORMAT:match("html") then
    el.text = el.text:gsub("\\color{#(%x%x)(%x%x)(%x%x)}", function(r, g, b)
      return string.format(
        "\\color[RGB]{%d, %d, %d}",
        tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
      )
    end)
    return el
  end
end
