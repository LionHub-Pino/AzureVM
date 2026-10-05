local Seed = {}

function Seed.random()
    local file = io.open("/dev/urandom", "rb")
    if file then
        local bytes = file:read(4)
        file:close()
        if bytes and #bytes == 4 then
            local a, b, c, d = bytes:byte(1, 4)
            return (a + b * 256 + c * 65536 + d * 16777216) % 2147483647 + 1
        end
    end
    -- Portability fallback; not cryptographically unpredictable.
    return (os.time() + math.floor(os.clock() * 1000000)) % 2147483647 + 1
end

return Seed
