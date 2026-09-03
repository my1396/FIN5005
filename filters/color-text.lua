-- Minimal color-text filter to support .blue class in LaTeX/HTML
-- HTML: wraps content in <span class="blue"> or adds inline style
-- LaTeX: wraps content in {\color{blue} ...}

local pandoc = require 'pandoc'

-- Ensure xcolor and colortbl for LaTeX
function Meta(meta)
  local header_includes = meta["header-includes"] or pandoc.List{}
  header_includes:insert(pandoc.RawBlock('latex', '\\usepackage{xcolor}'))
  header_includes:insert(pandoc.RawBlock('latex', '\\usepackage{colortbl}'))
  meta["header-includes"] = header_includes
  return meta
end

local function wrap_blue_inlines(inlines, fmt)
  if fmt:match('latex') then
    return { pandoc.RawInline('latex', '{\\color{blue} '), table.unpack(inlines), pandoc.RawInline('latex', '}') }
  else
    -- HTML and other formats
    return { pandoc.Span(inlines, {class = 'blue', style = 'color: blue;'}) }
  end
end

local function make_header_blue(header, fmt)
  if fmt:match('latex') then
    local content = {pandoc.RawInline('latex', '{\\color{blue} ')}
    for i, inline in ipairs(header.content) do
      table.insert(content, inline)
    end
    table.insert(content, pandoc.RawInline('latex', '}'))
    return pandoc.Header(header.level, content, header.attr)
  else
    return pandoc.Header(header.level, header.content, pandoc.Attr(header.identifier, {}, {style="color: blue;"}))
  end
end

local function make_table_blue(table_elem, fmt)
  if fmt:match('latex') then
    -- Use begingroup/endgroup approach for tables too
    return {
      pandoc.RawBlock('latex', '\\begingroup\\color{blue}'),
      table_elem,
      pandoc.RawBlock('latex', '\\endgroup')
    }
  else
    -- For HTML, add style to the table
    if table_elem.attr then
      local style = table_elem.attr.attributes.style or ""
      style = style .. "; color: blue;"
      table_elem.attr.attributes.style = style
    else
      table_elem.attr = pandoc.Attr("", {}, {style = "color: blue;"})
    end
    return table_elem
  end
end

local function process_blue_blocks(blocks, fmt)
  local processed = pandoc.List{}
  for _, block in ipairs(blocks) do
    if block.tag == 'Header' then
      processed:insert(make_header_blue(block, fmt))
    elseif block.tag == 'Table' then
      local blue_table = make_table_blue(block, fmt)
      if type(blue_table) == 'table' and blue_table[1] then
        -- If make_table_blue returns multiple blocks, add them all
        for _, b in ipairs(blue_table) do
          processed:insert(b)
        end
      else
        processed:insert(blue_table)
      end
    else
      processed:insert(block)
    end
  end
  return processed
end

-- Vertical space added after a block-level .blue div (a solution block) so it
-- does not butt up against the next question. Adjust the multiplier here, or
-- set the string to '' to switch the skip off.
local blue_div_skip = '\\vspace{6pt}'

local function wrap_blue_blocks(blocks, fmt)
  local processed_blocks = process_blue_blocks(blocks, fmt)
  
  if fmt:match('latex') then
    local wrapped = pandoc.List{}
    -- Use begingroup and color command which works better with paragraph breaks
    wrapped:insert(pandoc.RawBlock('latex', '\\begingroup\\color{blue}'))
    for _, b in ipairs(processed_blocks) do 
      wrapped:insert(b) 
    end
    wrapped:insert(pandoc.RawBlock('latex', '\\endgroup'))
    if blue_div_skip ~= '' then
      wrapped:insert(pandoc.RawBlock('latex', blue_div_skip))
    end
    return wrapped
  else
    return { pandoc.Div(processed_blocks, {class = 'blue', style = 'color: blue;'}) }
  end
end

function Div(div)
  local fmt = FORMAT or ''
  if div.classes:includes('blue') then
    return wrap_blue_blocks(div.content, fmt)
  end
end

function Span(span)
  local fmt = FORMAT or ''
  if span.classes:includes('blue') then
    return wrap_blue_inlines(span.content, fmt)
  end
end

function Header(el)
  local fmt = FORMAT or ''
  if el.classes:includes('blue') then
    if fmt:match('latex') then
      local content = {pandoc.RawInline('latex', '{\\color{blue} ')}
      for i, inline in ipairs(el.content) do
        table.insert(content, inline)
      end
      table.insert(content, pandoc.RawInline('latex', '}'))
      return pandoc.Header(el.level, content, el.attr)
    else
      -- HTML and other formats
      return pandoc.Header(el.level, el.content, pandoc.Attr(el.identifier, {}, {style="color: blue;"}))
    end
  end
  return el
end

function Table(el)
  local fmt = FORMAT or ''
  if el.classes:includes('blue') then
    return make_table_blue(el, fmt)
  end
  return el
end
