
-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list — engine entry points
-- ═══════════════════════════════════════════════════════════════════════════
-- parsePage(bookUrl, page) — the engine's paginated API. Page 1 NEVER
--   returns nil (the v1.0.0 bug: engines without show_error propagation
--   surfaced the bare "parsePage returned non-table" error): worst case it
--   returns an empty table after show_error. Pages > 1 return nil on
--   failure — the engine stops the walk and keeps what it has; progress
--   persists and resumes.
-- getChapterList(bookUrl) — fallback for engines without parsePage. Same
--   three-layer core; drives the walk to completion in one call (bounded);
--   the final list is cid-sorted (cid == reading order, live-verified).

function parsePage(bookUrl, page)
  if page == 1 then
    local raw, tp = tocFetchPage1(bookUrl)
    if raw == nil or #raw == 0 then
      -- everything unreachable: guided error on builds that propagate
      -- show_error; an EMPTY TABLE (never nil!) everywhere else
      tocShowUnreachable()
      return { chapters = {}, totalPages = 1 }
    end
    return { chapters = finalizeToc(raw), totalPages = tp or 1 }
  end

  local raw, tp = tocFetchPageN(bookUrl, page)
  if raw == nil or #raw == 0 then return nil end -- engine stops the walk
  return { chapters = finalizeToc(raw), totalPages = tp or page }
end

function getChapterList(bookUrl)
  local p1, tp, _, mode = tocFetchPage1(bookUrl)
  if p1 == nil or #p1 == 0 then
    -- last resort: everything cached (any mode) with no site access
    local entry = tocCacheLoad(bookUrl)
    if entry then
      local all = {}
      local pnums = {}
      for p in pairs(entry.pages or {}) do pnums[#pnums + 1] = p end
      table.sort(pnums)
      for _, p in ipairs(pnums) do
        for _, ch in ipairs(entry.pages[p]) do all[#all + 1] = ch end
      end
      if #all > 0 then return finalizeToc(all) end
    end
    tocShowUnreachable()
    return {}
  end

  local chapters, seenUrl = {}, {}
  for _, ch in ipairs(p1) do
    chapters[#chapters + 1] = ch
    seenUrl[ch.url] = true
  end

  if mode == "walk" then
    -- legacy engines: drive the virtual walk to completion (bounded; each
    -- page aborts at the first failed fetch and resumes on the next call)
    local entry = tocCacheLoad(bookUrl)
    local seedUrls = tocSeedUrls(bookUrl, entry)
    for vpage = 2, 60 do -- ≤ 60 × 40 = 2400 chapters per call
      local raw = walkEnsure(bookUrl, vpage, entry, seedUrls)
      if raw == nil then break end
      entry = tocCacheLoad(bookUrl) -- pick up the saved frontier
      local added = 0
      for _, ch in ipairs(raw) do
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
          added = added + 1
        end
      end
      if added == 0 then break end
    end
  else
    -- real mode: walk the site's pages, ABORT at the first failure (when
    -- the EdgeOne challenge does not clear, each failed fetch already cost
    -- a full WebView-solver ladder — walking on would launch it per page)
    tp = tp or 1
    for p = 2, tp do
      local raw, tp2 = tocFetchPageN(bookUrl, p)
      if raw == nil then break end -- ABORT at the first failed page
      if tp2 and tp2 > tp then tp = tp2 end
      for _, ch in ipairs(raw) do
        -- cross-page dedupe: a wrong page-N URL that soft-serves page 1
        -- again must not duplicate chapters
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
        end
      end
    end
  end

  -- cid == reading order (live-verified): the final sort fixes any seed /
  -- walk interleaving and the site's swapped-adjacent quirks
  table.sort(chapters, function(x, y)
    return (cidFromUrl(x.url) or 0) < (cidFromUrl(y.url) or 0)
  end)
  return finalizeToc(chapters)
end
