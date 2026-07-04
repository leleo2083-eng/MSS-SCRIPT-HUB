-- ══════════════════════════════════════════════════════════════════════════════
-- MSS HUB v30 - GAG2 (Decompiled Networking API)
-- Game: Wachsen Sie einen Garten 2 | PlaceId 97598239454123
-- Requires MSS UI v2.3+ for config saving (gracefully degrades on older builds)
-- ══════════════════════════════════════════════════════════════════════════════

local MSS_URL = "https://raw.githubusercontent.com/leleo2083-eng/SolisUILibary/refs/heads/main/MSS.lua"

local okFetch, source = pcall(game.HttpGet, game, MSS_URL)
if not okFetch then
    error("[MSS HUB] Failed to download the UI library: " .. tostring(source), 0)
end
if type(source) ~= "string" or #source < 10000 then
    error(("[MSS HUB] The hosted MSS.lua looks incomplete (%d bytes). Re-upload the full library to GitHub.")
        :format(type(source) == "string" and #source or -1), 0)
end

local chunk, compileErr = loadstring(source)
if not chunk then
    error("[MSS HUB] The UI library failed to compile: " .. tostring(compileErr), 0)
end

local Library = chunk()

local Window = Library:CreateWindow({
    Name = "MSS HUB",
    LoadingAnimation = true,
    LoadingText = "MSS",
    LoadingDuration = 2.65,
})

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIG / FLAG PERSISTENCE (uses MSS UI v2.3+ flag system; feature-guarded)
-- ══════════════════════════════════════════════════════════════════════════════
local HAS_CONFIG  = type(Library.SaveConfig) == "function"
    and type(Library.LoadConfig) == "function"
    and type(Library.ListConfigs) == "function"
local CONFIG_NAME = "gag2"

-- Dropdowns apply their value through Set, which does NOT re-fire the element
-- callback, so we re-sync the script's variables manually after a config load.
local dropdownResync = {}
local function registerResync(handle, applyFn)
    if handle and applyFn then
        table.insert(dropdownResync, function() applyFn(handle:Get()) end)
    end
end
local function ResyncAll()
    for _, fn in ipairs(dropdownResync) do pcall(fn) end
end

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local UserId = LocalPlayer.UserId

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))

local StealFlags
pcall(function()
    StealFlags = require(ReplicatedStorage.SharedModules.Flags.StealFlags)
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- DIRECT ACTION FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════
local function DoSell()
    pcall(function() Networking.NPCS.SellAll:Fire() end)
end

local function PreviewSell()
    local ok, result = pcall(function() return Networking.NPCS.PreviewSellAll:Fire() end)
    return ok and result or nil
end

local function BuySeed(name)
    if not name or name == "" then return end
    pcall(function() Networking.SeedShop.PurchaseSeed:Fire(name) end)
end

local function BuyGear(name)
    if not name or name == "" then return end
    pcall(function() Networking.GearShop.PurchaseGear:Fire(name) end)
end

local function BuyCrate(name)
    if not name or name == "" then return end
    pcall(function() Networking.CrateShop.PurchaseCrate:Fire(name) end)
end

local PLANT_MIN_DIST = 1.05
local lastPlantTime = 0

local function WaterDirect(position, canName, tool)
    if not position or not canName or not tool then return false end
    local ok = pcall(function()
        Networking.WateringCan.UseWateringCan:Fire(position - Vector3.new(0, 0.3, 0), canName, tool)
    end)
    return ok
end

local function OpenCrateDirect(crateId)
    if not crateId or crateId == "" then return false end
    local ok = pcall(function() Networking.Crate.OpenCrate:Fire(crateId) end)
    return ok
end

local function ExpandGarden()
    pcall(function() Networking.Actions.ExpandGarden:Fire() end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════════════════════════
local function GetHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function TeleportTo(pos)
    local hrp = GetHRP()
    if not hrp or not pos then return false end
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    return true
end

local function GetModelPosition(model)
    if not model or not model.Parent then return nil end
    if model:IsA("BasePart") then return model.Position end
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and cf then return cf.Position end
    local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    return pp and pp.Position
end

local function IsNight()
    local night = ReplicatedStorage:FindFirstChild("Night")
    return night and night.Value == true
end

local function IsRipe(model)
    local age = model:GetAttribute("Age")
    local maxAge = model:GetAttribute("MaxAge")
    if typeof(age) ~= "number" or typeof(maxAge) ~= "number" then
        return true
    end
    return maxAge <= age
end

local function IsPlantStealable(name)
    if not name then return true end
    if StealFlags and StealFlags.IsPlantStealable then
        return StealFlags.IsPlantStealable(name)
    end
    return true
end

local function GetPromptWorldPosition(prompt)
    local parent = prompt.Parent
    if not parent then return nil end
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Model") then return GetModelPosition(parent) end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    for _, c in ipairs(parent:GetChildren()) do
        if c:IsA("BasePart") then return c.Position end
    end
    return nil
end

local function FindMyPlot()
    local plotId = LocalPlayer:GetAttribute("PlotId")
    if plotId then
        local gardens = workspace:FindFirstChild("Gardens")
        if gardens then
            local plot = gardens:FindFirstChild("Plot" .. tostring(plotId))
            if plot then return plot end
        end
    end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if plants then
            for _, plant in ipairs(plants:GetChildren()) do
                if plant:GetAttribute("UserId") == UserId then return plot end
            end
        end
    end
    return nil
end

local function GetVisiblePlantAreas(plot)
    local areas = {}
    if not plot then return areas end
    for _, part in ipairs(plot:GetDescendants()) do
        if part:IsA("BasePart") and CollectionService:HasTag(part, "PlantArea") and part.Transparency < 1 then
            table.insert(areas, part)
        end
    end
    return areas
end

local function GetPlantBlockers(plot)
    local blockers = {}
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return blockers end
    for _, plant in ipairs(plants:GetChildren()) do
        local pos = GetModelPosition(plant)
        if pos then table.insert(blockers, pos) end
    end
    return blockers
end

local function IsSpotClear(pos, blockers, minDist)
    minDist = minDist or PLANT_MIN_DIST
    for _, bp in ipairs(blockers) do
        local dx, dz = pos.X - bp.X, pos.Z - bp.Z
        if dx * dx + dz * dz < minDist * minDist then return false end
    end
    return true
end

local function SurfacePlantPosition(areaPart, localX, localZ)
    local size = areaPart.Size
    return areaPart.CFrame:PointToWorldSpace(Vector3.new(localX, size.Y / 2 + 0.15, localZ))
end

local function GeneratePlantSpots(plot, spacing)
    spacing = math.max(spacing or 2, PLANT_MIN_DIST + 0.5)
    local spots = {}
    local blockers = GetPlantBlockers(plot)
    for _, area in ipairs(GetVisiblePlantAreas(plot)) do
        local size = area.Size
        local halfX = math.max(size.X / 2 - 1.5, 0.5)
        local halfZ = math.max(size.Z / 2 - 1.5, 0.5)
        for x = -halfX, halfX, spacing do
            for z = -halfZ, halfZ, spacing do
                local pos = SurfacePlantPosition(area, x, z)
                if IsSpotClear(pos, blockers, PLANT_MIN_DIST) then
                    table.insert(spots, { position = pos, area = area })
                    table.insert(blockers, pos)
                end
            end
        end
    end
    return spots
end

local function GetSeedQueue(filterNames)
    local filterSet = {}
    if filterNames and #filterNames > 0 then
        for _, name in ipairs(filterNames) do filterSet[name] = true end
    end
    local queue = {}
    local seen = {}
    local function addEntry(item)
        if not item:IsA("Tool") then return end
        local seedName = item:GetAttribute("SeedTool")
        if not seedName then return end
        if next(filterSet) and not filterSet[seedName] then return end
        local count = tonumber(item:GetAttribute("Count")) or 1
        if count <= 0 or not item.Parent then return end
        local key = tostring(item)
        if seen[key] then return end
        seen[key] = true
        table.insert(queue, { seedName = seedName, tool = item, count = count })
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do addEntry(item) end
    end
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do addEntry(item) end
    end
    table.sort(queue, function(a, b) return a.seedName < b.seedName end)
    return queue
end

local function GetBackpackSeedNames()
    local names, seen = {}, {}
    for _, entry in ipairs(GetSeedQueue(nil)) do
        if not seen[entry.seedName] then
            seen[entry.seedName] = true
            table.insert(names, entry.seedName)
        end
    end
    table.sort(names)
    return names
end

local function GetTotalSeedCount(filterNames)
    local total = 0
    for _, entry in ipairs(GetSeedQueue(filterNames)) do
        total += tonumber(entry.tool:GetAttribute("Count")) or 1
    end
    return total
end

local function EquipSeedTool(tool)
    if not tool or not tool.Parent then return false end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local equipped = LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
    if equipped == tool then return true end
    pcall(function() hum:EquipTool(tool) end)
    task.wait(0.1)
    return LocalPlayer.Character:FindFirstChildWhichIsA("Tool") == tool
end

local function GetPlantCount(plot)
    local plants = plot and plot:FindFirstChild("Plants")
    return plants and #plants:GetChildren() or 0
end

local function TryPlantAt(spot, seedName, tool, equipFirst)
    if not spot or not spot.position or not seedName or not tool then return false end
    if not tool.Parent then return false end

    local now = os.clock()
    if now - lastPlantTime < 0.08 then
        task.wait(0.08 - (now - lastPlantTime))
    end

    local plot = FindMyPlot()
    if not plot then return false end
    if not IsSpotClear(spot.position, GetPlantBlockers(plot), PLANT_MIN_DIST) then
        return false
    end

    if equipFirst and not EquipSeedTool(tool) then return false end

    local before = GetPlantCount(plot)
    local fired = pcall(function()
        Networking.Plant.PlantSeed:Fire(spot.position, seedName, tool)
    end)
    lastPlantTime = os.clock()
    if not fired then return false end

    for _ = 1, 6 do
        task.wait(0.05)
        if GetPlantCount(plot) > before then return true end
        if not tool.Parent then break end
        local count = tonumber(tool:GetAttribute("Count")) or 0
        if count <= 0 then return true end
    end
    return false
end

local function RunPlantCycle(seedFilter, spacing, gap, equipFirst, maxPlants)
    local plot = FindMyPlot()
    if not plot then return 0, "no_plot" end

    local queue = GetSeedQueue(seedFilter)
    if #queue == 0 then return 0, "no_seeds" end

    local spots = GeneratePlantSpots(plot, spacing)
    if #spots == 0 then return 0, "full" end

    local planted = 0
    local qi = 1

    for _, spot in ipairs(spots) do
        if maxPlants and planted >= maxPlants then break end

        local entry
        for _ = 1, #queue do
            local cand = queue[qi]
            qi = (qi % #queue) + 1
            local tool = cand.tool
            if tool and tool.Parent then
                local count = tonumber(tool:GetAttribute("Count")) or 1
                if count > 0 then
                    entry = cand
                    break
                end
            end
        end
        if not entry then break end

        if TryPlantAt(spot, entry.seedName, entry.tool, equipFirst) then
            planted += 1
        end
        task.wait(gap)
    end

    return planted, planted > 0 and "ok" or "failed"
end

local function FindWateringCan()
    local function scan(container)
        if not container then return nil, nil end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("WateringCan") then
                return item, item:GetAttribute("WateringCan")
            end
        end
        return nil, nil
    end
    local char = LocalPlayer.Character
    if char then
        local tool, name = scan(char)
        if tool then return tool, name end
    end
    return scan(LocalPlayer:FindFirstChild("Backpack"))
end

local function GetMyPlants(plot)
    local results = {}
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return results end
    for _, plant in ipairs(plants:GetChildren()) do
        if plant:GetAttribute("UserId") == UserId then
            local pos = GetModelPosition(plant)
            if pos then
                table.insert(results, {
                    model = plant,
                    position = pos,
                    seedName = plant:GetAttribute("SeedName") or "Unknown",
                    age = plant:GetAttribute("Age"),
                    maxAge = plant:GetAttribute("MaxAge"),
                })
            end
        end
    end
    return results
end

local function GetBackpackCrates()
    local crates = {}
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("Crate") then
                local crateName = item:GetAttribute("Crate")
                table.insert(crates, {
                    tool = item,
                    name = crateName,
                    id = crateName,
                })
            end
        end
    end
    scan(LocalPlayer:FindFirstChild("Backpack"))
    scan(LocalPlayer.Character)
    return crates
end

local function FirePromptBypassed(prompt, bypass)
    if not prompt or not prompt.Parent then return false end
    local ok = pcall(function()
        if bypass then
            local oldDist = prompt.MaxActivationDistance
            local oldHold = prompt.HoldDuration
            local oldLOS  = prompt.RequiresLineOfSight
            prompt.MaxActivationDistance = math.huge
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            fireproximityprompt(prompt)
            task.delay(0.1, function()
                if prompt.Parent then
                    prompt.MaxActivationDistance = oldDist
                    prompt.HoldDuration = oldHold
                    prompt.RequiresLineOfSight = oldLOS
                end
            end)
        else
            fireproximityprompt(prompt)
        end
    end)
    return ok
end

local function MutationPriority(mut)
    if mut == "Rainbow" then return 100 end
    if mut == "Starstruck" then return 80 end
    if mut == "Aurora" then return 70 end
    if mut == "Bloodlit" then return 60 end
    if mut == "Gold" then return 50 end
    if mut == "None" or mut == nil then return 1 end
    return 25
end

local function CollectFruitDirect(plantId, fruitId)
    if not plantId then return false end
    local ok = pcall(function()
        Networking.Garden.CollectFruit:Fire(plantId, fruitId or "")
    end)
    return ok
end

local function StealFruitDirect(ownerUserId, plantId, fruitId)
    if not ownerUserId or not plantId then return false end
    if not IsNight() then return false end
    local ok = pcall(function()
        Networking.Steal.BeginSteal:Fire(ownerUserId, plantId, fruitId or "")
        Networking.Steal.CompleteSteal:Fire()
    end)
    return ok
end

local function ScanGardenFruits(opts)
    opts = opts or {}
    local results = {}
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end

    local myPlot = FindMyPlot()
    for _, plot in ipairs(gardens:GetChildren()) do
        if opts.onlyMy and plot ~= myPlot then continue end
        if opts.skipMy and plot == myPlot then continue end
        if opts.skipBlocked and plotsBlockedByOwner and plotsBlockedByOwner[plot] then continue end

        local plants = plot:FindFirstChild("Plants")
        if not plants then continue end
        if opts.skipEmpty and #plants:GetChildren() == 0 then continue end

        for _, plant in ipairs(plants:GetChildren()) do
            local ownerId = tonumber(plant:GetAttribute("UserId"))
            local plantId = plant:GetAttribute("PlantId")
            if not ownerId or typeof(plantId) ~= "string" then continue end

            local seedName = plant:GetAttribute("SeedName") or plant:GetAttribute("CorePartName") or "Unknown"

            local function addTarget(model, fruitId)
                if opts.ripeOnly and not IsRipe(model) then return end
                local fruitName = model:GetAttribute("CorePartName") or model:GetAttribute("SeedName") or seedName
                local mutation = model:GetAttribute("Mutation") or model:GetAttribute("Variant") or "None"

                if opts.fruitFilter and opts.fruitFilter ~= "All" and fruitName ~= opts.fruitFilter then return end
                if opts.mutationFilter and opts.mutationFilter ~= "All" then
                    if opts.mutationFilter == "None" then
                        if mutation ~= "None" and mutation ~= nil then return end
                    elseif tostring(mutation) ~= opts.mutationFilter then
                        return
                    end
                end

                table.insert(results, {
                    ownerUserId = ownerId,
                    plantId = plantId,
                    fruitId = fruitId or "",
                    fruitName = fruitName,
                    mutation = tostring(mutation),
                    plot = plot,
                    model = model,
                    position = GetModelPosition(model),
                    isMine = ownerId == UserId,
                    priority = MutationPriority(mutation),
                })
            end

            local fruits = plant:FindFirstChild("Fruits")
            if fruits and #fruits:GetChildren() > 0 then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    local fruitId = fruit:GetAttribute("FruitId")
                    if typeof(fruitId) == "string" then
                        addTarget(fruit, fruitId)
                    end
                end
            elseif opts.includeWholePlants and ownerId == UserId then
                addTarget(plant, "")
            end
        end
    end

    if opts.smartSort then
        table.sort(results, function(a, b) return a.priority > b.priority end)
    end
    return results
end

local function GetAllFruitTypes()
    local types = { "All" }
    local seen = { All = true }

    local function add(name)
        if name and not seen[name] then
            seen[name] = true
            table.insert(types, name)
        end
    end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if assets then
        local seeds = assets:FindFirstChild("Seeds")
        if seeds then
            for _, s in ipairs(seeds:GetChildren()) do add(s.Name) end
        end
    end

    local gardens = workspace:FindFirstChild("Gardens")
    if gardens then
        for _, plot in ipairs(gardens:GetChildren()) do
            local plants = plot:FindFirstChild("Plants")
            if plants then
                for _, plant in ipairs(plants:GetChildren()) do
                    add(plant:GetAttribute("SeedName") or plant:GetAttribute("CorePartName"))
                    local ff = plant:FindFirstChild("Fruits")
                    if ff then
                        for _, fruit in ipairs(ff:GetChildren()) do
                            add(fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName"))
                        end
                    end
                end
            end
        end
    end

    table.sort(types, function(a, b)
        if a == "All" then return true end
        if b == "All" then return false end
        return a < b
    end)
    return types
end

local function GetAllMutations()
    local muts = { "All", "None" }
    local seen = { All = true, None = true }
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return muts end
    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if plants then
            for _, plant in ipairs(plants:GetChildren()) do
                local ff = plant:FindFirstChild("Fruits")
                if ff then
                    for _, fruit in ipairs(ff:GetChildren()) do
                        local m = fruit:GetAttribute("Mutation") or fruit:GetAttribute("Variant")
                        if m and not seen[tostring(m)] then
                            seen[tostring(m)] = true
                            table.insert(muts, tostring(m))
                        end
                    end
                end
            end
        end
    end
    return muts
end

local function GetShopItems(shopName)
    local items = {}
    local seen = {}
    local stock = ReplicatedStorage:FindFirstChild("StockValues")
    if stock then
        local shop = stock:FindFirstChild(shopName)
        if shop then
            local it = shop:FindFirstChild("Items")
            if it then
                for _, item in ipairs(it:GetChildren()) do
                    if not seen[item.Name] then
                        seen[item.Name] = true
                        table.insert(items, item.Name)
                    end
                end
            end
        end
    end
    table.sort(items)
    return items
end

local function GetSeedShopItems() return GetShopItems("SeedShop") end
local function GetGearShopItems() return GetShopItems("GearShop") end
local function GetCrateShopItems() return GetShopItems("CrateShop") end

-- ══════════════════════════════════════════════════════════════════════════════
-- AUTO TAB
-- ══════════════════════════════════════════════════════════════════════════════
local AutoTab = Window:AddTab({ Name = "Auto", Subtitle = "Automation", Icon = "lightning" })

-- ── AUTO SELL ─────────────────────────────────────────────────────────────────
local SellSub   = AutoTab:AddSubTab("Auto Sell")
local autoSell  = false
local sellDelay = 5

SellSub:AddToggle({
    Name = "Auto Sell", Default = false, Flag = "sell_auto",
    Callback = function(v)
        autoSell = v
        Window:Notify({Title="Auto Sell", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
SellSub:AddSlider({ Name="Sell Interval", Min=1, Max=60, Default=5, Suffix="s", Flag="sell_interval", Callback=function(v) sellDelay=v end })
SellSub:AddButton({
    Name = "Sell Now", Primary = true,
    Callback = function()
        DoSell()
        Window:Notify({Title="Sell", Content="Sold inventory!", Type="Success", Duration=2})
    end,
})
SellSub:AddButton({
    Name = "Preview Sell Value",
    Callback = function()
        local preview = PreviewSell()
        if preview then
            local val = preview.TotalSellValue or preview.TotalValue or preview.TotalBaseValue or 0
            Window:Notify({Title="Sell Preview", Content=("Value: %s"):format(tostring(val)), Type="Info", Duration=4})
        else
            Window:Notify({Title="Sell Preview", Content="Could not fetch preview", Type="Error", Duration=3})
        end
    end,
})

task.spawn(function()
    while true do
        if autoSell then DoSell() end
        task.wait(sellDelay)
    end
end)

-- ── AUTO HARVEST ──────────────────────────────────────────────────────────────
local HarvestSub    = AutoTab:AddSubTab("Auto Harvest")
local autoHarvest   = false
local harvestDelay  = 0.3
local harvestOnlyMy = true
local harvestFilter = "All"
local harvestRipeOnly = true
local harvestUseAPI = true
local harvestGap    = 0.05

HarvestSub:AddToggle({
    Name = "Auto Harvest", Default = false, Flag = "harvest_auto",
    Callback = function(v)
        autoHarvest = v
        Window:Notify({Title="Auto Harvest", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
HarvestSub:AddToggle({ Name="Use Direct API", Default=true, Flag="harvest_api", Callback=function(v) harvestUseAPI=v end })
HarvestSub:AddToggle({ Name="Only Ripe Fruit", Default=true, Flag="harvest_ripe", Callback=function(v) harvestRipeOnly=v end })
HarvestSub:AddSlider({ Name="Cycle Delay", Min=0.1, Max=10, Default=0.3, Suffix="s", Flag="harvest_cycle", Callback=function(v) harvestDelay=v end })
HarvestSub:AddSlider({ Name="Action Gap", Min=0.01, Max=1, Default=0.05, Suffix="s", Flag="harvest_gap", Callback=function(v) harvestGap=v end })
HarvestSub:AddToggle({ Name="Only My Plot", Default=true, Flag="harvest_onlymy", Callback=function(v) harvestOnlyMy=v end })

local function applyHarvestFilter(v) harvestFilter=v end
local harvestDropdown = HarvestSub:AddDropdown({
    Name="Fruit Filter", Options=GetAllFruitTypes(), Default="All",
    MaxVisible=5, Searchable=true, Flag="harvest_fruit",
    Callback=applyHarvestFilter,
})
registerResync(harvestDropdown, applyHarvestFilter)
HarvestSub:AddButton({
    Name="Refresh Fruit List",
    Callback=function()
        harvestDropdown:SetOptions(GetAllFruitTypes())
        Window:Notify({Title="Refreshed", Content="Fruit list updated.", Type="Info", Duration=2})
    end,
})

task.spawn(function()
    while true do
        if autoHarvest then
            local targets = ScanGardenFruits({
                onlyMy = harvestOnlyMy,
                fruitFilter = harvestFilter,
                ripeOnly = harvestRipeOnly,
                includeWholePlants = true,
            })
            for _, t in ipairs(targets) do
                if not autoHarvest then break end
                if not t.isMine then continue end
                if harvestUseAPI then
                    CollectFruitDirect(t.plantId, t.fruitId)
                else
                    local prompt = t.model:FindFirstChild("HarvestPrompt", true)
                    if prompt then FirePromptBypassed(prompt, true) end
                end
                task.wait(harvestGap)
            end
        end
        task.wait(harvestDelay)
    end
end)

-- ── AUTO PLANT ────────────────────────────────────────────────────────────────
local PlantSub = AutoTab:AddSubTab("Auto Plant")
local autoPlant = false
local plantDelay = 0.4
local plantGap = 0.15
local plantSpacing = 2
local plantEquip = true
local plantTpPlot = false
local plantSelectedSeeds = {}
local plantPlantedCount = 0
local plantFailNotify = true
local lastPlantFailAt = 0

local function GetPlantFilter()
    return #plantSelectedSeeds > 0 and plantSelectedSeeds or nil
end

local function PlantStatusMessage(planted, reason)
    if planted > 0 then
        return ("Planted %d"):format(planted), "Success"
    end
    if reason == "no_plot" then return "Could not find your plot.", "Error"
    elseif reason == "no_seeds" then return "No seeds in backpack.", "Error"
    elseif reason == "full" then return "Garden is full — no free spots.", "Info"
    else return "Planting failed — spots may be blocked.", "Error" end
end

PlantSub:AddToggle({
    Name = "Auto Plant", Default = false, Flag = "plant_auto",
    Callback = function(v)
        autoPlant = v
        if v then plantPlantedCount = 0 end
        Window:Notify({Title="Auto Plant", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
PlantSub:AddToggle({
    Name = "Equip Seed Before Plant", Default = true, Flag = "plant_equip",
    Description = "Matches the game's planting flow — strongly recommended",
    Callback = function(v) plantEquip = v end,
})
PlantSub:AddToggle({
    Name = "Teleport to Plot", Default = false, Flag = "plant_tp",
    Description = "TP to your plot center before each planting cycle",
    Callback = function(v) plantTpPlot = v end,
})
PlantSub:AddSlider({ Name="Cycle Delay", Min=0.1, Max=10, Default=0.4, Suffix="s", Flag="plant_cycle", Callback=function(v) plantDelay=v end })
PlantSub:AddSlider({ Name="Plant Gap", Min=0.08, Max=2, Default=0.15, Suffix="s", Flag="plant_gap", Callback=function(v) plantGap=v end })
PlantSub:AddSlider({ Name="Grid Spacing", Min=1.5, Max=4, Default=2, Suffix=" studs", Flag="plant_spacing", Callback=function(v) plantSpacing=v end })

local function applyPlantSeeds(sel) plantSelectedSeeds = sel or {} end
local plantSeedDropdown = PlantSub:AddMultiDropdown({
    Name="Seeds to Plant", Options=GetBackpackSeedNames(), Default={},
    MaxVisible=6, Searchable=true, Flag="plant_seeds",
    Callback=applyPlantSeeds,
})
registerResync(plantSeedDropdown, applyPlantSeeds)
PlantSub:AddButton({
    Name="Refresh Seed List",
    Callback=function()
        plantSeedDropdown:SetOptions(GetBackpackSeedNames())
        local total = GetTotalSeedCount(GetPlantFilter())
        Window:Notify({Title="Auto Plant", Content=("%d seed(s) ready"):format(total), Type="Info", Duration=2})
    end,
})
PlantSub:AddButton({
    Name = "Show Free Spots", 
    Callback = function()
        local plot = FindMyPlot()
        if not plot then
            Window:Notify({Title="Auto Plant", Content="Could not find your plot.", Type="Error", Duration=2})
            return
        end
        local spots = GeneratePlantSpots(plot, plantSpacing)
        local seeds = GetTotalSeedCount(GetPlantFilter())
        Window:Notify({
            Title = "Auto Plant",
            Content = ("%d free spot(s) | %d seed(s) available"):format(#spots, seeds),
            Type = "Info", Duration = 4,
        })
    end,
})
PlantSub:AddButton({
    Name="Fill Garden Once", Primary=true,
    Callback=function()
        if plantTpPlot then
            local plot = FindMyPlot()
            local areas = plot and GetVisiblePlantAreas(plot)
            if areas and areas[1] then TeleportTo(areas[1].Position) task.wait(0.2) end
        end
        local planted, reason = RunPlantCycle(GetPlantFilter(), plantSpacing, plantGap, plantEquip, nil)
        plantPlantedCount += planted
        local msg, kind = PlantStatusMessage(planted, reason)
        Window:Notify({Title="Auto Plant", Content=msg, Type=kind, Duration=3})
    end,
})

task.spawn(function()
    while true do
        if autoPlant then
            if plantTpPlot then
                local plot = FindMyPlot()
                if plot then
                    local areas = GetVisiblePlantAreas(plot)
                    if areas[1] then TeleportTo(areas[1].Position) task.wait(0.15) end
                end
            end
            local planted, reason = RunPlantCycle(GetPlantFilter(), plantSpacing, plantGap, plantEquip, nil)
            if planted > 0 then
                plantPlantedCount += planted
            elseif plantFailNotify and reason and reason ~= "ok" and (tick() - lastPlantFailAt) > 20 then
                lastPlantFailAt = tick()
                local msg = PlantStatusMessage(0, reason)
                Window:Notify({Title="Auto Plant", Content=msg, Type="Info", Duration=3})
            end
        end
        task.wait(plantDelay)
    end
end)

-- ── AUTO WATER ────────────────────────────────────────────────────────────────
local WaterSub = AutoTab:AddSubTab("Auto Water")
local autoWater = false
local waterDelay = 1
local waterGap = 0.55
local waterMode = "Plant Positions"
local waterOnlyRipe = false
local waterCount = 0

WaterSub:AddToggle({
    Name = "Auto Water", Default = false, Flag = "water_auto",
    Callback = function(v)
        autoWater = v
        if v then waterCount = 0 end
        Window:Notify({Title="Auto Water", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
WaterSub:AddSlider({ Name="Cycle Delay", Min=0.2, Max=15, Default=1, Suffix="s", Flag="water_cycle", Callback=function(v) waterDelay=v end })
WaterSub:AddSlider({ Name="Water Gap", Min=0.5, Max=3, Default=0.55, Suffix="s", Flag="water_gap", Callback=function(v) waterGap=v end })
local function applyWaterMode(v) waterMode = v end
local waterModeDropdown = WaterSub:AddDropdown({
    Name="Water Mode", Options={"Plant Positions","Full Plot Grid","Ripe Plants Only"}, Default="Plant Positions",
    MaxVisible=3, Flag="water_mode", Callback=applyWaterMode,
})
registerResync(waterModeDropdown, applyWaterMode)
WaterSub:AddToggle({
    Name="Skip Fully Grown", Default=false, Flag="water_skipripe",
    Description="Only water plants that haven't reached MaxAge yet",
    Callback=function(v) waterOnlyRipe = v end,
})
WaterSub:AddButton({
    Name="Water Once (Test)", Primary=true,
    Callback=function()
        local tool, canName = FindWateringCan()
        if not tool then
            Window:Notify({Title="Auto Water", Content="Equip a watering can first!", Type="Error", Duration=3})
            return
        end
        local plot = FindMyPlot()
        if not plot then
            Window:Notify({Title="Auto Water", Content="Could not find your plot.", Type="Error", Duration=2})
            return
        end
        local targets = {}
        if waterMode == "Full Plot Grid" then
            for _, spot in ipairs(GeneratePlantSpots(plot, 3)) do table.insert(targets, spot.position) end
        else
            for _, p in ipairs(GetMyPlants(plot)) do
                if waterMode == "Ripe Plants Only" then
                    if typeof(p.age) == "number" and typeof(p.maxAge) == "number" and p.age >= p.maxAge then
                        table.insert(targets, p.position)
                    end
                elseif waterOnlyRipe then
                    if typeof(p.maxAge) ~= "number" or typeof(p.age) ~= "number" or p.age < p.maxAge then
                        table.insert(targets, p.position)
                    end
                else
                    table.insert(targets, p.position)
                end
            end
        end
        local watered = 0
        for _, pos in ipairs(targets) do
            if WaterDirect(pos, canName, tool) then watered += 1 end
            task.wait(waterGap)
        end
        Window:Notify({Title="Auto Water", Content=("Watered %d spot(s)"):format(watered), Type=watered > 0 and "Success" or "Info", Duration=3})
    end,
})

task.spawn(function()
    while true do
        if autoWater then
            local tool, canName = FindWateringCan()
            local plot = FindMyPlot()
            if tool and plot then
                local targets = {}
                if waterMode == "Full Plot Grid" then
                    for _, spot in ipairs(GeneratePlantSpots(plot, 3)) do table.insert(targets, spot.position) end
                else
                    for _, p in ipairs(GetMyPlants(plot)) do
                        if waterMode == "Ripe Plants Only" then
                            if typeof(p.age) == "number" and typeof(p.maxAge) == "number" and p.age >= p.maxAge then
                                table.insert(targets, p.position)
                            end
                        elseif waterOnlyRipe then
                            if typeof(p.maxAge) ~= "number" or typeof(p.age) ~= "number" or p.age < p.maxAge then
                                table.insert(targets, p.position)
                            end
                        else
                            table.insert(targets, p.position)
                        end
                    end
                end
                for _, pos in ipairs(targets) do
                    if not autoWater then break end
                    if WaterDirect(pos, canName, tool) then waterCount += 1 end
                    task.wait(waterGap)
                end
            end
        end
        task.wait(waterDelay)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- AUTO STEAL
-- ══════════════════════════════════════════════════════════════════════════════
local StealSub = AutoTab:AddSubTab("Auto Steal")

local autoSteal=false; local stealDelay=0.2; local stealGap=0.03
local stealFilter="All"; local stealMutation="All"; local antiAFKLoop=true
local skipEmptyPlots=true; local smartSort=true
local stealRipeOnly=true; local requireNight=true
local notifyOwnerLeft=true; local notifyNotNight=true
local teleportMode=false; local tpReturnDelay=0.1; local tpReturnAfterAll=false
local stealCount=0

local plotsBlockedByOwner={}
local plotOwners={}; local plotReturnPositions={}
local cachedMyPlot=nil; local cachedMyCenter=nil; local lastPlotCheck=0
local lastStealCooldowns={}

local function GetPlotOwnerId(plot)
    if plotOwners[plot] then return plotOwners[plot] end
    local plants = plot:FindFirstChild("Plants")
    if not plants then return nil end
    for _, p in ipairs(plants:GetChildren()) do
        local uid = p:GetAttribute("UserId")
        if uid then plotOwners[plot] = uid; return uid end
    end
    return nil
end

local function GetGardenZone(plot)
    for _, d in ipairs(plot:GetDescendants()) do
        if d.Name == "GardenZonePart" and d:IsA("BasePart") then return d end
    end
    return nil
end

local function IsPositionInZone(pos, zonePart)
    if not zonePart or not zonePart:IsA("BasePart") then return false end
    local rel = zonePart.CFrame:PointToObjectSpace(pos)
    local hs = zonePart.Size / 2
    return math.abs(rel.X) <= hs.X and math.abs(rel.Y) <= hs.Y and math.abs(rel.Z) <= hs.Z
end

local function IsOwnerOnPlot(plot)
    local ownerId = GetPlotOwnerId(plot)
    if not ownerId or ownerId == UserId then return false end
    local owner = Players:GetPlayerByUserId(ownerId)
    if not owner or not owner.Character then return false end
    local hrp = owner.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local zone = GetGardenZone(plot)
    if not zone then return false end
    return IsPositionInZone(hrp.Position, zone)
end

local function GetMyPlotCenter()
    if cachedMyCenter and (tick() - lastPlotCheck) < 10 then return cachedMyCenter end
    cachedMyPlot = FindMyPlot()
    lastPlotCheck = tick()
    if not cachedMyPlot then cachedMyCenter=nil; return nil end
    if plotReturnPositions[cachedMyPlot] then
        cachedMyCenter = plotReturnPositions[cachedMyPlot]; return cachedMyCenter
    end
    local zone = GetGardenZone(cachedMyPlot)
    if zone then
        plotReturnPositions[cachedMyPlot] = zone.Position
        cachedMyCenter = zone.Position; return cachedMyCenter
    end
    for _, d in ipairs(cachedMyPlot:GetDescendants()) do
        if d:IsA("BasePart") then
            plotReturnPositions[cachedMyPlot] = d.Position
            cachedMyCenter = d.Position; return cachedMyCenter
        end
    end
    return nil
end

task.spawn(function()
    while true do
        local gardens = workspace:FindFirstChild("Gardens")
        if gardens then
            for _, plot in ipairs(gardens:GetChildren()) do
                local plants = plot:FindFirstChild("Plants")
                if plants and #plants:GetChildren() > 0 then
                    local was = plotsBlockedByOwner[plot]
                    local now = IsOwnerOnPlot(plot)
                    plotsBlockedByOwner[plot] = now
                    if was and not now and notifyOwnerLeft and autoSteal then
                        local oid = plotOwners[plot]; local oname = "?"
                        if oid then local p = Players:GetPlayerByUserId(oid); if p then oname = p.DisplayName end end
                        Window:Notify({Title="Plot Open!", Content=oname.." left their plot!", Type="Success", Duration=3})
                    end
                end
            end
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while true do
        task.wait(30)
        for plot, _ in pairs(plotsBlockedByOwner) do
            if not plot.Parent then
                plotsBlockedByOwner[plot]=nil
                plotOwners[plot]=nil
                plotReturnPositions[plot]=nil
            end
        end
        local now = tick()
        for key, t in pairs(lastStealCooldowns) do
            if now - t > 60 then lastStealCooldowns[key] = nil end
        end
    end
end)

local function FireStealTarget(data)
    if not data.model or not data.model.Parent then return false end
    if not IsPlantStealable(data.fruitName) then return false end

    if requireNight and not IsNight() then
        if notifyNotNight and autoSteal then
            notifyNotNight = false
            Window:Notify({Title="Steal", Content="Stealing only works at night!", Type="Error", Duration=3})
            task.delay(30, function() notifyNotNight = true end)
        end
        return false
    end

    local key = ("%d_%s_%s"):format(data.ownerUserId, data.plantId, data.fruitId)
    if lastStealCooldowns[key] and (tick() - lastStealCooldowns[key]) < 1.5 then
        return false
    end

    local success = false
    if teleportMode and data.position then
        TeleportTo(data.position)
        task.wait(0.05)
    end

    success = StealFruitDirect(data.ownerUserId, data.plantId, data.fruitId)

    if success then
        lastStealCooldowns[key] = tick()
        stealCount += 1
        if teleportMode and not tpReturnAfterAll then
            task.wait(tpReturnDelay)
            local rp = GetMyPlotCenter()
            if rp then TeleportTo(rp) end
        end
    end
    return success
end

StealSub:AddToggle({
    Name="Auto Steal", Default=false, Flag="steal_auto",
    Callback=function(v)
        autoSteal = v
        if v then stealCount=0 end
        Window:Notify({Title="Auto Steal", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
StealSub:AddToggle({ Name="Require Night", Default=true, Flag="steal_night", Callback=function(v) requireNight=v end })
StealSub:AddToggle({ Name="Only Ripe Fruit", Default=true, Flag="steal_ripe", Callback=function(v) stealRipeOnly=v end })
StealSub:AddToggle({ Name="Teleport Mode", Default=false, Flag="steal_tp", Callback=function(v) teleportMode=v end })
StealSub:AddToggle({ Name="Return After Cycle", Default=false, Flag="steal_return", Callback=function(v) tpReturnAfterAll=v end })
StealSub:AddSlider({ Name="TP Return Delay", Min=0.05, Max=2, Default=0.1, Suffix="s", Flag="steal_tpdelay", Callback=function(v) tpReturnDelay=v end })
StealSub:AddSlider({ Name="Cycle Delay", Min=0.1, Max=10, Default=0.2, Suffix="s", Flag="steal_cycle", Callback=function(v) stealDelay=v end })
StealSub:AddSlider({ Name="Steal Gap", Min=0.01, Max=1, Default=0.03, Suffix="s", Flag="steal_gap", Callback=function(v) stealGap=v end })

local function applyStealMut(v) stealMutation=v end
local stealMutDropdown = StealSub:AddDropdown({
    Name="Mutation Filter", Options=GetAllMutations(), Default="All", MaxVisible=5, Searchable=true, Flag="steal_mutation",
    Callback=applyStealMut,
})
registerResync(stealMutDropdown, applyStealMut)
local function applyStealFruit(v) stealFilter=v end
local stealFruitDropdown = StealSub:AddDropdown({
    Name="Fruit Filter", Options=GetAllFruitTypes(), Default="All", MaxVisible=5, Searchable=true, Flag="steal_fruit",
    Callback=applyStealFruit,
})
registerResync(stealFruitDropdown, applyStealFruit)
StealSub:AddButton({
    Name="Refresh Lists",
    Callback=function()
        stealMutDropdown:SetOptions(GetAllMutations())
        stealFruitDropdown:SetOptions(GetAllFruitTypes())
        Window:Notify({Title="Refreshed", Content="Lists updated.", Type="Info", Duration=2})
    end,
})

StealSub:AddToggle({ Name="Notify When Owner Leaves", Default=true, Flag="steal_notifyleave", Callback=function(v) notifyOwnerLeft=v end })
StealSub:AddToggle({ Name="Smart Sort (Mutations)", Default=true, Flag="steal_smartsort", Callback=function(v) smartSort=v end })
StealSub:AddToggle({ Name="Skip Empty Plots", Default=true, Flag="steal_skipempty", Callback=function(v) skipEmptyPlots=v end })
StealSub:AddToggle({ Name="Anti-AFK", Default=true, Flag="steal_antiafk", Callback=function(v) antiAFKLoop=v end })

if not _G.MSSAntiAFKConnected then
    _G.MSSAntiAFKConnected = true
    LocalPlayer.Idled:Connect(function()
        if antiAFKLoop then
            local VU = game:GetService("VirtualUser")
            VU:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            VU:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end
    end)
end

task.spawn(function()
    while true do
        if autoSteal then
            local targets = ScanGardenFruits({
                skipMy = true,
                skipBlocked = true,
                skipEmpty = skipEmptyPlots,
                fruitFilter = stealFilter,
                mutationFilter = stealMutation,
                ripeOnly = stealRipeOnly,
                smartSort = smartSort,
            })
            local didTP = false
            for _, data in ipairs(targets) do
                if not autoSteal then break end
                if data.isMine then continue end
                if FireStealTarget(data) then
                    if teleportMode then didTP = true end
                end
                task.wait(stealGap)
            end
            if teleportMode and tpReturnAfterAll and didTP then
                task.wait(tpReturnDelay)
                local rp = GetMyPlotCenter()
                if rp then TeleportTo(rp) end
            end
        end
        task.wait(stealDelay)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- AUTO CLAIM SEED PACK
-- ══════════════════════════════════════════════════════════════════════════════
local ClaimSub = AutoTab:AddSubTab("Auto Claim Seed")
local autoClaim=false; local claimDelay=0.5; local claimGap=0.1
local claimTeleport=true; local claimNotify=true
local returnAfter=true; local totalClaimed=0; local claimStartPos=nil
local claimedSpawns={}

local function GetActiveSeedPackSpawns()
    local spawns = {}
    local map = workspace:FindFirstChild("Map")
    if not map then return spawns end
    local serverFolder = map:FindFirstChild("SeedPackSpawnServerLocations")
    if serverFolder then
        for _, part in ipairs(serverFolder:GetChildren()) do
            if part.Parent then
                local pos = part:IsA("BasePart") and part.Position or GetModelPosition(part)
                local packName = part:GetAttribute("SeedPack")
                    or (part:GetAttribute("RainbowSeed") and "Rainbow Seed")
                    or (part:GetAttribute("GoldSeed") and "Gold Seed")
                    or (part:GetAttribute("MegaSeed") and "Mega Seed")
                    or "Seed Pack"
                table.insert(spawns, {
                    id = part:GetFullName(),
                    part = part,
                    position = pos,
                    name = packName,
                })
            end
        end
    end
    return spawns
end

ClaimSub:AddToggle({
    Name="Auto Claim Seed Packs", Default=false, Flag="claim_auto",
    Callback=function(v)
        autoClaim = v
        if v then local h=GetHRP(); if h then claimStartPos=h.Position end end
        Window:Notify({Title="Auto Claim", Content=v and "ON" or "OFF", Type=v and "Success" or "Error", Duration=2})
    end,
})
ClaimSub:AddSlider({ Name="Cycle Delay", Min=0.1, Max=10, Default=0.5, Suffix="s", Flag="claim_cycle", Callback=function(v) claimDelay=v end })
ClaimSub:AddSlider({ Name="Claim Gap", Min=0.05, Max=2, Default=0.1, Suffix="s", Flag="claim_gap", Callback=function(v) claimGap=v end })
ClaimSub:AddToggle({ Name="Teleport to Spawn", Default=true, Flag="claim_tp", Callback=function(v) claimTeleport=v end })
ClaimSub:AddToggle({ Name="Return After Claim", Default=true, Flag="claim_return", Callback=function(v) returnAfter=v end })
ClaimSub:AddToggle({ Name="Notify on Claim", Default=true, Flag="claim_notify", Callback=function(v) claimNotify=v end })

local mapFolder = workspace:FindFirstChild("Map")
if mapFolder then
    local serverLocs = mapFolder:FindFirstChild("SeedPackSpawnServerLocations")
    if serverLocs then
        serverLocs.ChildAdded:Connect(function(child)
            if autoClaim and claimNotify then
                Window:Notify({Title="Seed Pack Spawned!", Content=child:GetAttribute("SeedPack") or "Special Seed", Type="Success", Duration=4})
            end
        end)
    end
end

task.spawn(function()
    while true do
        if autoClaim then
            local spawns = GetActiveSeedPackSpawns()
            if #spawns > 0 then
                local hrp = GetHRP()
                if hrp and not claimStartPos then claimStartPos=hrp.Position end
                for _, s in ipairs(spawns) do
                    if not autoClaim then break end
                    if claimedSpawns[s.id] then continue end
                    if claimTeleport and s.position then
                        TeleportTo(s.position)
                        task.wait(0.15)
                    end
                    claimedSpawns[s.id] = tick()
                    totalClaimed += 1
                    if claimNotify then
                        Window:Notify({Title="Seed Pack", Content=("Claimed: %s (Total: %d)"):format(s.name, totalClaimed), Type="Success", Duration=2})
                    end
                    task.wait(claimGap)
                end
                if returnAfter and claimStartPos then TeleportTo(claimStartPos) end
            end
        end
        task.wait(claimDelay)
    end
end)

task.spawn(function()
    while true do
        task.wait(60)
        local now = tick()
        for id, t in pairs(claimedSpawns) do
            if now - t > 120 then claimedSpawns[id] = nil end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- BUY TAB
-- ══════════════════════════════════════════════════════════════════════════════
local BuyTab = Window:AddTab({ Name = "Buy", Subtitle = "Shop", Icon = "coin" })

local function SetupBuySub(sub, shopName, buyFn, label)
    local autoBuy = false
    local buyDelay = 1
    local buyGap = 0.08
    local selected = {}
    local buyMode = "Buy All"
    local itemList = GetShopItems(shopName)

    local function applySelected(sel) selected = sel or {} end
    local dropdown = sub:AddMultiDropdown({
        Name = "Select " .. label .. "s",
        Options = itemList,
        Default = {},
        MaxVisible = 6,
        Searchable = true,
        Flag = "buy_" .. shopName .. "_items",
        Callback = applySelected,
    })
    registerResync(dropdown, applySelected)
    sub:AddButton({
        Name = "Refresh Shop List",
        Callback = function()
            itemList = GetShopItems(shopName)
            dropdown:SetOptions(itemList)
            Window:Notify({Title = label .. " Shop", Content = #itemList .. " items", Type = "Info", Duration = 3})
        end,
    })
    local function applyMode(v) buyMode = v end
    local modeDropdown = sub:AddDropdown({
        Name = "Buy Mode",
        Options = {"Buy All", "Buy 1 Each", "Round Robin"},
        Default = "Buy All",
        MaxVisible = 3,
        Flag = "buy_" .. shopName .. "_mode",
        Callback = applyMode,
    })
    registerResync(modeDropdown, applyMode)
    sub:AddSlider({ Name = "Cycle Delay", Min = 0.1, Max = 10, Default = 1, Suffix = "s", Flag = "buy_" .. shopName .. "_delay", Callback = function(v) buyDelay = v end })
    sub:AddSlider({ Name = "Buy Gap", Min = 0.02, Max = 2, Default = 0.08, Suffix = "s", Flag = "buy_" .. shopName .. "_gap", Callback = function(v) buyGap = v end })
    sub:AddToggle({
        Name = "Auto Buy " .. label .. "s",
        Default = false,
        Flag = "buy_" .. shopName .. "_enabled",
        Callback = function(v)
            autoBuy = v
            local summary = #selected > 0 and (#selected .. " selected") or "nothing selected"
            Window:Notify({Title = "Auto Buy", Content = v and ("Buying: " .. summary) or "OFF", Type = v and "Success" or "Error", Duration = 2})
        end,
    })
    sub:AddButton({
        Name = "Buy Once (Test)",
        Primary = true,
        Callback = function()
            if #selected == 0 then
                Window:Notify({Title = "Buy", Content = "Select at least one item.", Type = "Error", Duration = 2})
                return
            end
            for _, item in ipairs(selected) do
                buyFn(item)
                task.wait(buyGap)
            end
            Window:Notify({Title = "Buy", Content = ("Bought %d item(s)"):format(#selected), Type = "Info", Duration = 2})
        end,
    })

    local rrIndex = 1
    task.spawn(function()
        while true do
            if autoBuy and #selected > 0 then
                if buyMode == "Buy All" then
                    for _, item in ipairs(selected) do
                        if not autoBuy then break end
                        for _ = 1, 30 do
                            if not autoBuy then break end
                            buyFn(item)
                            task.wait(buyGap)
                        end
                    end
                elseif buyMode == "Buy 1 Each" then
                    for _, item in ipairs(selected) do
                        if not autoBuy then break end
                        buyFn(item)
                        task.wait(buyGap)
                    end
                else
                    local item = selected[rrIndex]
                    if item then
                        buyFn(item)
                        rrIndex = (rrIndex % #selected) + 1
                    end
                end
            end
            task.wait(buyDelay)
        end
    end)

    local stock = ReplicatedStorage:FindFirstChild("StockValues")
    if stock then
        local shop = stock:FindFirstChild(shopName)
        if shop and shop:FindFirstChild("Items") then
            shop.Items.ChildAdded:Connect(function()
                itemList = GetShopItems(shopName)
                dropdown:SetOptions(itemList)
            end)
        end
    end

    return #itemList
end

local seedCount = SetupBuySub(BuyTab:AddSubTab("Buy Seeds"), "SeedShop", BuySeed, "Seed")
local gearCount = SetupBuySub(BuyTab:AddSubTab("Buy Gears & Tools"), "GearShop", BuyGear, "Gear")
local crateCount = SetupBuySub(BuyTab:AddSubTab("Buy Crates"), "CrateShop", BuyCrate, "Crate")

-- ── AUTO OPEN CRATES ──────────────────────────────────────────────────────────
local OpenSub = BuyTab:AddSubTab("Open Crates")
local autoOpenCrates = false
local openDelay = 1
local openGap = 0.3
local openCount = 0

OpenSub:AddToggle({
    Name = "Auto Open Crates", Default = false, Flag = "crate_open_auto",
    Callback = function(v)
        autoOpenCrates = v
        if v then openCount = 0 end
        Window:Notify({Title = "Auto Open", Content = v and "ON" or "OFF", Type = v and "Success" or "Error", Duration = 2})
    end,
})
OpenSub:AddSlider({ Name = "Cycle Delay", Min = 0.2, Max = 10, Default = 1, Suffix = "s", Flag = "crate_open_cycle", Callback = function(v) openDelay = v end })
OpenSub:AddSlider({ Name = "Open Gap", Min = 0.1, Max = 3, Default = 0.3, Suffix = "s", Flag = "crate_open_gap", Callback = function(v) openGap = v end })
OpenSub:AddButton({
    Name = "Open All Crates Now", Primary = true,
    Callback = function()
        local crates = GetBackpackCrates()
        local opened = 0
        for _, c in ipairs(crates) do
            if OpenCrateDirect(c.id) then opened += 1 end
            task.wait(openGap)
        end
        Window:Notify({Title = "Open Crates", Content = ("Opened %d crate(s)"):format(opened), Type = opened > 0 and "Success" or "Info", Duration = 3})
    end,
})

task.spawn(function()
    while true do
        if autoOpenCrates then
            for _, c in ipairs(GetBackpackCrates()) do
                if not autoOpenCrates then break end
                if OpenCrateDirect(c.id) then openCount += 1 end
                task.wait(openGap)
            end
        end
        task.wait(openDelay)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- MISC TAB
-- ══════════════════════════════════════════════════════════════════════════════
local MiscTab = Window:AddTab({ Name = "Misc", Subtitle = "Garden", Icon = "home" })
local GardenSub = MiscTab:AddSubTab("Garden")

GardenSub:AddButton({
    Name = "Expand Garden", Primary = true,
    Callback = function()
        ExpandGarden()
        Window:Notify({Title="Garden", Content="Expand request sent!", Type="Success", Duration=2})
    end,
})
GardenSub:AddButton({
    Name = "Sync Gardens",
    Callback = function()
        pcall(function() Networking.Garden.RequestGardens:Fire() end)
        Window:Notify({Title="Garden", Content="Garden sync requested.", Type="Info", Duration=2})
    end,
})
GardenSub:AddButton({
    Name = "Teleport to My Plot",
    Callback = function()
        local center = GetMyPlotCenter()
        if center then
            TeleportTo(center)
            Window:Notify({Title="Teleport", Content="Teleported to your plot.", Type="Success", Duration=2})
        else
            Window:Notify({Title="Teleport", Content="Could not find your plot.", Type="Error", Duration=2})
        end
    end,
})

local InfoSub = MiscTab:AddSubTab("Info")
InfoSub:AddButton({
    Name = "Show Game Status",
    Callback = function()
        local plot = FindMyPlot()
        local preview = PreviewSell()
        local sellVal = preview and (preview.TotalSellValue or preview.TotalValue or 0) or "?"
        Window:Notify({
            Title = "GAG2 Status",
            Content = ("Plot: %s | Night: %s | Sell: %s | Steals: %d | Planted: %d | Watered: %d | Crates: %d"):format(
                plot and plot.Name or "?",
                IsNight() and "Yes" or "No",
                tostring(sellVal),
                stealCount,
                plantPlantedCount,
                waterCount,
                openCount
            ),
            Type = "Info", Duration = 6,
        })
    end,
})

-- ══════════════════════════════════════════════════════════════════════════════
-- SETTINGS TAB (config save / load via MSS UI flag system)
-- ══════════════════════════════════════════════════════════════════════════════
local SettingsTab = Window:AddTab({ Name = "Settings", Subtitle = "Configuration", Icon = "settings" })
local CfgSub = SettingsTab:AddSubTab("Config")

CfgSub:AddParagraph({
    Title = "Configs",
    Text = "Save and restore every toggle, slider and dropdown across sessions. Configs are stored on disk by your executor.",
})

local cfgNameInput = CfgSub:AddInput({
    Name = "Config Name", Placeholder = "gag2", Default = CONFIG_NAME,
    Callback = function(t) if t and t ~= "" then CONFIG_NAME = t end end,
})

if HAS_CONFIG then
    CfgSub:AddSection("Manage")

    local cfgListDropdown
    cfgListDropdown = CfgSub:AddDropdown({
        Name = "Saved Configs", Options = Library:ListConfigs(), MaxVisible = 5, Searchable = true,
        Callback = function(v)
            if v and v ~= "" then
                CONFIG_NAME = v
                if cfgNameInput then cfgNameInput:Set(v) end
            end
        end,
    })

    CfgSub:AddButton({
        Name = "Save Config", Primary = true,
        Callback = function()
            local ok = Library:SaveConfig(CONFIG_NAME)
            if cfgListDropdown then cfgListDropdown:SetOptions(Library:ListConfigs()) end
            Window:Notify({Title="Config", Content=ok and ("Saved '"..CONFIG_NAME.."'") or "Save failed", Type=ok and "Success" or "Error", Duration=3})
        end,
    })
    CfgSub:AddButton({
        Name = "Load Config",
        Callback = function()
            local ok = Library:LoadConfig(CONFIG_NAME)
            if ok then ResyncAll() end
            Window:Notify({Title="Config", Content=ok and ("Loaded '"..CONFIG_NAME.."'") or "Config not found", Type=ok and "Success" or "Error", Duration=3})
        end,
    })
    CfgSub:AddButton({
        Name = "Refresh List",
        Callback = function()
            if cfgListDropdown then cfgListDropdown:SetOptions(Library:ListConfigs()) end
            Window:Notify({Title="Config", Content="List refreshed.", Type="Info", Duration=2})
        end,
    })
    CfgSub:AddButton({
        Name = "Delete Config",
        Callback = function()
            local ok = type(Library.DeleteConfig) == "function" and Library:DeleteConfig(CONFIG_NAME)
            if cfgListDropdown then cfgListDropdown:SetOptions(Library:ListConfigs()) end
            Window:Notify({Title="Config", Content=ok and ("Deleted '"..CONFIG_NAME.."'") or "Delete failed", Type=ok and "Success" or "Error", Duration=3})
        end,
    })

    -- Auto-load the default config on startup once every element/flag is registered.
    task.defer(function()
        for _, name in ipairs(Library:ListConfigs()) do
            if name == CONFIG_NAME then
                if Library:LoadConfig(CONFIG_NAME) then
                    ResyncAll()
                    Window:Notify({Title="Config", Content="Loaded saved settings.", Type="Info", Duration=3})
                end
                break
            end
        end
    end)
else
    CfgSub:AddParagraph({
        Title = "Saving Unavailable",
        Text = "The loaded MSS UI build does not support config saving. Update the library to v2.3+ to enable it.",
    })
end

task.delay(2.5, function()
    local plot = FindMyPlot()
    Window:Notify({
        Title = "MSS HUB v30",
        Content = ("Plot: %s | Seeds: %d | Gears: %d | Crates: %d\nAuto Plant v2 — equip + grid fill"):format(
            plot and plot.Name or "?", seedCount, gearCount, crateCount),
        Type = "Success", Duration = 6,
    })
end)

print("[MSS HUB v30] Loaded — GAG2 auto plant v2 + multi-select buy shops")
