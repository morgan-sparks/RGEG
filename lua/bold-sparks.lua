--[[
bold-sparks.lua
Quarto/Pandoc Lua filter that bolds "Sparks, M. M." (and common
variants) wherever it appears in the bibliography.

Usage – add to your document YAML front matter:
  filters:
    - bold-sparks.lua

How it works:
  Pandoc renders the bibliography as a Div with id="refs". This filter
  walks every Str/Space/Quoted sequence inside that Div and wraps any
  run of inlines that spell out the target name in a Strong node.
]]

-- Name variants to match (all normalised to single spaces).
-- Extend this table if your .bib uses a different form.
local TARGET_NAMES = {
  "Sparks, M. M.",   -- APA family, initials with spaces
  "Sparks, M.M.",    -- no space between initials
  "Sparks, MM",      -- unlikely but defensive
  "Sparks, M. M.,", 
}

-- Build a lookup set for fast membership testing
local target_set = {}
for _, name in ipairs(TARGET_NAMES) do
  target_set[name] = true
end

---------------------------------------------------------------------------
-- Helper: flatten a list of inlines to a plain string so we can pattern-
-- match across Str/Space nodes produced by pandoc.
---------------------------------------------------------------------------
local function inlines_to_text(inlines)
  local parts = {}
  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      parts[#parts + 1] = el.text
    elseif el.t == "Space" then
      parts[#parts + 1] = " "
    elseif el.t == "Strong" or el.t == "Emph" then
      -- recurse so we don't miss names already inside formatting
      parts[#parts + 1] = inlines_to_text(el.content)
    else
      parts[#parts + 1] = "\0" -- non-text sentinel breaks matching
    end
  end
  return table.concat(parts)
end

---------------------------------------------------------------------------
-- Core: given a flat list of inlines, return a new list where every
-- occurrence of a target name is wrapped in Strong{}.
---------------------------------------------------------------------------
local function bold_name_in_inlines(inlines)
  -- Work on a character-level string, then map back to inline nodes.
  -- Strategy: rebuild the inline list token by token, accumulating a
  -- "pending" buffer of Str/Space nodes. When the buffer spells a target
  -- name, emit a Strong; otherwise flush the buffer as-is.

  local result  = pandoc.Inlines({})
  local pending = {}          -- {inline, text_contribution} pairs
  local pending_text = ""

  local function flush_pending()
    for _, p in ipairs(pending) do
      result:insert(p.inline)
    end
    pending = {}
    pending_text = ""
  end

  local function try_match()
    -- Check whether pending_text ends with any target name.
    for name, _ in pairs(target_set) do
      local start = #pending_text - #name + 1
      if start >= 1 and pending_text:sub(start) == name then
        -- Find which pending tokens make up the matched suffix.
        local suffix_len = #name
        local split_idx  = #pending       -- walk backwards
        local consumed   = 0
        while split_idx >= 1 and consumed < suffix_len do
          consumed   = consumed + #pending[split_idx].text
          split_idx  = split_idx - 1
        end
        split_idx = split_idx + 1         -- first token of the match

        -- Flush everything before the match
        for i = 1, split_idx - 1 do
          result:insert(pending[i].inline)
        end

        -- Collect the matched inlines and wrap in Strong
        local matched = pandoc.Inlines({})
        for i = split_idx, #pending do
          matched:insert(pending[i].inline)
        end
        result:insert(pandoc.Strong(matched))

        pending      = {}
        pending_text = ""
        return true
      end
    end
    return false
  end

  for _, el in ipairs(inlines) do
    local contrib = nil
    if el.t == "Str" then
      contrib = el.text
    elseif el.t == "Space" then
      contrib = " "
    end

    if contrib then
      pending[#pending + 1] = { inline = el, text = contrib }
      pending_text = pending_text .. contrib

      -- After each token, check whether we have a complete match.
      -- Flush any prefix that can no longer be part of a match.
      try_match()

      -- Prune pending_text: keep only the longest suffix that is a
      -- prefix of some target name (so we don't accumulate forever).
      local max_keep = 0
      for name, _ in pairs(target_set) do
        for len = math.min(#pending_text, #name), 1, -1 do
          if name:sub(1, len) == pending_text:sub(-len) then
            if len > max_keep then max_keep = len end
            break
          end
        end
      end

      if max_keep < #pending_text then
        -- Flush tokens that definitely won't complete a match
        local drop_chars = #pending_text - max_keep
        local dropped    = 0
        local keep_from  = 1
        for i, p in ipairs(pending) do
          if dropped < drop_chars then
            result:insert(p.inline)
            dropped   = dropped + #p.text
            keep_from = i + 1
          else
            break
          end
        end
        local new_pending = {}
        for i = keep_from, #pending do
          new_pending[#new_pending + 1] = pending[i]
        end
        pending      = new_pending
        pending_text = pending_text:sub(#pending_text - max_keep + 1)
      end
    else
      -- Non-text inline: flush pending, recurse into children if any
      flush_pending()
      if el.content then
        el.content = bold_name_in_inlines(el.content)
      end
      result:insert(el)
    end
  end

  flush_pending()
  return result
end

---------------------------------------------------------------------------
-- Filter entry point: only touch Divs that are inside the bibliography
-- (id="refs" or class contains "references").
---------------------------------------------------------------------------
local in_refs = false

function Div(div)
  if div.identifier == "refs"
    or div.classes:includes("references")
    or div.classes:includes("bibliography") then
    in_refs = true
    local result = div:walk({
      Para = function(para)
        para.content = bold_name_in_inlines(para.content)
        return para
      end,
      Plain = function(plain)
        plain.content = bold_name_in_inlines(plain.content)
        return plain
      end,
    })
    in_refs = false
    return result
  end
end
