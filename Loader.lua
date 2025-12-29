local GameList = {

    -- 제목 없는 rpg 1세계
    [118582391303761] = "https://raw.githubusercontent.com/bgsn523/Bgsn1-Hub/refs/heads/main/scripts/UntitledRPG/1.lua",

    -- 제목 없는 rpg 2세계
    [117917823443279] = "https://raw.githubusercontent.com/bgsn523/Bgsn1-Hub/refs/heads/main/scripts/UntitledRPG/2.lua",

}

-- ==================================================================
local PlaceId = game.PlaceId
local ScriptUrl = GameList[PlaceId]

print("[Hub] Checking current place id... " .. PlaceId)

if ScriptUrl then
    print("[Hub] Script Found! Loading script...")
    
    local success, err = pcall(function()
        loadstring(game:HttpGet(ScriptUrl))()
    end)

    if not success then
        warn("[Hub] Failed to excute script!: " .. err)
    end
else
    warn("[Hub] This (" .. PlaceId .. ") is not available.")
    -- loadstring(game:HttpGet("universal"))()
end

