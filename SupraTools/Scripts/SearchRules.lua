local rules = {}
rules.categories = {
    {id="pages", label="Страницы", color={R=0,G=1,B=1,A=0.85}, classes={"Pickup_SolversGuidePage_C","Pickup_SolversGuidePage_Combined_C"}},
    {id="secrets", label="Секреты", color={R=0.2,G=1,B=0.3,A=0.85}, classes={"SecretVolume_C"}},
    {id="coins", label="Монеты", color={R=1,G=0.75,B=0.1,A=0.85}, classes={"RealCoinPickup_C"}},
    {id="chests", label="Сундуки / подарки", color={R=1,G=0.25,B=0.3,A=0.85}, classes={"PresentBox_C","PresentBox_Lootpools_C"}},
    {id="abilities", label="Способности / яйца", color={R=0.65,G=0.15,B=1,A=0.85}, classes={"ChocolateEgg_C","ShopEgg_C"}},
    {id="cards", label="Игральные карты", color={R=1,G=0.2,B=0.65,A=0.85}, classes={"Pickup_Card_C"}},
}
rules.enabled = {pages=true,secrets=true,coins=true,chests=true,abilities=true,cards=true}
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
local function eggRewardCollected(actor)
    local ok,collected=pcall(function()
        local class=actor:GetClass():GetFName():ToString()
        if class=="ChocolateEgg_C" then
            local egg=property(actor,'ToyEgg')
            if valid(egg) then return taken(egg) or eggRewardCollected(egg) end
        elseif class=="ShopEgg_C" then
            if actor.bEggIsCut==true then return true end
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
    return taken(actor) or eggRewardCollected(actor)
end
local eggLocations={}
function rules.refreshEggLocations()
    eggLocations={}
    for _,class in ipairs({'ShopEgg_C','ChocolateEgg_C'}) do
        for _,egg in ipairs(FindAllOf(class) or {}) do
            if valid(egg) then eggLocations[#eggLocations+1]=egg:K2_GetActorLocation() end
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
function rules.gather(includeDisabled)
    rules.refreshEggLocations()
    local result={}
    local seen={}
    for _,category in ipairs(rules.categories) do
        if includeDisabled or rules.enabled[category.id] then
            for _,class in ipairs(category.classes) do
                for _,actor in ipairs(FindAllOf(class) or {}) do
                    if not rules.isCollected(actor) and not (class=='SecretVolume_C' and rules.isEggSecret(actor)) then
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
