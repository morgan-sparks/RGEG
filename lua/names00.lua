function Str(el)
  if el.text:match("Maitland") then
    return pandoc.Strong(el)
  end
  return el
end

return {
  { Str = Str }
} 
