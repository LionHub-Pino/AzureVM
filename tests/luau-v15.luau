-- Test modern Luau syntax and transpiler transformations (AzureVM v1.5.2)

type PlayerData = {
    name: string,
    score: number,
    isVIP: boolean
}

local base_score = 0b101010 -- 42
local bonus = 1_000_000

local player_name = "AzureWarrior"
local greeting = `Welcome back, {player_name}! Base score: {base_score}`
print(greeting)

local status = if base_score > 40 then "ELITE" else "NOVICE"
print("Status:", status)

local total = base_score
total += 8
total *= 2
total -= 10
total /= 3
total %= 15
print("Calculated total:", total)

local text = "Azure"
text ..= "VM_v1.5.2"
print("Joined text:", text)

local function compute(val: number, multiplier: number): number
    local res = val * multiplier
    return if res > 100 then res else 100
end

print("Compute output:", compute(30, 4))
