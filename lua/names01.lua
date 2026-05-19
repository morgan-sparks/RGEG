function Str(el)
  -- Bold ANY appearance of "Maitland"
  if el.text:match("Maitland") then
    return pandoc.Strong(el)
  end

  -- Underline ANY appearance of "Barrus"
  if el.text:match("Barrus") then
    if FORMAT:match("latex") then
      return pandoc.RawInline('latex', '\\underline{' .. el.text .. '}')
    else
      return pandoc.RawInline('html', '<u>' .. el.text .. '</u>')
    end
  end

  return el
end

return {
  { Str = Str }
}


