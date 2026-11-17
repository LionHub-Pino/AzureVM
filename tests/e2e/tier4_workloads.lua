-- Tier 4: Realistic Multi-Function Application Workloads (6 workloads)
-- Exercises stateful ECS, binary protocol + CRC-32, short & full license validator,
-- OOP class hierarchy, cooperative async coroutine scheduler, and Luau rule engine.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("Tier4_Workloads")

suite:test("T4_W1_stateful_mini_ecs_engine", "FA1+FA2+FA3+FA4", function()
    local src = [[
        local function create_world()
            local next_id = 0
            local alive = {}
            local pos = {}
            local vel = {}
            local tags = {}

            local world = {}
            function world.spawn(x, y, vx, vy, tag)
                next_id = next_id + 1
                local id = next_id
                alive[id] = true
                pos[id] = { x = x, y = y }
                vel[id] = { vx = vx, vy = vy }
                tags[id] = tag or "entity"
                return id
            end
            function world.despawn(id)
                alive[id] = nil
                pos[id] = nil
                vel[id] = nil
                tags[id] = nil
            end
            function world.query_movers()
                local ids = {}
                for id = 1, next_id do
                    if alive[id] and pos[id] and vel[id] then
                        ids[#ids + 1] = id
                    end
                end
                local i = 0
                return function()
                    i = i + 1
                    local id = ids[i]
                    if not id then return nil end
                    return id, pos[id], vel[id], tags[id]
                end
            end
            function world.tick(dt)
                for id, p, v in world.query_movers() do
                    p.x = p.x + v.vx * dt
                    p.y = p.y + v.vy * dt
                end
            end
            function world.snapshot()
                local out = {}
                for id, p, _, tag in world.query_movers() do
                    out[#out + 1] = tag .. "@" .. p.x .. "," .. p.y
                end
                return table.concat(out, ";")
            end
            return world
        end

        local w = create_world()
        local e1 = w.spawn(0, 0, 2, 3, "hero")
        local e2 = w.spawn(10, -4, -1, 2, "drone")
        local e3 = w.spawn(5, 5, 0, 0, "temp")
        w.despawn(e3)
        w.tick(3)
        w.tick(2)
        return e1, e2, w.snapshot()
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 4101 })
end)

suite:test("T4_W2_binary_frame_codec_crc32", "FA1+FA2+FA4", function()
    local src = [[
        local function bxor(a, b)
            local res = 0
            local bitval = 1
            while a > 0 or b > 0 do
                local ra = a % 2
                local rb = b % 2
                if ra ~= rb then res = res + bitval end
                a = math.floor(a / 2)
                b = math.floor(b / 2)
                bitval = bitval * 2
            end
            return res
        end

        local function crc32(s)
            local crc = 4294967295
            for i = 1, #s do
                crc = bxor(crc, string.byte(s, i))
                for _ = 1, 8 do
                    local lsb = crc % 2
                    crc = math.floor(crc / 2)
                    if lsb == 1 then
                        crc = bxor(crc, 3988292384)
                    end
                end
            end
            return (4294967295 - crc)
        end

        local function u32_be(n)
            local b4 = n % 256; n = math.floor(n / 256)
            local b3 = n % 256; n = math.floor(n / 256)
            local b2 = n % 256; n = math.floor(n / 256)
            local b1 = n % 256
            return string.char(b1, b2, b3, b4)
        end

        local function read_u32_be(s, off)
            local b1, b2, b3, b4 = string.byte(s, off, off + 3)
            return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        end

        local function encode_frame(id, flags, payload)
            local body = string.char(id % 256, flags % 256) .. u32_be(#payload) .. payload
            return "\170\85" .. body .. u32_be(crc32(body))
        end

        local function decode_frame(raw)
            if #raw < 12 or string.sub(raw, 1, 2) ~= "\170\85" then
                return nil, "bad_magic"
            end
            local id, flags = string.byte(raw, 3, 4)
            local len = read_u32_be(raw, 5)
            if #raw ~= 12 + len then
                return nil, "bad_len"
            end
            local body = string.sub(raw, 3, 8 + len)
            local expected_crc = read_u32_be(raw, 9 + len)
            if crc32(body) ~= expected_crc then
                return nil, "bad_crc"
            end
            return { id = id, flags = flags, payload = string.sub(raw, 9, 8 + len) }
        end

        local f1 = encode_frame(7, 3, "AUTH:\0\1\255:OK")
        local d1, err1 = decode_frame(f1)
        local tampered = string.sub(f1, 1, 9) .. "X" .. string.sub(f1, 11)
        local d2, err2 = decode_frame(tampered)
        return d1 ~= nil, err1 == nil, d1.id, d1.flags, #d1.payload, d1.payload:sub(1, 4), d2 == nil, err2
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 4102 })
end)

suite:test("T4_W3_license_auth_short_and_full_paths", "FA1+FA4+FA6+FA7", function()
    -- Short fast-fail (<10 VM instructions)
    local short_src = [[ return (...) == "AZ-KEY-9921" ]]
    -- Full validator
    local full_src = [[
        local function checksum_token(tok)
            local acc = 17
            for i = 1, #tok do
                acc = (acc * 31 + string.byte(tok, i) + i) % 65521
            end
            return acc
        end
        local function verify(token, epoch)
            if type(token) ~= "string" or #token < 10 then
                return false, "malformed"
            end
            local tier, exp_str, sig_str = token:match("^([A-Z]+)%-(%d+)%-(%d+)$")
            if not tier then
                return false, "format"
            end
            local exp = tonumber(exp_str)
            if exp < epoch then
                return false, "expired"
            end
            local expected_sig = checksum_token(tier .. ":" .. exp_str)
            if tonumber(sig_str) ~= expected_sig then
                return false, "bad_sig"
            end
            return true, tier
        end
        local tok_ok = "PRO-2000-" .. tostring(checksum_token("PRO:2000"))
        local tok_exp = "STD-1000-" .. tostring(checksum_token("STD:1000"))
        local ok1, r1 = verify(tok_ok, 1500)
        local ok2, r2 = verify(tok_exp, 1500)
        local ok3, r3 = verify("PRO-2000-0", 1500)
        return ok1, r1, ok2, r2, ok3, r3
    ]]
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        E2E.assert_compile_and_match(short_src, {
            preset = preset, compact = true, seed = 4103, args = E2E.pack("AZ-KEY-9921"),
        }, E2E.pack(true))
        E2E.assert_compile_and_match(short_src, {
            preset = preset, compact = true, seed = 4103, args = E2E.pack("WRONG"),
        }, E2E.pack(false))
        E2E.assert_compile_and_match(full_src, {
            preset = preset, compact = true, seed = 4103,
        }, E2E.pack(true, "PRO", false, "expired", false, "bad_sig"))
    end
end)

suite:test("T4_W4_oop_class_hierarchy_metamethods", "FA1+FA2+FA3+FA4", function()
    local src = [[
        local seq = 0
        local Shape = {}
        Shape.__index = Shape
        function Shape:new(name)
            seq = seq + 1
            return setmetatable({ id = seq, name = name }, self)
        end
        function Shape:describe()
            return "#" .. self.id .. ":" .. self.name
        end

        local Vec2 = setmetatable({}, { __index = Shape })
        Vec2.__index = Vec2
        function Vec2:new(x, y)
            local o = Shape.new(self, "Vec2")
            o.x = x
            o.y = y
            return setmetatable(o, Vec2)
        end
        function Vec2.__add(a, b)
            return Vec2:new(a.x + b.x, a.y + b.y)
        end
        function Vec2.__eq(a, b)
            return a.x == b.x and a.y == b.y
        end
        function Vec2.__tostring(a)
            return a:describe() .. "(" .. a.x .. "," .. a.y .. ")"
        end
        function Vec2.__call(a, scale)
            return a.x * scale + a.y * scale
        end

        local a = Vec2:new(3, 4)
        local b = Vec2:new(1, 2)
        local c = a + b
        return tostring(c), c == Vec2:new(4, 6), c(10), seq
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 4104 })
end)

suite:test("T4_W5_cooperative_async_coroutine_scheduler", "FA1+FA3+FA4+FA6", function()
    local src = [[
        local function create_scheduler()
            local queue = {}
            local log = {}
            local sched = {}

            function sched.spawn(name, prio, fn)
                queue[#queue + 1] = { name = name, prio = prio, co = coroutine.create(fn) }
            end

            function sched.run()
                while #queue > 0 do
                    table.sort(queue, function(a, b) return a.prio > b.prio end)
                    local task = table.remove(queue, 1)
                    local ok, tag = coroutine.resume(task.co)
                    if not ok then
                        log[#log + 1] = task.name .. ":ERR:" .. tostring(tag)
                    elseif coroutine.status(task.co) ~= "dead" then
                        log[#log + 1] = task.name .. ":" .. tostring(tag)
                        queue[#queue + 1] = task
                    else
                        log[#log + 1] = task.name .. ":DONE:" .. tostring(tag)
                    end
                end
                return table.concat(log, "|")
            end

            return sched
        end

        local s = create_scheduler()
        s.spawn("net", 10, function()
            coroutine.yield("req")
            local ok = pcall(function() error("retryable", 0) end)
            return ok and "ok" or "recovered"
        end)
        s.spawn("io", 5, function()
            coroutine.yield("read")
            return "flushed"
        end)
        s.spawn("bad", 1, function()
            error("task_crash", 0)
        end)
        return s.run()
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 4105 })
end)

suite:test("T4_W6_luau_rule_inventory_evaluator", "FA1+FA2+FA4+FA5", function()
    local src = [[
        export type Item = { name: string, qty: number, price: number, flags: number }
        type Summary = { count: number, total: number, label: string }

        local VIP_FLAG: number = 0b0100
        local BONUS_CAP: number = 1_000

        local items: any = {
            { name = "Sword", qty = 2, price = 150, flags = 0b0101 },
            { name = "Potion", qty = 5, price = 40, flags = 0b0001 },
            { name = "Shield", qty = 1, price = 320, flags = 0b0100 },
        }

        local total = 0
        local vip_count = 0
        for i = 1, #items do
            local it = items[i]
            local sub = it.qty * it.price
            if (it.flags % 8) >= VIP_FLAG then
                vip_count += 1
                sub *= 0.9
            end
            total += sub
        end

        local tier = if total >= BONUS_CAP then "PLATINUM" else "GOLD"
        local summary: Summary = {
            count = vip_count,
            total = total,
            label = `tier={tier}:vip={vip_count}:total={total}`
        }
        local tag: string = (summary.label :: any)
        tag ..= ":OK"
        return summary.count, summary.total, tag
    ]]
    -- Expected: Sword 2*150*0.9=270, Potion 5*40=200, Shield 1*320*0.9=288 -> total=758, vip=2
    E2E.assert_compile_and_match(src, {
        preset = "AzureGodUltra", compact = true, seed = 4106, ext = ".luau",
    }, E2E.pack(2, 758, "tier=GOLD:vip=2:total=758:OK"))
end)

suite:finish()
