-- annote.lua
-- Appends the `annote` field from a .bib file as an italicized,
-- indented paragraph below each matching bibliography entry in Quarto/Pandoc.
--
-- USAGE in your .qmd YAML front matter:
--   filters:
--     - annote.lua
--
-- The filter tries multiple strategies to locate your .bib file(s):
--   1. meta.bibliography (standard Pandoc)
--   2. meta["bibliography"] (alternate key access)
--   3. Scans the working directory for any *.bib files as a fallback

local annotes = {}
local bib_parsed = false

-- ── 1. BIB PARSER ────────────────────────────────────────────────────────────

local function parse_bib(path)
  local f = io.open(path, "r")
  if not f then
    -- Try relative to working directory explicitly
    local handle = io.popen("pwd")
    local cwd = handle:read("*l")
    handle:close()
    f = io.open(cwd .. "/" .. path, "r")
    if not f then return false end
  end

  local content = f:read("*a")
  f:close()

  for entry in content:gmatch("@%w+%s*{([^@]+)") do
    local key = entry:match("^%s*([^,%s]+)")
    if not key then goto continue end

    local annote_val

    -- Brace-delimited: annote = { ... }
    local annote_start = entry:lower():find("annote%s*=%s*{")
    if annote_start then
      local brace_pos = entry:find("{", annote_start)
      if brace_pos then
        local depth = 0
        local chars = {}
        for i = brace_pos, #entry do
          local c = entry:sub(i, i)
          if c == "{" then
            depth = depth + 1
            if depth > 1 then chars[#chars+1] = c end
          elseif c == "}" then
            depth = depth - 1
            if depth == 0 then break end
            chars[#chars+1] = c
          else
            chars[#chars+1] = c
          end
        end
        annote_val = table.concat(chars)
      end
    end

    -- Quote-delimited fallback: annote = "..."
    if not annote_val then
      annote_val = entry:match('[Aa]nnote%s*=%s*"([^"]*)"')
    end

    if annote_val then
      annote_val = annote_val:gsub("%s+", " "):match("^%s*(.-)%s*$")
      if annote_val ~= "" then
        annotes[key] = annote_val
      end
    end

    ::continue::
  end
  return true
end

-- ── 2. FALLBACK: scan working directory for .bib files ───────────────────────

local function scan_for_bibs()
  local handle = io.popen("ls *.bib 2>/dev/null")
  if not handle then return end
  local result = handle:read("*a")
  handle:close()
  for bib in result:gmatch("[^\n]+") do
    parse_bib(bib)
  end
end

-- ── 3. METADATA READER ───────────────────────────────────────────────────────

local function try_parse_meta_val(val)
  if not val then return end
  local path = pandoc.utils.stringify(val)
  if path ~= "" then parse_bib(path) end
end

function Meta(meta)
  -- Strategy 1: standard meta.bibliography
  local bib = meta.bibliography or meta["bibliography"]

  if bib then
    if bib.t == "MetaList" then
      for _, item in ipairs(bib) do try_parse_meta_val(item) end
    else
      try_parse_meta_val(bib)
    end
    bib_parsed = true
  end

  -- Strategy 2: Quarto sometimes puts it under meta.document or meta.quarto
  if not bib_parsed then
    for _, key in ipairs({ "document", "quarto", "format" }) do
      if meta[key] and meta[key].bibliography then
        local b = meta[key].bibliography
        if b.t == "MetaList" then
          for _, item in ipairs(b) do try_parse_meta_val(item) end
        else
          try_parse_meta_val(b)
        end
        bib_parsed = true
        break
      end
    end
  end

  -- Strategy 3: fallback — scan working directory for any .bib files
  if not bib_parsed then
    scan_for_bibs()
  end
end

-- ── 4. BIBLIOGRAPHY PATCHER ──────────────────────────────────────────────────

function Div(div)
  if div.identifier ~= "refs" then return nil end

  -- If Meta() never found a bib, try the directory scan as last resort
  if not bib_parsed then
    scan_for_bibs()
    bib_parsed = true
  end

  local new_blocks = {}
  for _, block in ipairs(div.content) do
    table.insert(new_blocks, block)

    if block.t == "Div" then
      local key = block.identifier:match("^ref%-(.+)$")
      if key and annotes[key] then
        local indent = pandoc.Str("\u{00A0}\u{00A0}\u{00A0}\u{00A0}")
        local annotation = pandoc.Emph({ pandoc.Str(annotes[key]) })
        local annote_para = pandoc.Para({ indent, annotation })
        local annote_div = pandoc.Div(
          { annote_para },
          pandoc.Attr("", { "annote" }, {})
        )
        table.insert(new_blocks, annote_div)
      end
    end
  end

  div.content = new_blocks
  return div
end