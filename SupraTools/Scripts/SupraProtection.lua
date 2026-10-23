local UEHelpers = require("UEHelpers")
local enabled = true
local installed = false
local blocked = 0
local lastInstallError
local hookPath = "/Supraworld/Core/Characters/SupraworldCharacterBase.SupraworldCharacterBase_C:IsImmuneToDamage?"

local function player()
    local pc = getPlayerController and getPlayerController() or UEHelpers.GetPlayerController()
    if not pc or not pc:IsValid() then return end
    local actor = pc.Character
    if actor and actor:IsValid() and actor:GetClass():GetFName():ToString() == "Player_ToyCharacter_C" then return actor end
end

local function install()
    if installed then return end
    local fn = StaticFindObject(hookPath)
    if not fn or not fn:IsValid() then return end
    local ok, err = pcall(RegisterHook, hookPath, function(context)
        if not enabled then return end
        local actor = context:get()
        local localPlayer = player()
        if actor and actor:IsValid() and localPlayer and actor:GetFullName() == localPlayer:GetFullName() then
            blocked = blocked + 1
            return true
        end
    end)
    if not ok then
        local message = tostring(err)
        if message ~= lastInstallError then
            print("Protection unavailable; menu/search remain enabled:", message)
            lastInstallError = message
        end
        return
    end
    lastInstallError = nil
    installed = true
    print("Protection ON; Alt+K toggles player damage immunity")
end

local function status()
    local actor = player()
    if not actor then print("Protection: player not loaded"); return end
    local hc = actor.HealthComponent
    print("Protection", enabled and "ON" or "OFF", "hook", installed, "blocked", blocked,
        "health", hc:GetHealth(), "/", hc:GetMaxHealth())
    print("Player immunity response", actor["IsImmuneToDamage?"](actor, {}))
    for _, class in ipairs({"Pickup_SolversGuidePage_C", "Pickup_SolversGuidePage_Combined_C"}) do
        local remaining = 0
        for _, page in ipairs(FindAllOf(class) or {}) do
            if page:IsValid() and page.bPickedUp ~= true and page.bHidden ~= true then remaining = remaining + 1 end
        end
        print("Pages", class, "remaining loaded", remaining)
    end
end

install()
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteInGameThread(install)
end)
RegisterKeyBind(Key.K, {ModifierKey.ALT}, function()
    enabled = not enabled
    print("Protection", installed and (enabled and "ON" or "OFF") or "UNAVAILABLE")
end)
RegisterConsoleCommandHandler("supra_status", function()
    ExecuteInGameThread(status)
    return true
end)
RegisterConsoleCommandHandler("supra_test_damage", function()
    ExecuteInGameThread(function()
        local actor = player()
        if not actor or not installed or not enabled then print("Damage test skipped: protection not ready"); return end
        local before = actor.HealthComponent:GetHealth()
        local oldBlocked = blocked
        local damage = UEHelpers.GetGameplayStatics():ApplyDamage(actor, 1.0, getPlayerController(), actor, CreateInvalidObject())
        print("Damage test", "before", before, "after", actor.HealthComponent:GetHealth(), "damage", damage, "immunity calls", blocked-oldBlocked)
    end)
    return true
end)
