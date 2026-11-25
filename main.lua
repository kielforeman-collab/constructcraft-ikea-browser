-- IKEA Browser plugin for ConstructCraft (Plugin API 3)
-- Data source: https://huggingface.co/datasets/T-K-233/ikea-furniture
-- No live price lookup; each imported component carries a clickable IKEA productUrl.

local M = {}

local catalog_state = nil

local function is_valid_rev(rev)
    return type(rev) == "string"
        and rev ~= ""
        and not rev:find("..", 1, true)
        and rev:match("^[a-zA-Z0-9._-]+$") ~= nil
end

local function is_valid_chunk(name)
    return type(name) == "string"
        and not name:find("..", 1, true)
        and name:match("^[a-zA-Z0-9._-]+%.json$") ~= nil
end

local function is_valid_sha256(h)
    return type(h) == "string" and #h == 64 and h:match("^[0-9a-fA-F]+$") ~= nil
end

local function sanitize_ikea_url(url)
    if type(url) ~= "string" then
        return ""
    end
    if url:match("^https://www%.ikea%.com/") or url:match("^https://www%.ikea%.cn/") then
        return url
    end
    return ""
end

local function sanitize_image_rel(image)
    if type(image) ~= "string" or image == "" then
        return ""
    end
    local rel = image:gsub("^/+", "")
    if rel:find("..", 1, true) or rel:match("^[a-zA-Z0-9._/-]+$") == nil then
        return ""
    end
    return rel
end

local function base_prefix()
    local base = (ccad.settings.base_url or "https://huggingface.co/datasets/T-K-233/ikea-furniture/resolve")
        :gsub("/+$", "")
    local rev = (ccad.settings.dataset_rev or "main"):gsub("^/+", ""):gsub("/+$", "")
    if not is_valid_rev(rev) then
        rev = "main"
    end
    return base .. "/" .. rev, rev
end

--- Format an 8-digit article number as XXX.XXX.XX.
function M.format_article(id)
    local digits = tostring(id or ""):gsub("[^0-9]", "")
    if #digits == 8 then
        return digits:sub(1, 3) .. "." .. digits:sub(4, 6) .. "." .. digits:sub(7, 8)
    end
    return tostring(id or "")
end

--- Map a T-K-233/ikea-furniture category path to ConstructCraft ComponentKind and IFC class.
function M.classify(path)
    local top = path and path[1] or ""
    local sub = path and path[2] or ""
    if top:sub(1, 2) == "li" then
        return "lighting", "IFCLIGHTFIXTURE"
    end
    if (top == "hi001" and sub == "700718") or top:sub(1, 2) == "ba" then
        return "plumbing", "IFCSANITARYTERMINAL"
    end
    if top == "st001" or top == "ka001" then
        return "casework", "IFCFURNITURE"
    end
    return "furniture", "IFCFURNITURE"
end

--- Parse a single array-encoded row from data/catalog-N.json into a structured record.
function M.parse_row(row)
    local id = type(row[1]) == "string" and row[1] or ""
    local name = type(row[2]) == "string" and row[2] or ""
    local type_name = type(row[3]) == "string" and row[3] or ""
    local path = type(row[4]) == "table" and row[4] or {}
    local variant = type(row[5]) == "string" and row[5] or ""
    local image = sanitize_image_rel(row[6])
    local bytes = tonumber(row[8]) or 0
    local hash = type(row[9]) == "string" and row[9] or ""
    local dims = type(row[10]) == "table" and row[10] or {}
    local colors = type(row[11]) == "table" and row[11] or {}
    local product_url = sanitize_ikea_url(row[12])
    local kind, ifc_class = M.classify(path)
    local w = type(dims.width) == "number" and dims.width or nil
    local d = type(dims.depth) == "number" and dims.depth or nil
    local h = type(dims.height) == "number" and dims.height or nil
    local search_blob = (name .. " " .. type_name .. " " .. variant .. " " .. id):lower()
    return {
        id = id,
        name = name,
        type_name = type_name,
        path = path,
        variant = variant,
        image = image,
        bytes = bytes,
        hash = hash,
        w = w,
        d = d,
        h = h,
        colors = colors,
        product_url = product_url,
        kind = kind,
        ifc_class = ifc_class,
        search_blob = search_blob,
    }
end

local function fetch_json_cached(url, cache_key, max_bytes)
    local limit = max_bytes or (16 * 1024 * 1024)
    local raw = ccad.http.read_cached(cache_key, { max_bytes = limit })
    if not raw then
        ccad.http.download(url, cache_key, { max_bytes = limit })
        raw = ccad.http.read_cached(cache_key, { max_bytes = limit })
    end
    if not raw then
        error("failed to read cached catalog file: " .. cache_key)
    end
    return ccad.json.decode(raw)
end

local function load_catalog()
    local prefix, rev = base_prefix()
    if catalog_state and catalog_state.prefix == prefix then
        return catalog_state
    end
    local manifest = fetch_json_cached(
        prefix .. "/data/manifest.json",
        "catalog/" .. rev .. "/manifest.json",
        4 * 1024 * 1024
    )
    -- Structure-of-Arrays (SoA) storage: avoids 36,447 hash-table allocations in Lua 5.4.
    local ids, names, types_arr, variants = {}, {}, {}, {}
    local paths, images, bytes_arr, hashes = {}, {}, {}, {}
    local ws, ds, hs, colors_arr, urls, blobs = {}, {}, {}, {}, {}, {}
    local by_id = {}
    local by_category = {}
    local by_word = {}
    local color_set = {}
    local n = 0

    local chunks = type(manifest.chunks) == "table" and manifest.chunks or {}
    for _, chunk_name in ipairs(chunks) do
        if is_valid_chunk(chunk_name) then
            local rows = fetch_json_cached(
                prefix .. "/data/" .. chunk_name,
                "catalog/" .. rev .. "/" .. chunk_name,
                16 * 1024 * 1024
            )
            if type(rows) == "table" then
                for r = 1, #rows do
                    local row = rows[r]
                    local id = type(row[1]) == "string" and row[1] or ""
                    local hash = type(row[9]) == "string" and row[9] or ""
                    if id:match("^%d%d%d%d%d%d%d%d$") and is_valid_sha256(hash) then
                        n = n + 1
                        local name = type(row[2]) == "string" and row[2] or ""
                        local type_name = type(row[3]) == "string" and row[3] or ""
                        local path = type(row[4]) == "table" and row[4] or {}
                        local variant = type(row[5]) == "string" and row[5] or ""
                        local image = sanitize_image_rel(row[6])
                        local bytes = tonumber(row[8]) or 0
                        local dims = type(row[10]) == "table" and row[10] or nil
                        local colors = type(row[11]) == "table" and row[11] or {}
                        local url = sanitize_ikea_url(row[12])
                        local blob = (name .. " " .. type_name .. " " .. variant .. " " .. id):lower()

                        ids[n] = id
                        names[n] = name
                        types_arr[n] = type_name
                        variants[n] = variant
                        paths[n] = path
                        images[n] = image
                        bytes_arr[n] = bytes
                        hashes[n] = hash
                        if dims then
                            if type(dims.width) == "number" then ws[n] = dims.width end
                            if type(dims.depth) == "number" then ds[n] = dims.depth end
                            if type(dims.height) == "number" then hs[n] = dims.height end
                        end
                        colors_arr[n] = colors
                        urls[n] = url
                        blobs[n] = blob

                        by_id[id] = n

                        local top = path[1]
                        if type(top) == "string" and top ~= "" then
                            local bucket = by_category[top]
                            if not bucket then
                                bucket = {}
                                by_category[top] = bucket
                            end
                            bucket[#bucket + 1] = n
                        end

                        for ci = 1, #colors do
                            local c = colors[ci]
                            if type(c) == "string" and c ~= "" then
                                color_set[c] = true
                            end
                        end

                        -- Inverted word index for fast full-text lookup without sacrificing recall.
                        local seen = {}
                        for word in blob:gmatch("[a-z0-9][a-z0-9][a-z0-9]+") do
                            if not seen[word] then
                                seen[word] = true
                                local list = by_word[word]
                                if not list then
                                    list = {}
                                    by_word[word] = list
                                end
                                list[#list + 1] = n
                            end
                        end
                    end
                end
            end
        end
    end

    local colors = {}
    for c in pairs(color_set) do
        colors[#colors + 1] = c
    end
    table.sort(colors)

    catalog_state = {
        prefix = prefix,
        rev = rev,
        snapshot = type(manifest.snapshot) == "string" and manifest.snapshot or "",
        categories = type(manifest.categories) == "table" and manifest.categories or {},
        colors = colors,
        n = n,
        ids = ids,
        names = names,
        types = types_arr,
        variants = variants,
        paths = paths,
        images = images,
        bytes = bytes_arr,
        hashes = hashes,
        ws = ws,
        ds = ds,
        hs = hs,
        colors_arr = colors_arr,
        urls = urls,
        blobs = blobs,
        by_id = by_id,
        by_category = by_category,
        by_word = by_word,
    }
    return catalog_state
end

local function has_segment(path, code)
    for i = 1, #path do
        if path[i] == code then
            return true
        end
    end
    return false
end

local function has_color(colors, wanted)
    for i = 1, #colors do
        if colors[i] == wanted then
            return true
        end
    end
    return false
end

function M.filter_state(st, query)
    local raw_text = type(query.text) == "string" and query.text or ""
    local text = raw_text:lower():match("^%s*(.-)%s*$")
    local has_text = text ~= ""
    local category = type(query.category) == "string" and query.category ~= "" and query.category or nil
    local color = type(query.color) == "string" and query.color ~= "" and query.color or nil
    local max_w = tonumber(query.max_width)
    local max_d = tonumber(query.max_depth)
    local max_h = tonumber(query.max_height)
    local has_dims = max_w ~= nil or max_d ~= nil or max_h ~= nil
    local offset = math.max(0, math.floor(tonumber(query.offset) or 0))
    local limit = math.min(200, math.max(1, math.floor(tonumber(query.limit) or 60)))

    -- Pick the smallest candidate index list: exact article ID, smallest word bucket, or category bucket.
    local candidates = nil
    local check_cat = category ~= nil
    if has_text and text:match("^%d%d%d%.?%d%d%d%.?%d%d$") then
        local hit = st.by_id[text:gsub("%.", "")]
        candidates = hit and { hit } or {}
        has_text = false
    else
        if category and st.by_category[category] then
            candidates = st.by_category[category]
            check_cat = false
        end
        if has_text then
            -- Use the smallest posting list for any whole >=3-char alphanumeric word in the query.
            for word in text:gmatch("[a-z0-9][a-z0-9][a-z0-9]+") do
                local list = st.by_word[word]
                if list and (not candidates or #list < #candidates) then
                    candidates = list
                    check_cat = category ~= nil
                end
            end
        end
    end

    local ids = st.ids
    local names = st.names
    local types_arr = st.types
    local variants = st.variants
    local paths = st.paths
    local images = st.images
    local bytes_arr = st.bytes
    local ws, ds, hs = st.ws, st.ds, st.hs
    local colors_arr = st.colors_arr
    local urls = st.urls
    local blobs = st.blobs

    local page = ccad.array()
    local total = 0
    local stop = offset + limit
    local sfind = string.find

    local count = candidates and #candidates or st.n
    for i = 1, count do
        local idx = candidates and candidates[i] or i
        local ok = true
        if check_cat and not has_segment(paths[idx], category) then
            ok = false
        elseif color and not has_color(colors_arr[idx], color) then
            ok = false
        elseif has_dims then
            local w, d, h = ws[idx], ds[idx], hs[idx]
            if (max_w and w and w > max_w)
                or (max_d and d and d > max_d)
                or (max_h and h and h > max_h)
            then
                ok = false
            end
        end
        if ok and has_text and sfind(blobs[idx], text, 1, true) == nil then
            ok = false
        end
        if ok then
            total = total + 1
            if total > offset and total <= stop then
                local dims = {}
                if ws[idx] then dims.width = ws[idx] end
                if ds[idx] then dims.depth = ds[idx] end
                if hs[idx] then dims.height = hs[idx] end
                local kind = M.classify(paths[idx])
                local v = variants[idx]
                local tn = types_arr[idx]
                page[#page + 1] = {
                    id = ids[idx],
                    name = names[idx],
                    subtitle = v ~= "" and (tn .. " — " .. v) or tn,
                    kind = kind,
                    article = M.format_article(ids[idx]),
                    bytes = bytes_arr[idx],
                    dimensions = dims,
                    colors = ccad.array(colors_arr[idx]),
                    url = urls[idx],
                    has_thumbnail = images[idx] ~= "",
                }
            end
        end
    end

    return { total = total, items = page }
end

local function top_categories(st)
    local cats = ccad.array()
    for _, c in ipairs(st.categories) do
        if type(c.path) == "table" and #c.path == 1 then
            cats[#cats + 1] = {
                id = c.path[1],
                name = c.name,
                count = c.count,
            }
        end
    end
    return cats
end

local function normalize_id(raw)
    return tostring(raw or ""):gsub("[^0-9]", "")
end

local function lookup_index(item_id)
    local st = load_catalog()
    local clean = normalize_id(item_id)
    local idx = st.by_id[clean] or st.by_id[tostring(item_id or "")]
    if not idx then
        error("unknown IKEA item id: " .. tostring(item_id))
    end
    return st, idx
end

local function prepare_load_args(item_id)
    local st, idx = lookup_index(item_id)
    local id = st.ids[idx]
    local hash = st.hashes[idx]
    if not is_valid_sha256(hash) then
        error("invalid model sha256 for IKEA item: " .. id)
    end
    local article = M.format_article(id)
    local name = st.names[idx]
    local type_name = st.types[idx]
    local variant = st.variants[idx]
    local url = st.urls[idx]
    local kind, ifc_class = M.classify(st.paths[idx])
    local prefix = base_prefix()
    local model_url = prefix .. "/raw/" .. id:sub(1, 2) .. "/" .. id .. "/model.glb"
    local cache_key = "models/" .. hash:sub(1, 2) .. "/" .. hash .. ".glb"
    local local_path = ccad.http.download(model_url, cache_key, {
        sha256 = hash,
        max_bytes = 64 * 1024 * 1024,
    })
    local props = {
        ArticleNumber = article,
        ProductName = name,
        TypeName = type_name,
        ModelSha256 = hash,
    }
    if variant ~= "" then props.Variant = variant end
    if url ~= "" then props.ProductUrl = url end
    if st.ws[idx] then props.CatalogWidth = st.ws[idx] end
    if st.ds[idx] then props.CatalogDepth = st.ds[idx] end
    if st.hs[idx] then props.CatalogHeight = st.hs[idx] end
    return st, idx, {
        path = local_path,
        name = name .. " " .. article,
        kind = kind,
        ifc_class = ifc_class,
        properties = { Pset_IkeaProduct = props },
    }
end

ccad.catalog {
    id = "ikea",
    load = function()
        local st = load_catalog()
        return {
            total = st.n,
            snapshot = st.snapshot,
            categories = top_categories(st),
            colors = ccad.array(st.colors),
            notice = "",
        }
    end,
    search = function(query)
        local st = load_catalog()
        return M.filter_state(st, query or {})
    end,
    thumbnail = function(item_id)
        local st = load_catalog()
        local idx = st.by_id[item_id]
        if not idx then
            return nil
        end
        local rel = st.images[idx]
        if rel == "" then
            return nil
        end
        local prefix = base_prefix()
        return ccad.http.download(prefix .. "/" .. rel, rel, { max_bytes = 2 * 1024 * 1024 })
    end,
    prepare = function(item_id)
        local _, _, load_args = prepare_load_args(item_id)
        return {
            command = "gltf_component_load",
            args = load_args,
        }
    end,
}

-- MCP & CLI commands (`ikea_browser__categories`, `ikea_browser__search`, `ikea_browser__place`)

ccad.command {
    name = "categories",
    kind = "query",
    description = "List top-level IKEA 3D furniture catalog categories with their codes and item counts.",
    params = {
        type = "object",
        properties = {},
    },
    run = function()
        local st = load_catalog()
        return {
            total = st.n,
            snapshot = st.snapshot,
            categories = top_categories(st),
        }
    end,
}

ccad.command {
    name = "search",
    kind = "query",
    description = "Search the IKEA 3D furniture catalog (36,447 models) by name, article number, category, color, or maximum dimensions in meters.",
    params = {
        type = "object",
        properties = {
            text = { type = "string", description = "Search query (product name, type, variant, or article number like 'KALLAX' or '002.758.48')." },
            category = { type = "string", description = "Top-level category code from ikea_browser__categories (e.g. 'st001', 'fu002', 'li001', 'ba001')." },
            color = { type = "string", description = "Color code filter." },
            max_width = { type = "number", description = "Maximum width in meters." },
            max_depth = { type = "number", description = "Maximum depth in meters." },
            max_height = { type = "number", description = "Maximum height in meters." },
            offset = { type = "integer", description = "Pagination offset (default 0)." },
            limit = { type = "integer", description = "Maximum items to return, 1..50 (default 20)." },
        },
    },
    run = function(args)
        local st = load_catalog()
        local q = {
            text = args.text,
            category = args.category,
            color = args.color,
            max_width = args.max_width,
            max_depth = args.max_depth,
            max_height = args.max_height,
            offset = args.offset or 0,
            limit = math.min(50, math.max(1, math.floor(tonumber(args.limit) or 20))),
        }
        return M.filter_state(st, q)
    end,
}

ccad.command {
    name = "place",
    kind = "edit",
    description = "Download (SHA-256 verified), load, and optionally place an IKEA 3D furniture model into the project with BIM category and IFC Pset_IkeaProduct metadata.",
    params = {
        type = "object",
        required = { "id" },
        properties = {
            id = { type = "string", description = "IKEA 8-digit item ID or dotted article number (e.g. '00275848' or '002.758.48')." },
            position = {
                type = "array",
                items = { type = "number" },
                minItems = 2,
                maxItems = 2,
                description = "Optional [x, y] plan position in meters. If provided, places an instance; if omitted, only loads the component type.",
            },
            level = { type = "string", description = "Optional level name or ID (default: lowest level)." },
            rotation = { type = "number", description = "Optional rotation in plan, in degrees (default 0)." },
            base_offset = { type = "number", description = "Optional elevation offset above the level in meters (default 0)." },
        },
    },
    run = function(args)
        local st, idx = lookup_index(args.id)
        local id = st.ids[idx]
        local name = st.names[idx]
        local article = M.format_article(id)
        local comp_name = name .. " " .. article

        -- Reuse an already-loaded component type of the same IKEA article when present.
        local type_id = nil
        local faces = nil
        local reused = false
        local existing = ccad.run("types_list", { category = "component" })
        if type(existing) == "table" then
            for i = 1, #existing do
                if existing[i].name == comp_name then
                    type_id = existing[i].id
                    reused = true
                    break
                end
            end
        end

        if not type_id then
            local _, _, load_args = prepare_load_args(id)
            local loaded = ccad.run("gltf_component_load", load_args)
            type_id = loaded.types and loaded.types[1] or nil
            comp_name = loaded.component or comp_name
            faces = loaded.faces
        end

        local out = {
            id = id,
            article = article,
            name = name,
            component = comp_name,
            type_id = type_id,
            reused = reused,
            url = st.urls[idx],
        }
        if faces then out.faces = faces end
        if type(args.position) == "table" and type_id then
            local place_args = {
                type = type_id,
                position = args.position,
            }
            if type(args.level) == "string" and args.level ~= "" then
                place_args.level = args.level
            end
            if type(args.rotation) == "number" then
                place_args.rotation = args.rotation
            end
            if type(args.base_offset) == "number" then
                place_args.base_offset = args.base_offset
            end
            local placed = ccad.run("component_place", place_args)
            out.element_id = placed.id
        end
        return out
    end,
}

return M
