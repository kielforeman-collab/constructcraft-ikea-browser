-- Unit tests for the IKEA Browser plugin (run with `ccad plugins test`).

local function format_article(id)
    local digits = tostring(id or ""):gsub("[^0-9]", "")
    if #digits == 8 then
        return digits:sub(1, 3) .. "." .. digits:sub(4, 6) .. "." .. digits:sub(7, 8)
    end
    return tostring(id or "")
end

local function classify(path)
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

function test_article_formatting()
    ccad.test.eq(format_article("00069768"), "000.697.68")
    ccad.test.eq(format_article("802.758.87"), "802.758.87")
    ccad.test.eq(format_article("short"), "short")
end

function test_category_classification()
    local k1, i1 = classify({ "st001", "46052" })
    ccad.test.eq(k1, "casework")
    ccad.test.eq(i1, "IFCFURNITURE")

    local k2, i2 = classify({ "li001", "10731" })
    ccad.test.eq(k2, "lighting")
    ccad.test.eq(i2, "IFCLIGHTFIXTURE")

    local k3, i3 = classify({ "hi001", "700718", "10482" })
    ccad.test.eq(k3, "plumbing")
    ccad.test.eq(i3, "IFCSANITARYTERMINAL")

    local k4, i4 = classify({ "bm001", "bm003" })
    ccad.test.eq(k4, "furniture")
    ccad.test.eq(i4, "IFCFURNITURE")
end

function test_plugin_loads_with_api_v3()
    ccad.test.ok(ccad.api >= 3, "expected plugin API >= 3")
end

function test_json_null_handling()
    local decoded = ccad.json.decode('{"category":null,"color":null,"text":"","max_width":null}')
    -- mlua represents JSON null as truthy light userdata (ccad.null), not nil.
    ccad.test.ok(decoded.category == ccad.null, "expected JSON null to decode to ccad.null")
    local category = type(decoded.category) == "string" and decoded.category or nil
    local color = type(decoded.color) == "string" and decoded.color or nil
    local max_w = tonumber(decoded.max_width)
    ccad.test.eq(category, nil)
    ccad.test.eq(color, nil)
    ccad.test.eq(max_w, nil)
end

function test_mcp_commands_registered()
    local found = {}
    for _, cmd in ipairs(ccad.commands()) do
        found[cmd.name] = cmd.kind
    end
    ccad.test.eq(found["ikea_browser__categories"], "query")
    ccad.test.eq(found["ikea_browser__search"], "query")
    ccad.test.eq(found["ikea_browser__place"], "edit")
end
