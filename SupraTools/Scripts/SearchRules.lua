local UEHelpers = require("UEHelpers")

local rules = {}
rules.categories = {
    {id="pages", label="Страницы", color={R=0,G=1,B=1,A=0.85}, classes={"Pickup_SolversGuidePage_C","Pickup_SolversGuidePage_Combined_C"}},
    {id="secrets", label="Секреты", color={R=0.2,G=1,B=0.3,A=0.85}, classes={"SecretVolume_C"}},
    {id="coins", label="Монеты", color={R=1,G=0.75,B=0.1,A=0.85}, classes={"RealCoinPickup_C"}},
    {id="chests", label="Сундуки / подарки", color={R=1,G=0.25,B=0.3,A=0.85}, classes={"PresentBox_C","PresentBox_Lootpools_C"}},
    {id="chips", label="Чипы способностей", color={R=1,G=0,B=0,A=0.85}, classes={"ShopItemChip_C"}},
    {id="abilities", label="Яйца", color={R=0.65,G=0.15,B=1,A=0.85}, classes={"ChocolateEgg_C","ShopEgg_C"}},
    {id="cards", label="Игральные карты", color={R=1,G=0.2,B=0.65,A=0.85}, classes={"Pickup_Card_C"}},
}
rules.enabled = {pages=true,secrets=true,coins=true,chests=true,chips=true,abilities=false,cards=true}
rules.classCategory = {}
for _,category in ipairs(rules.categories) do
    for _,class in ipairs(category.classes) do rules.classCategory[class]=category.id end
end
rules.classCategory.ItemSpawner_C="chests"
rules.classCategory.PickupSpawner_C="chests"
local picked = {}
local observedRewards = {}
function rules.mark(name) picked[name] = true end
function rules.wasPicked(name) return picked[name]==true end
local function flag(actor, name)
    local ok,value=pcall(function() return actor[name] end)
    return ok and value==true
end
local function valid(actor)
    local ok,value=pcall(function() return actor and actor:IsValid() end)
    return ok and value==true
end
local function property(actor,name)
    local ok,value=pcall(function() return actor[name] end)
    return ok and value or nil
end
local function taken(actor)
    if not valid(actor) then return false end
    if picked[actor:GetFullName()] then return true end
    for _,name in ipairs({'bPickedUp','bFound','bItemIsTaken','IsOpen','bEggIsCut',
        'ChocolateMeltedOpen','bHidden','Pickup has been collected'}) do
        if flag(actor,name) then return true end
    end
    local ok,hidden=pcall(function() return actor:IsHidden() end)
    if ok and hidden==true then return true end
    return false
end
local function saveString(value)
    return string.pack("<I4", #value + 1) .. value .. "\0"
end

local mapTag = saveString("Values") .. saveString("MapProperty") .. string.pack("<I4", 2)
    .. saveString("NameProperty") .. string.pack("<I4", 0)
    .. saveString("StructProperty") .. string.pack("<I4", 1)
    .. saveString("AnyValue") .. string.pack("<I4", 1)
    .. saveString("/Script/AnyValue") .. string.pack("<I4", 0)
local boolTag = "\1" .. saveString("/Script/AnyValue.SingleValueStruct_Bool")
    .. saveString("Value") .. saveString("BoolProperty") .. string.rep("\0", 8)
local absentTag = saveString("Exists") .. boolTag .. "\0" .. saveString("None")
local chipTakenTag = saveString("ItemIsTaken") .. boolTag .. "\16" .. saveString("None")

local function eggSaveKey(name)
    -- The UAID identifies the placed actor. The numeric suffix can be
    -- regenerated when a level instance is loaded.
    return name:match("^([%w_]+_UAID_%x+)_?%d*$") or name
end

local function readRemovedEggs(data)
    local removed = {}
    if data:sub(1, 4) ~= "GVAS" then return removed end
    for _, class in ipairs({"ShopEgg_C", "ChocolateEgg_C", "ShopItemChip_C"}) do
        local flag = class == "ShopItemChip_C" and chipTakenTag or absentTag
        local cursor = 1
        while true do
            local first, last, name = data:find("PersistentLevel%.(" .. class .. "_[%w_]+)", cursor)
            if not first then break end
            cursor = last + 1
            local sizePos = cursor + #mapTag
            if first > 4 and sizePos + 4 <= #data
                and string.unpack("<I4", data, first - 4) == last - first + 1
                and data:sub(cursor, sizePos - 1) == mapTag and data:byte(sizePos + 4) == 8 then
                local size = string.unpack("<I4", data, sizePos)
                local start = sizePos + 5
                if size <= #data - start + 1 then
                    local values = data:sub(start, start + size - 1)
                    if values:find(flag, 1, true) then removed[eggSaveKey(name)] = true end
                    cursor = start + size
                end
            end
        end
    end
    return removed
end

local function currentEggSave(root)
    local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local class = StaticFindObject("/Script/DynamicSave.DynamicSaveSubsystem")
    if not valid(library) or not valid(class) then return end
    local subsystem = library:GetGameInstanceSubsystem(UEHelpers.GetGameInstance(), class)
    if not valid(subsystem) then return end

    local category = subsystem.CurrentSaveGameCategoryName:ToString()
    local slot = subsystem.CurrentSaveGameSlotName:ToString()
    local path = subsystem.CurrentSaveGameSlotPath:ToString():gsub("\\", "/")
    if path:sub(1, #root):lower() == root:lower() then path = path:sub(#root + 1) end
    path = path:gsub("^SaveGames/", ""):gsub("/+$", "")
    local fallback
    if category:match("^[%w_ %-]+$") and slot:match("^[%w_ %-]+$")
        and slot ~= "None" and category ~= "None" then
        fallback = root .. category .. "/" .. slot .. "/SaveGame.sav"
    end
    if (path:match("^[^:/]+/[^:/]+$") or path:match("^[^:/]+/[^:/]+/[^:/]+%.sav$"))
        and not path:find("..", 1, true) then
        if path:sub(-4):lower() ~= ".sav" then path = path .. "/SaveGame.sav" end
        return root .. path, fallback
    end
    return fallback
end

local removedEggs, lastSave, nextRead = {}, nil, 0
local saveWarningLogged = false
local saveStatus
local function refreshEggSave()
    local appData = os.getenv("LOCALAPPDATA")
    if not appData then return end
    local base = appData:gsub("\\", "/") .. "/Supraworld/"
    local root = base .. "Saved/SaveGames/"
    local ok, path, fallback = pcall(currentEggSave, root)
    if not ok then
        if not saveWarningLogged then
            print("Egg save lookup: " .. tostring(path))
            saveWarningLogged = true
        end
        path = nil
    end
    local now = os.time()
    if path == lastSave and now < nextRead then return end
    lastSave, nextRead = path, now + 5
    removedEggs = {}
    local configuredPath, confirmedEggs
    local config = io.open(base .. "SupraToolsEggSaveSlot.txt", "r")
    if config then
        local slot = config:read("*l")
        if slot and slot:match("^[%w_ %-]+/[%w_ %-]+$") then
            configuredPath = root .. slot .. "/SaveGame.sav"
            confirmedEggs = {}
            for name in config:lines() do
                if name:match("^ShopEgg_C_UAID_%x+_%d+$") then
                    confirmedEggs[eggSaveKey(name)] = true
                end
            end
        end
        config:close()
    end

    local savePath = path or configuredPath
    local file = savePath and io.open(savePath, "rb")
    if not file and fallback and fallback ~= savePath then
        savePath = fallback
        file = io.open(savePath, "rb")
    end
    local status = "active save unavailable"
    local source = path and "active slot" or "configured slot"
    if file then
        local data = file:read("*a")
        file:close()
        if data then
            removedEggs = readRemovedEggs(data)
            if configuredPath and savePath:lower() == configuredPath:lower() then
                for name in pairs(confirmedEggs) do removedEggs[name] = true end
            end
            local count = 0
            for _ in pairs(removedEggs) do count = count + 1 end
            status = count .. " saved egg/chip removals from " .. source
        end
    end
    if status ~= saveStatus then
        print("Egg filter: " .. status)
        saveStatus = status
    end
end

-- Only permanent unlocks are safe to deduplicate by ownership. Stackable
-- upgrades, coins and health pickups may appear in more than one egg.
local permanentRewards = {
    Inventory_Walk_C=true, Inventory_Run_C=true, Inventory_Jump_C=true,
    Inventory_Crouch_C=true, Inventory_JumpHeightDouble_C=true, Inventory_Strength_C=true,
    Inventory_BlowGun_C=true, Inventory_Dash_C=true, Inventory_Toothpick_C=true,
    Inventory_SolversGuide_C=true, Inventory_PlayerMap_C=true, Inventory_ThirdEye_C=true,
    Inventory_ThoughtReading_C=true, Inventory_MindVision_C=true, Inventory_SpongeSuit_C=true,
    Inventory_LanguageFabric_C=true, Inventory_SeeEnemyHealth_C=true, Inventory_CoinMagnet_C=true,
}
local inventory
local ownedRewards = {}

local function refreshEggInventory()
    inventory, ownedRewards = nil, {}
    local ok, component = pcall(function()
        local pc = UEHelpers.GetPlayerController()
        local class = StaticFindObject("/Script/LyraGame.LyraInventoryManagerComponent")
        if not valid(pc) or not valid(class) then return end
        local components = pc:K2_GetComponentsByClass(class)
        if #components > 0 then return components[1]:get() end
    end)
    if ok and valid(component) then inventory = component end
end

local function eggRewardPath(actor)
    -- Read only the asset FName, avoiding the unsupported UTF-8 subpath.
    local ref = actor.InventoryItem
    if not ref then return end
    return ref:GetObjectID():GetAssetPathName():ToString()
end

local function ownsEggReward(actor)
    if not valid(inventory) then return false end
    local path = eggRewardPath(actor)
    if not path then return false end
    local name = path:match("^/Supraworld/Abilities/.+%.([%w_]+)$")
    if not name or not permanentRewards[name] then return false end
    if ownedRewards[path] == nil then
        local definition = StaticFindObject(path)
        ownedRewards[path] = valid(definition) and valid(inventory:FindFirstItemStackByDefinition(definition))
    end
    return ownedRewards[path]
end

local function eggRewardCollected(actor)
    local ok,collected=pcall(function()
        local class=actor:GetClass():GetFName():ToString()
        if class ~= "ChocolateEgg_C" and class ~= "ShopEgg_C" then return false end
        if removedEggs[eggSaveKey(actor:GetFName():ToString())] then return true end
        if class=="ChocolateEgg_C" then
            local egg=property(actor,'ToyEgg')
            if valid(egg) then return taken(egg) or eggRewardCollected(egg) end
        elseif class=="ShopEgg_C" then
            if actor.bEggIsCut==true then return true end
            local ownedOK, owned = pcall(ownsEggReward, actor)
            if ownedOK and owned then return true end
            local reward=property(actor,'SpawnedShopItem')
            local name=actor:GetFullName()
            if valid(reward) then
                observedRewards[name]=reward
                return taken(reward)
            end
            -- Never interpret an initially empty reward slot as collected.
            -- A reward observed alive and subsequently destroyed is completed.
            local previous=observedRewards[name]
            if previous and not valid(previous) then return true end
        end
        return false
    end)
    return ok and collected==true
end
function rules.isCollected(actor)
    if not actor or not actor:IsValid() then return true end
    if taken(actor) then return true end
    local class = actor:GetClass():GetFName():ToString()
    if class == "ShopItemChip_C" then
        return removedEggs[eggSaveKey(actor:GetFName():ToString())] == true
            or flag(actor, "ItemIsTaken")
    end
    return eggRewardCollected(actor)
end
local eggLocations={}
local wrappedEggs={}

function rules.isWrappedEgg(actor)
    return wrappedEggs[actor:GetFullName()] == true
end
function rules.refreshEggLocations()
    refreshEggSave()
    refreshEggInventory()
    eggLocations={}
    wrappedEggs={}
    for _,class in ipairs({'ShopEgg_C','ChocolateEgg_C'}) do
        for _,egg in ipairs(FindAllOf(class) or {}) do
            if valid(egg) then
                eggLocations[#eggLocations+1]=egg:K2_GetActorLocation()
                if class == "ChocolateEgg_C" and not rules.isCollected(egg) then
                    local inner = property(egg, "ToyEgg")
                    if valid(inner) then wrappedEggs[inner:GetFullName()] = true end
                end
            end
        end
    end
end
function rules.isEggSecret(actor)
    -- Egg secrets use a separate SecretVolume actor. Suppress only nearby
    -- duplicates, including volumes around eggs that have already been opened.
    local loc=actor:K2_GetActorLocation()
    for _,egg in ipairs(eggLocations) do
        local dx,dy,dz=loc.X-egg.X,loc.Y-egg.Y,loc.Z-egg.Z
        if dx*dx+dy*dy+dz*dz<=150*150 then return true end
    end
    return false
end
function rules.showOnMap(class)
    local category=rules.classCategory[class]
    return not category or rules.enabled[category] == true
end
function rules.logEggMarkers(targets, playerLocation)
    local visible = {}
    local count = 0
    for _, target in ipairs(targets) do
        if target.category.id == "abilities" then
            visible[target.name] = true
            count = count + 1
        end
    end
    print("Egg radar markers: " .. count)
    for _, class in ipairs({"ChocolateEgg_C", "ShopEgg_C"}) do
        for _, actor in ipairs(FindAllOf(class) or {}) do
            if valid(actor) then
                local name = actor:GetFullName()
                local rewardActor = class == "ChocolateEgg_C" and property(actor, "ToyEgg") or actor
                local ok, path = pcall(eggRewardPath, rewardActor)
                local reward = ok and path and path ~= "None" and path or "unknown"
                if reward == "unknown" then
                    local spawned = property(rewardActor, "SpawnedShopItem")
                    if valid(spawned) then reward = spawned:GetFullName() end
                end
                local loc = actor:K2_GetActorLocation()
                local dx, dy, dz = loc.X-playerLocation.X, loc.Y-playerLocation.Y, loc.Z-playerLocation.Z
                local distance = math.sqrt(dx*dx+dy*dy+dz*dz) / 100
                if visible[name] or distance <= 30 or reward == "Inventory_LaserWalk_C" then
                    local status = visible[name] and "shown"
                        or (rules.isWrappedEgg(actor) and "inside shell" or "filtered")
                    print(string.format("Egg %s | %s | %s | XYZ %.0f %.0f %.0f | %.1f m",
                        status, reward, name, loc.X, loc.Y, loc.Z, distance))
                end
            end
        end
    end
end

function rules.gather(includeDisabled)
    rules.refreshEggLocations()
    local result={}
    local seen={}
    for _,category in ipairs(rules.categories) do
        if includeDisabled or rules.enabled[category.id] then
            for _,class in ipairs(category.classes) do
                for _,actor in ipairs(FindAllOf(class) or {}) do
                    if not rules.isCollected(actor)
                        and not (class=="ShopEgg_C" and rules.isWrappedEgg(actor))
                        and not (class=="SecretVolume_C" and rules.isEggSecret(actor)) then
                        local name=actor:GetFullName()
                        if not seen[name] then
                            seen[name]=true
                            local loc=actor:K2_GetActorLocation()
                            result[#result+1]={loc={X=loc.X,Y=loc.Y,Z=loc.Z}, class=class, category=category, name=name}
                        end
                    end
                end
            end
        end
    end
    return result
end
return rules
