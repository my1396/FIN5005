--[[
  keep-tables-together.lua

  Pandoc renders markdown pipe tables as `longtable` in LaTeX, which is built to
  split across pages. This filter puts `\Needspace{n\baselineskip}` before each
  table, with `n` estimated from the table's rows and caption, so LaTeX starts a
  new page when the whole table does not fit on the current one.

  `\Needspace` (capital N), not `\needspace`: lowercase `\needspace` only marks a
  preferred break that TeX acts on once the page overflows, which is after
  longtable has set its header. longtable then repeats the header on the new
  page, so the table starts with two. `\Needspace` measures the space left and
  breaks at once, before the table begins.

  Requires `\usepackage{needspace}` in the preamble (see latex/preamble.tex).
  A table taller than a full page still splits, as it must.
]]

-- Count the rows of a table: header, all body sections, and footer
local function count_rows(tbl)
  local n = #tbl.head.rows + #tbl.foot.rows
  for _, body in ipairs(tbl.bodies) do
    n = n + #body.head + #body.body
  end
  return n
end

-- Columns get explicit widths when a source line is wider than `--columns`;
-- their cells then wrap, so rows can take more than one line
local function has_wrapping_columns(tbl)
  for _, spec in ipairs(tbl.colspecs) do
    if type(spec[2]) == "number" then
      return true
    end
  end
  return false
end

function Table(tbl)
  if not quarto.doc.is_format("latex") then
    return nil
  end
  local rows = count_rows(tbl)
  if has_wrapping_columns(tbl) then
    rows = rows * 1.5
  end
  local lines = math.ceil(rows * 1.2) + 3 -- rows, plus rules and spacing
  if #tbl.caption.long > 0 then
    lines = lines + 2
  end
  return {
    pandoc.RawBlock("latex", string.format("\\Needspace{%d\\baselineskip}", lines)),
    tbl
  }
end
