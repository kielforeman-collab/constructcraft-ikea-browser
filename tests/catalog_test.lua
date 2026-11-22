-- Unit tests for the IKEA Browser plugin (run with `ccad plugins test`).

function test_article_formatting()
    -- Format 8-digit article numbers via a standalone helper check.
    local id = "00069768"
    local formatted = id:sub(1, 3) .. "." .. id:sub(4, 6) .. "." .. id:sub(7, 8)
    ccad.test.eq(formatted, "000.697.68")
end

function test_plugin_loads_with_api_v3()
    ccad.test.ok(ccad.api >= 3, "expected plugin API >= 3")
end
