
-- ═══════════════════════════════════════════════════════════════════════════
-- TAG SEARCH INDEX
-- One "id|Label|L" triple per line, auto-generated from the live
-- https://www.wuxiabox.com/browsetags/ pages (all letters, all pages) by
-- scripts/build_wuxiabox_tag_index.py. Labels are the site's own names;
-- where the site truncates to 10 chars, the build script expands to the
-- full spaced name when the prefix is unambiguous. L is the letter page
-- the tag lives on (pinyin letter for the site's Chinese tags: 报仇 → B).
-- Do not hand-edit — re-run the generator after refreshing the harvest.
--
-- Parsed once at plugin load into ALL_TAGS:
--   { id = "34", label = "Ancient China", lower = "ancient china",
--     flat = "ancientchina", letter = "A" }
--   flat = lowercased label with ALL whitespace removed — the match key
--   that makes the search space-insensitive.
-- ═══════════════════════════════════════════════════════════════════════════

local TAG_SEARCH_INDEX = [==[
-- BEGIN_TAG_INDEX (auto-generated — do not edit)
0|Placeholder|A
-- END_TAG_INDEX
]==]

local ALL_TAGS = {}
local TAGS_BY_ID = {}
do
    local seen = {}
    for line in TAG_SEARCH_INDEX:gmatch("[^\r\n]+") do
        if string.sub(line, 1, 2) ~= "--" then
            local id, label, letter = string.match(line, "^([^|]+)|([^|]+)|([^|]*)$")
            if not id then
                id, label = string.match(line, "^([^|]+)|([^|]+)$")
            end
            if id and label and not seen[id] then
                seen[id] = true
                local lower = string.lower(label)
                if not letter or letter == "" then
                    letter = string.upper(string.sub(label, 1, 1))
                end
                local tag = {
                    id     = id,
                    label  = label,
                    lower  = lower,
                    flat   = lower:gsub("%s+", ""),
                    letter = letter,
                }
                ALL_TAGS[#ALL_TAGS + 1] = tag
                TAGS_BY_ID[id] = tag
            end
        end
    end
end

-- Resolve a free-text Tag Search field into a deduplicated list of tag ids.
-- Semantics (mirrors the site's own tag browsing + the wtrlab tag search):
--   • Tokens are split on comma / semicolon; spaces stay INSIDE tokens so
--     multi-word phrases work ("weak to strong" == "weaktostrong").
--   • Per token, resolution order:
--       1. exact name match, case- AND space-insensitive ("male prot" →
--          MaleProtagonist); several site tags share a squashed name —
--          every exact match is included;
--       2. numeric token — a verbatim tag id (validated);
--       3. "keyword*" wildcard — includes ALL substring matches at once;
--       4. ANY substring match — a partial keyword INCLUDES every tag
--          containing it: the search "shows everything as a result";
--       5. multi-word token with no phrase match → per-word fallback.
--   • A token with no match at all raises a clear error.
--   • letter: ""/"all"/nil = all letters, else a single "A".."Z" — scopes
--     the whole resolution (mirrors the /browsetags/ letter grouping).
local MAX_UNION_TAGS = 12

function tagSearchResolve(text, letter)
    if not text or text == "" then return {} end
    local scopeAll = (not letter) or letter == "" or string.lower(letter) == "all"
    local scopeLetter = nil
    if not scopeAll then scopeLetter = string.upper(letter) end

    local seen, out = {}, {}

    local function scoped(t)
        return (scopeLetter == nil) or t.letter == scopeLetter
    end

    -- every tag whose flattened name contains `flatToken` (plain substring)
    local function substringMatches(flatToken)
        local matches = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and string.find(t.flat, flatToken, 1, true) then
                matches[#matches + 1] = t
            end
        end
        return matches
    end

    local function addTag(t)
        if not seen[t.id] then
            seen[t.id] = true
            out[#out + 1] = t.id
        end
    end

    local function formatMatches(matches, maxN)
        local names = {}
        for i = 1, math.min(#matches, maxN) do
            names[#names + 1] = matches[i].label .. " (#" .. matches[i].id .. ")"
        end
        local s = table.concat(names, ", ")
        if #matches > maxN then
            s = s .. ", …and " .. (#matches - maxN) .. " more"
        end
        return s
    end

    local function resolveToken(token)
        local lowerToken = string.lower(token)
        local flatToken  = lowerToken:gsub("%s+", "")

        -- 1) exact (space-insensitive) name match
        local exact = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and t.flat == flatToken then exact[#exact + 1] = t end
        end
        if #exact > 0 then
            for _, t in ipairs(exact) do addTag(t) end
            return
        end

        -- 2) verbatim numeric tag id
        if string.match(token, "^%d+$") then
            local t = TAGS_BY_ID[token]
            if t then
                if scoped(t) then addTag(t) return end
                error("tag id " .. token .. " does not start with letter " .. tostring(scopeLetter) .. ".")
            end
            error("no tag with id " .. token .. " on wuxiabox.com.")
        end

        -- 3) trailing-* wildcard: every substring match at once
        if string.sub(token, -1) == "*" then
            local stem = flatToken:sub(1, -2)
            if stem == "" then return end
            local matches = substringMatches(stem)
            if #matches == 0 then
                error("no tag name contains '" .. stem .. "'." ..
                    (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
            end
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 4) substring: INCLUDE EVERY MATCH
        local matches = substringMatches(flatToken)
        if #matches > 0 then
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 5) multi-word fallback: resolve word by word
        if string.find(token, "%s") then
            for word in token:gmatch("%S+") do resolveToken(word) end
            return
        end

        error("no tag name contains '" .. token .. "'." ..
            (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
    end

    for token in string.gmatch(text, "[^,;]+") do
        token = string.gsub(token, "^%s+", "")
        token = string.gsub(token, "%s+$", "")
        if token ~= "" then resolveToken(token) end
    end

    if #out > MAX_UNION_TAGS then
        local names = {}
        for _, id in ipairs(out) do
            names[#names + 1] = TAGS_BY_ID[id] and TAGS_BY_ID[id].label or id
        end
        error("Tag Search matched " .. #out .. " tags (" ..
            table.concat(names, ", ", 1, MAX_UNION_TAGS) .. ", …). " ..
            "wuxiabox.com browses ONE tag listing at a time, so the plugin merges " ..
            "them into " .. #out .. " parallel requests per result page — too many. " ..
            "Type a more specific keyword or an exact tag name.")
    end

    return out
end
