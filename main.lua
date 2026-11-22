-- IKEA Browser plugin for ConstructCraft (Plugin API 3)
-- Data source: https://huggingface.co/datasets/T-K-233/ikea-furniture
-- No live price lookup; each imported component carries a clickable IKEA productUrl.

local M = {}

local catalog_state = nil

local function base_prefix()
    local base = (ccad.settings.base_url or "https://huggingface.co/datasets/T-K-233/ikea-furniture/resolve")
        :gsub("/+$", "")
    local rev = (ccad.settings.dataset_rev or "main"):gsub("^/+", ""):gsub("/+$", "")
    if rev == "" then rev = "main" end
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

----- Parse a single array-encoded row from data/catalog-N.json into a structured record.
function M.parse_row(row)
    local id = type(row[1]) == "string" and row[1] or ""
    local name = type(row[2]) == "string" and row[2] or ""
    local type_name = type(row[3]) == "string" and row[3] or ""
    local path = type(row[4]) == "table" and row[4] or {}
    local variant = type(row[5]) == "string" and row[5] or ""
    local image = type(row[6]) == "string" and row[6] or ""
    local bytes = tonumber(row[8]) or 0
    local hash = type(row[9]) == "string" and row[9] or ""
    local dims = type(row[10]) == "table" and row[10] or {}
    local colors = type(row[11]) == "table" and row[11] or {}
    local product_url = type(row[12]) == "string" and row[12] or ""
    local kind, ifc_class = M.classify(path)
    local search_blob = (name .. " " .. type_name .. " " .. variant .. " " .. id .. " " .. M.format_article(id)):lower()
    return {
        id = id,
        article = M.format_article(id),
        name = name,
        type_name = type_name,
        path = path,
        variant = variant,
        image = image,
        bytes = bytes,
        hash = hash,
        dimensions = dims,
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
    if catalog_state then
        return catalog_state
    end
    local prefix, rev = base_prefix()
    local safe_rev = rev:gsub("[^a-zA-Z0-9._-]", "_")
    local manifest = fetch_json_cached(
        prefix .. "/data/manifest.json",
        "catalog/" .. safe_rev .. "/manifest.json",
        4 * 1024 * 1024
    )
    local items = {}
    local by_id = {}
    local color_set = {}
    local chunks = manifest.chunks or {}
    for _, chunk_name in ipairs(chunks) do
        local rows = fetch_json_cached(
            prefix .. "/data/" .. chunk_name,
            "catalog/" .. safe_rev .. "/" .. chunk_name,
            16 * 1024 * 1024
        )
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                local item = M.parse_row(row)
                if #item.id == 8 then
                    items[#items + 1] = item
                    by_id[item.id] = item
                    for _, c in ipairs(item.colors) do
                        if type(c) == "string" and c ~= "" then
                            color_set[c] = true
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
        rev = rev,
        snapshot = type(manifest.snapshot) == "string" and manifest.snapshot or "",
        categories = type(manifest.categories) == "table" and manifest.categories or {},
        colors = colors,
        items = items,
        by_id = by_id,
    }
    return catalog_state
end

local function path_starts_with(path, prefix_code)
    if type(prefix_code) ~= "string" or prefix_code == "" then
        return true
    end
    for _, seg in ipairs(path) do
        if seg == prefix_code then
            return true
        end
    end
    return false
end

local function has_color(colors, wanted)
    if type(wanted) ~= "string" or wanted == "" then
        return true
    end
    for _, c in ipairs(colors) do
        if c == wanted then
            return true
        end
    end
    return false
end

local function fits_dimensions(dims, max_w, max_d, max_h)
    local w = type(dims.width) == "number" and dims.width or nil
    local d = type(dims.depth) == "number" and dims.depth or nil
    local h = type(dims.height) == "number" and dims.height or nil
    if max_w and w and w > max_w then return false end
    if max_d and d and d > max_d then return false end
    if max_h and h and h > max_h then return false end
    return true
end

function M.filter_items(items, query)
    local raw_text = type(query.text) == "string" and query.text or ""
    local text = raw_text:lower():match("^%s*(.-)%s*$")
    local category = type(query.category) == "string" and query.category or nil
    local color = type(query.color) == "string" and query.color or nil
    local max_w = tonumber(query.max_width)
    local max_d = tonumber(query.max_depth)
    local max_h = tonumber(query.max_height)
    local offset = math.max(0, math.floor(tonumber(query.offset) or 0))
    local limit = math.min(200, math.max(1, math.floor(tonumber(query.limit) or 60)))

    local matches = {}
    for _, item in ipairs(items) do
        if path_starts_with(item.path, category)
            and has_color(item.colors, color)
            and fits_dimensions(item.dimensions, max_w, max_d, max_h)
            and (text == "" or item.search_blob:find(text, 1, true) ~= nil)
        then
            matches[#matches + 1] = item
        end
    end

    local page = ccad.array()
    local stop = math.min(#matches, offset + limit)
    for i = offset + 1, stop do
        local it = matches[i]
        page[#page + 1] = {
            id = it.id,
            name = it.name,
            subtitle = it.variant ~= "" and (it.type_name .. " — " .. it.variant) or it.type_name,
            kind = it.kind,
            article = it.article,
            bytes = it.bytes,
            dimensions = it.dimensions,
            colors = ccad.array(it.colors),
            url = it.product_url,
            has_thumbnail = it.image ~= "",
        }
    end
    return { total = #matches, items = page }
end

ccad.catalog {
    id = "ikea",
    load = function()
        local st = load_catalog()
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
        return {
            total = #st.items,
            snapshot = st.snapshot,
            categories = cats,
            colors = ccad.array(st.colors),
            notice = "Product names, images, and 3D models originate from IKEA (snapshot " .. st.snapshot .. ").",
        }
    end,
    search = function(query)
        local st = load_catalog()
        return M.filter_items(st.items, query or {})
    end,
    thumbnail = function(item_id)
        local st = load_catalog()
        local item = st.by_id[item_id]
        if not item or item.image == "" then
            return nil
        end
        local rel = item.image:gsub("^/+", "")
        local prefix = base_prefix()
        return ccad.http.download(prefix .. "/" .. rel, rel, { max_bytes = 2 * 1024 * 1024 })
    end,
    prepare = function(item_id)
        local st = load_catalog()
        local item = st.by_id[item_id]
        if not item then
            error("unknown IKEA item id: " .. tostring(item_id))
        end
        local prefix = base_prefix()
        local model_url = prefix .. "/raw/" .. item.id:sub(1, 2) .. "/" .. item.id .. "/model.glb"
        local cache_key = "models/" .. item.hash:sub(1, 2) .. "/" .. item.hash .. ".glb"
        local local_path = ccad.http.download(model_url, cache_key, {
            sha256 = item.hash,
            max_bytes = 64 * 1024 * 1024,
        })
        local props = {
            ArticleNumber = item.article,
            ProductName = item.name,
            TypeName = item.type_name,
            ModelSha256 = item.hash,
        }
        if item.variant ~= "" then props.Variant = item.variant end
        if item.product_url ~= "" then props.ProductUrl = item.product_url end
        if type(item.dimensions.width) == "number" then props.CatalogWidth = item.dimensions.width end
        if type(item.dimensions.depth) == "number" then props.CatalogDepth = item.dimensions.depth end
        if type(item.dimensions.height) == "number" then props.CatalogHeight = item.dimensions.height end
        return {
            command = "gltf_component_load",
            args = {
                path = local_path,
                name = item.name .. " " .. item.article,
                kind = item.kind,
                ifc_class = item.ifc_class,
                properties = { Pset_IkeaProduct = props },
            },
        }
    end,
}

return M
