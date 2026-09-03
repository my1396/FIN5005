-- Minimal emoji-to-image Pandoc Lua filter (local, engine-agnostic)
-- Maps a small set of emoji shortcodes and Unicode to local PNG assets in ./emoji/

local emoji_map = {
  -- define shortcode emojis
  -- find more commonly used shortcodes here: https://www.webfx.com/tools/emoji-cheat-sheet/
  [":grinning:"] = "1f600.png",                    -- 😀
  [":smile:"] = "1f604.png",                       -- 😄
  [":rocket:"] = "1f680.png",                      -- 🚀
  [":warning:"] = "26a0.png",                      -- ⚠
  [":bulb:"] = "1f4a1.png",                        -- 💡
  [":memo:"] = "1f4dd.png",                        -- 📝
  [":chart_with_upwards_trend:"] = "1f4c8.png",    -- 📈
  [":small_blue_diamond:"] = "1f539.png",          -- 🔹
  [":white_check_mark:"] = "2705.png",             -- ✅
  [":heart:"] = "2764.png",                        -- ❤️
  [":red_heart:"] = "2764.png",                    -- ❤️
  [":thumbsup:"] = "1f44d.png",                    -- 👍
  [":+1:"] = "1f44d.png",                          -- 👍
  [":tada:"] = "1f389.png",                        -- 🎉
  [":pushpin:"] = "1f4cc.png",                     -- 📌
  [":writing_hand:"] = "270d.png",                 -- ✍️
  [":x:"] = "274c.png",                            -- ❌
  [":cross_mark:"] = "274c.png",                   -- ❌
  [":o:"] = "2b55.png",                            -- ⭕
  [":exclamation:"] = "2757.png",                  -- ❗
  [":direct_hit:"] = "1f3af.png"                   -- 🎯
}

local unicode_map = {
  -- convert your unicode emojis to mapped images
  -- this supports direct emoji use
  ["😀"] = "1f600.png",  -- grinning face
  ["😄"] = "1f604.png",  -- smiling face with open mouth & smiling eyes
  ["🚀"] = "1f680.png",  -- rocket
  ["⚠"] = "26a0.png",   -- warning sign
  ["💡"] = "1f4a1.png",  -- light bulb
  ["📝"] = "1f4dd.png",  -- memo
  ["📈"] = "1f4c8.png",  -- chart with upwards trend
  ["🔹"] = "1f539.png",  -- small blue diamond
  ["✅"] = "2705.png",   -- white check mark
  ["❤️"] = "2764.png",   -- red heart
  ["👍"] = "1f44d.png",  -- thumbs up
  ["🎉"] = "1f389.png",  -- party popper
  ["📌"] = "1f4cc.png",  -- pushpin
  ["✍️"] = "270d.png",   -- writing hand
  ["❌"] = "274c.png",   -- cross mark
  ["🎯"] = "1f3af.png",   -- direct hit
  ["⭕"] = "2b55.png",   -- hollow red circle
  ["❗"] = "2757.png"    -- red exclamation mark
}

-- Resolve the asset directory relative to THIS filter file rather than the
-- process working directory, which is the document's own folder. Pandoc sets
-- PANDOC_SCRIPT_FILE to the path given in the YAML: "filters/emoji.lua" when
-- rendering from the project root, "../filters/emoji.lua" from _lab/ or _quiz/.
-- That prefix is also what \includegraphics needs, since LaTeX compiles in the
-- same directory.
local emoji_dir = ((PANDOC_SCRIPT_FILE or "filters/emoji.lua"):gsub("[^/\\]+$", "")) .. "emoji/"
local warned = false

local function make_img(filename, alt)
  local path = emoji_dir .. filename
  local f = io.open(path, "rb")
  if f then f:close() else
    -- If the asset is missing, fall back to plain text to keep compilation
    -- robust -- but say so once, otherwise the emoji silently stay as text.
    if not warned then
      warned = true
      io.stderr:write("[emoji.lua] asset not found: " .. path .. " (emoji left as text)\n")
    end
    return pandoc.Str(alt or "")
  end
  local attr = pandoc.Attr("", {}, {height = "1em"})
  return pandoc.Image({}, path, "", attr)
end

local function expand_text_to_inlines(text)
  -- Split text by any known emoji and build inline list
  local inlines = pandoc.List{}
  local i = 1
  local len = #text
  while i <= len do
    local matched = false
    
    -- Try longest matches first (shortcodes)
    for code, file in pairs(emoji_map) do
      local s, e = text:find(code, i, true)
      if s == i then
        if s > i then
          inlines:insert(pandoc.Str(text:sub(i, s-1)))
        end
        inlines:insert(make_img(file, code))
        i = e + 1
        matched = true
        break
      end
    end
    
    if matched then goto continue end
    
    -- Try Unicode emoji (handle multi-byte UTF-8)
    for emoji, file in pairs(unicode_map) do
      local s, e = text:find(emoji, i, true)
      if s == i then
        if s > i then
          inlines:insert(pandoc.Str(text:sub(i, s-1)))
        end
        inlines:insert(make_img(file, emoji))
        i = e + 1
        matched = true
        break
      end
    end
    
    if not matched then
      -- Accumulate run of non-emoji characters
      local j = i
      while j <= len do
        local found_emoji = false
        
        -- Check for shortcodes
        for code, _ in pairs(emoji_map) do
          if text:sub(j, j + #code - 1) == code then
            found_emoji = true
            break
          end
        end
        
        -- Check for Unicode emoji
        if not found_emoji then
          for emoji, _ in pairs(unicode_map) do
            local s, e = text:find(emoji, j, true)
            if s == j then
              found_emoji = true
              break
            end
          end
        end
        
        if found_emoji then break end
        j = j + 1
      end
      inlines:insert(pandoc.Str(text:sub(i, j - 1)))
      i = j
    end
    ::continue::
  end
  return inlines
end

function Str(el)
  local t = el.text
  -- Fast check
  local has_candidate = false
  if t:find(":", 1, true) then
    for code, _ in pairs(emoji_map) do
      if t:find(code, 1, true) then has_candidate = true; break end
    end
  end
  if not has_candidate then
    for ch, _ in pairs(unicode_map) do
      if t:find(ch, 1, true) then has_candidate = true; break end
    end
  end
  if not has_candidate then return nil end
  return expand_text_to_inlines(t)
end
