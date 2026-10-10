local rules = {}
rules.categories = {
    {id="pages", label="Страницы", color={R=0,G=1,B=1,A=0.85}, classes={"Pickup_SolversGuidePage_C","Pickup_SolversGuidePage_Combined_C"}},
    {id="secrets", label="Секреты", color={R=0.2,G=1,B=0.3,A=0.85}, classes={"SecretVolume_C"}},
    {id="coins", label="Монеты", color={R=1,G=0.75,B=0.1,A=0.85}, classes={"RealCoinPickup_C"}},
    {id="chests", label="Сундуки / подарки", color={R=1,G=0.25,B=0.3,A=0.85}, classes={"PresentBox_C","PresentBox_Lootpools_C"}},
    {id="abilities", label="Способности / яйца", color={R=0.65,G=0.15,B=1,A=0.85}, classes={"ChocolateEgg_C","ShopEgg_C"}},
}
rules.enabled = {pages=true,secrets=true,coins=true,chests=true,abilities=true}
rules.classCategory = {}
for _,category in ipairs(rules.categories) do
    for _,class in ipairs(category.classes) do rules.classCategory[class]=category.id end
end
rules.classCategory.ItemSpawner_C="chests"
rules.classCategory.PickupSpawner_C="chests"
local picked = {}
function rules.mark(name) picked[name] = true end
function rules.wasPicked(name) return picked[name]==true end
local function eggRewardCollected(actor)
    local ok,collected=pcall(function()
        local class=actor:GetClass():GetFName():ToString()
        if class=="ChocolateEgg_C" then
            local egg=actor.ToyEgg
            if egg and egg:IsValid() then return eggRewardCollected(egg) or egg.bEggIsCut==true end
        elseif class=="ShopEgg_C" then
            if actor.bEggIsCut==true then return true end
            local reward=actor.SpawnedShopItem
            if reward and reward:IsValid() then
                return picked[reward:GetFullName()]==true or reward.bItemIsTaken==true
                    or reward.bPickedUp==true or reward['Pickup has been collected']==true
            end
        end
        return false
    end)
    return ok and collected==true
end
function rules.isCollected(actor)
    if not actor or not actor:IsValid() then return true end
    return picked[actor:GetFullName()] == true
        or actor.bPickedUp == true or actor.bFound == true
        or actor.bItemIsTaken == true or actor.IsOpen == true
        or actor.bEggIsCut == true or actor.ChocolateMeltedOpen == true
        or actor.bHidden == true or actor['Pickup has been collected'] == true
        or eggRewardCollected(actor)
end
function rules.showOnMap(class)
    local category=rules.classCategory[class]
    return not category or rules.enabled[category] == true
end
function rules.gather(includeDisabled)
    local result={}
    local seen={}
    for _,category in ipairs(rules.categories) do
        if includeDisabled or rules.enabled[category.id] then
            for _,class in ipairs(category.classes) do
                for _,actor in ipairs(FindAllOf(class) or {}) do
                    if not rules.isCollected(actor) then
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
