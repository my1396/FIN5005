-- nested-ordered-list.lua
-- A Lua filter for Quarto to create nested ordered lists with prefixed numbering
--
-- Uses a top-down Pandoc-level traversal to avoid Pandoc's bottom-up processing
-- order, which caused nested lists to be labelled as top-level lists.
-- Now with conditional `tightlist` based on a parent Div's class.

-- Forward declarations for mutual recursion
local ol_to_latex
local letter_ol_to_latex
local process_blocks

-- Helper: is this list numeric?
local function is_numeric_list(el)
  return el and el.style and (el.style == "Decimal" or el.style == "DefaultStyle")
end

-- Convert a letter-style OrderedList to raw LaTeX with explicit enumitem label,
-- so uppercase/lowercase is preserved regardless of nesting depth.
letter_ol_to_latex = function(el, depth, opts)
  opts = opts or {}
  depth = depth or 0 -- Default depth for top-level calls
  local label
  if el.style == "UpperAlpha" then
    label = "\\Alph*)"
  elseif el.style == "LowerAlpha" then
    label = "\\alph*)"
  elseif el.style == "UpperRoman" then
    label = "\\Roman*)"
  elseif el.style == "LowerRoman" then
    label = "\\roman*)"
  else
    return nil  -- Unknown style, let Pandoc handle it
  end

  local out = { pandoc.RawBlock("latex", "\\begin{enumerate}[label=" .. label .. ", leftmargin=*]") }
  if not opts.disable_tightlist then
    table.insert(out, pandoc.RawBlock("latex", "\\tightlist"))
  end

  for _, item in ipairs(el.content) do
    table.insert(out, pandoc.RawBlock("latex", "\\item"))
    for _, block in ipairs(item) do
      if block.t == "OrderedList" and is_numeric_list(block) then
        -- Numeric nested list: recurse with depth+1, resetting options
        for _, b in ipairs(ol_to_latex(block, depth + 1, nil)) do
          table.insert(out, b)
        end
      elseif block.t == "OrderedList" and not is_numeric_list(block) then
        -- Another non-numeric list, recurse, resetting options
        local letter_blocks = letter_ol_to_latex(block, depth, nil)
        if letter_blocks then
          for _, b in ipairs(letter_blocks) do
            table.insert(out, b)
          end
        else
          table.insert(out, block)
        end
      else
        table.insert(out, block)
      end
    end
  end
  out[#out + 1] = pandoc.RawBlock("latex", "\\end{enumerate}")
  return pandoc.Blocks(out)
end


-- Recursively convert a numeric OrderedList to raw LaTeX blocks.
-- depth 0 = outermost list  → label "1."  "2."  "3."
-- depth 1 = first nested    → label "3.1" "3.2"
-- depth 2 = second nested   → label "3.2.1" "3.2.2"
ol_to_latex = function(el, depth, opts)
  opts = opts or {}
  local label
  if depth == 0 then
    label = "\\arabic*., leftmargin=*, labelindent=7pt"
  elseif depth == 1 then
    label = "\\arabic{enumi}.\\arabic*"
  elseif depth == 2 then
    label = "\\arabic{enumi}.\\arabic{enumii}.\\arabic*"
  elseif depth == 3 then
    label = "\\arabic{enumi}.\\arabic{enumii}.\\arabic{enumiii}.\\arabic*"
  else
    label = "\\arabic*"
  end

  local out = { pandoc.RawBlock("latex", "\\begin{enumerate}[label=" .. label .. "]") }
  if not opts.disable_tightlist then
    table.insert(out, pandoc.RawBlock("latex", "\\tightlist"))
  end

  if el.start and el.start > 1 then
    table.insert(out, pandoc.RawBlock("latex", "\\setcounter{enumi}{" .. (el.start - 1) .. "}"))
  end

  for _, item in ipairs(el.content) do
    table.insert(out, pandoc.RawBlock("latex", "\\item"))
    for _, block in ipairs(item) do
      if block.t == "OrderedList" and is_numeric_list(block) then
        -- Numeric nested list: recurse with depth+1, resetting options
        for _, b in ipairs(ol_to_latex(block, depth + 1, nil)) do
          table.insert(out, b)
        end
      else
        -- Letter list or other block inside a processed item: convert explicitly
        if block.t == "OrderedList" and not is_numeric_list(block) then
          -- Recurse, resetting options
          local letter_blocks = letter_ol_to_latex(block, depth, nil)
          if letter_blocks then
            for _, b in ipairs(letter_blocks) do
              table.insert(out, b)
            end
          else
            table.insert(out, block)
          end
        else
          table.insert(out, block)
        end
      end
    end
  end

  table.insert(out, pandoc.RawBlock("latex", "\\end{enumerate}"))
  return out
end

-- Walk a block list top-down, converting eligible lists to raw LaTeX.
-- Recurses into Divs and BlockQuotes so lists inside callouts etc. also work.
process_blocks = function(blocks, opts)
  local out = {}
  opts = opts or {}

  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.classes:includes("parskipsection") then
      -- This is our special div. Process children with 'disable_tightlist'
      local div_opts = { disable_tightlist = true }
      block.content = pandoc.Blocks(process_blocks(block.content, div_opts))
      table.insert(out, block)
    elseif block.t == "OrderedList" and is_numeric_list(block) then
      -- Numeric list: convert entire tree (with or without nested sublists)
      for _, b in ipairs(ol_to_latex(block, 0, opts)) do
        table.insert(out, b)
      end
    elseif block.t == "OrderedList" and not is_numeric_list(block) then
      -- Top-level letter list: convert with explicit label to preserve case
      local letter_blocks = letter_ol_to_latex(block, 0, opts)
      if letter_blocks then
        for _, b in ipairs(letter_blocks) do
          table.insert(out, b)
        end
      else
        table.insert(out, block)
      end
    elseif block.t == "Div" or block.t == "BlockQuote" then
      block.content = pandoc.Blocks(process_blocks(block.content, opts))
      table.insert(out, block)
    else
      table.insert(out, block)
    end
  end
  return out
end

-- Document-level entry point (top-down, avoids bottom-up OrderedList filter issues)
function Pandoc(doc)
  if FORMAT:match("latex") or FORMAT:match("pdf") then
    doc.blocks = pandoc.Blocks(process_blocks(doc.blocks))
    return doc
  end
  return doc
end
