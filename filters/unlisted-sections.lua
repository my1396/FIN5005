--[[
  unlisted-sections.lua
  
  This filter replaces level 2 headings under unnumbered level 1 headings with LaTeX commands.
  
  This allows:
  - Markdown headings to appear in VS Code's Outline pane for navigation
  - Automatic generation of LaTeX subsection commands with proper numbering and TOC entries
  - Correct hyperlink targets for TOC navigation
  - No duplicate headings in the PDF output
]]

-- Track if the current level 1 heading is unnumbered
local in_unnumbered_section = false

-- Helper function to convert Pandoc Inlines to plain text
local function inlines_to_string(inlines)
  return pandoc.utils.stringify(inlines)
end

return {
  {
    Header = function(el)
      -- Check if this is a level 1 heading
      if el.level == 1 then
        -- Check if it has unnumbered class or is marked with {-}
        if el.classes:includes('unnumbered') then
          in_unnumbered_section = true
        else
          in_unnumbered_section = false
        end
        return el
      -- Check if this is a level 2 heading under an unnumbered level 1
      elseif el.level == 2 and in_unnumbered_section then
        -- Extract heading text
        local heading_text = inlines_to_string(el.content)
        
        -- Extract or generate heading ID
        local heading_id = el.identifier
        if heading_id == "" then
          -- Generate ID from heading text if not provided
          heading_id = "sec-" .. heading_text:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
        end
        
        -- Generate LaTeX code
        local latex_code = string.format([[
\refstepcounter{section}
\hypertarget{%s}{}
\addcontentsline{toc}{subsection}{\protect\numberline{\thesection}%s}
\subsection*{\thesection\quad %s}
]], heading_id, heading_text, heading_text)
        
        -- Return the LaTeX as a RawBlock
        return pandoc.RawBlock('latex', latex_code)
      else
        return el
      end
    end
  }
}
