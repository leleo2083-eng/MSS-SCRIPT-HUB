local scripts = {
    [97598239454123] = "https://raw.githubusercontent.com/leleo2083-eng/SolisUILibary/refs/heads/main/MSS.lua",
    [987654321] = "https://raw.githubusercontent.com/USERNAME/REPO/main/script2.lua",
    [111111111] = "https://raw.githubusercontent.com/USERNAME/REPO/main/script3.lua",
}

local placeId = game.PlaceId
local scriptUrl = scripts[placeId]

if scriptUrl then
    local success, err = pcall(function()
        loadstring(game:HttpGet(scriptUrl, true))()
    end)

    if not success then
        warn("Failed to load script:", err)
    end
else
    warn("No script assigned for PlaceId:", placeId)
end
