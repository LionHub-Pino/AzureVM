-- Test Luraph v15.2 Anti-Hook, Canary, and Integrity verification

local function run_checks()
    -- 1. String metatable integrity
    local mt = getmetatable("")
    assert(mt == nil or mt.__index == string, "String metatable modified")

    -- 2. Concat Canary
    assert(("lura" .. "ph") == "luraph", "Concat canary failed")

    -- 3. Select range check
    local ok, err = pcall(select, 0)
    assert(ok == false and type(err) == "string" and string.find(err, "range"), "Select behavior altered")

    -- 4. Basic math assertions
    assert(math.floor(1337.9) == 1337, "Math floor hooked")
    assert(math.abs(-42) == 42, "Math abs hooked")

    -- 5. C-closure dump check (must fail in standard Lua/Luau)
    local dump_ok = pcall(string.dump, pcall)
    assert(dump_ok == false, "pcall should not be dumpable unless wrapped by Lua hook")

    print("ALL_V15_HARDENING_CANARIES_PASSED")
end

run_checks()
