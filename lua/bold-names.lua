function Div(el)
  -- This targets the bibliography entries specifically
  if el.classes:includes('references') or el.classes:includes('csl-entry') then
    return pandoc.walk_block(el, {
      Str = function(s)
        -- Matches "Sparks," followed by "M.M." or "M. M."
        if s.text:find("Sparks, MM") then
          return {
            pandoc.RawInline('html', '<b>'),
            pandoc.RawInline('tex', '\\textbf{'),
            s,
            pandoc.RawInline('tex', '}'),
            pandoc.RawInline('html', '</b>')
          }
        end
      end
    })
  end
end

-- A secondary pass to catch initials if they are separate strings
function Inlines(inls)
  for i = 1, #inls - 2 do
    if inls[i].t == "Str" and inls[i].text:find("Sparks,") then
      inls[i] = pandoc.Strong(inls[i])
      -- If the initials follow in the next few elements, bold them too
      if inls[i+2] and inls[i+2].t == "Str" and inls[i+2].text:find("M%.M%.") then
        inls[i+2] = pandoc.Strong(inls[i+2])
      end
    end
  end
  return inls
end