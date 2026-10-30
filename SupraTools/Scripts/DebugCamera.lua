local UEHelpers = require("UEHelpers")
local state = nil
local queued = false
local speed = 1000
local function valid(o) return o and o:IsValid() end

local hud, hudText
local function updateHud()
    if not valid(hud) then
        hud = StaticConstructObject(StaticFindObject("/Script/UMG.UserWidget"), UEHelpers.GetGameInstance())
        hud.WidgetTree = StaticConstructObject(StaticFindObject("/Script/UMG.WidgetTree"), hud)
        local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), hud.WidgetTree)
        hud.WidgetTree.RootWidget = canvas
        local bg = StaticConstructObject(StaticFindObject("/Script/UMG.Border"), canvas)
        bg:SetBrushColor({R=0,G=0,B=0,A=0.45})
        bg:SetPadding({Left=10,Top=5,Right=10,Bottom=5})
        local slot = canvas:AddChildToCanvas(bg)
        slot:SetAutoSize(true)
        slot:SetPosition({X=16,Y=16})
        hudText = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), bg)
        hudText.Font.Size = 16
        bg:SetContent(hudText)
        hud:AddToViewport(100)
        hud:SetVisibility(4)
    end
    hud:SetVisibility(4)
    hudText:SetText(UEHelpers.GetKismetTextLibrary():Conv_StringToText(string.format("Freecam | Speed %.1f", speed/100)))
end
local function rebuild(context)
    local library = StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    library:RequestRebuildControlMappingsUsingContext(context, true)
end
local function blockWheel(s)
    s.wheelMappings = {}
    for _, context in ipairs(FindAllOf("InputMappingContext") or {}) do
        if valid(context) then
            local changed = false
            context.Mappings:ForEach(function(index, param)
                local mapping = param:get()
                local name = mapping.Key.KeyName:ToString()
                if name == "MouseWheelAxis" or name == "MouseScrollUp" or name == "MouseScrollDown" then
                    table.insert(s.wheelMappings, {context=context,index=index,name=name})
                    mapping.Key.KeyName = FName("None")
                    changed = true
                end
            end)
            if changed then rebuild(context) end
        end
    end
end
local function restoreWheel(s)
    for _, entry in ipairs(s.wheelMappings or {}) do
        if valid(entry.context) then
            entry.context.Mappings[entry.index].Key.KeyName = FName(entry.name)
            rebuild(entry.context)
        end
    end
end

local function stop()
    local s = state
    if not s then return end
    local restored, restoreError = pcall(function() restoreWheel(s) end)
    if not restored then print("Wheel restore warning: " .. tostring(restoreError)) end
    if valid(hud) then hud:SetVisibility(2) end
    if valid(s.pc) then
        local target = valid(s.target) and s.target or s.pc.Pawn
        if valid(target) then s.pc:SetViewTargetWithBlend(target, 0, 0, 0, false) end
        s.pc:SetIgnoreMoveInput(false)
        s.pc:SetControlRotation(s.rotation)
    end
    if valid(s.actor) then s.actor:K2_DestroyActor() end
    state = nil
    inDebugCamera = false
    print("Free camera OFF")
end
local function guarded(fn)
    local ok, err = pcall(fn)
    if not ok then
        print("Free camera error: " .. tostring(err))
        local restored, restoreError = pcall(stop)
        if not restored then print("Camera recovery error: " .. tostring(restoreError)) end
    end
end
local function key(pc, name)
    return pc:IsInputKeyDown({KeyName=FName(name)})
end
local function tick()
    local s = state
    if not s then return end
    if not valid(s.pc) or not valid(s.actor) or not valid(s.pawn) then stop() return end
    if s.pc.Pawn ~= s.pawn then stop() return end
    local now = UEHelpers.GetGameplayStatics():GetRealTimeSeconds(s.pc)
    local dt = math.max(0, math.min(now - s.time, 0.05))
    s.time = now
    if UEHelpers.GetGameplayStatics():IsGamePaused(s.pc) then return end
    local r = s.pc:GetControlRotation()
    local rot = {Pitch=r.Pitch, Yaw=r.Yaw, Roll=0}
    local p = s.actor:K2_GetActorLocation()
    local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch)
    local f = (key(s.pc,"W") and 1 or 0) - (key(s.pc,"S") and 1 or 0)
    local side = (key(s.pc,"D") and 1 or 0) - (key(s.pc,"A") and 1 or 0)
    local up = (key(s.pc,"SpaceBar") and 1 or 0) - (key(s.pc,"LeftShift") and 1 or 0)
    local wheel = s.pc:GetInputAnalogKeyState({KeyName=FName("MouseWheelAxis")})
    if wheel ~= 0 and not s.wheelHeld then
        speed = math.max(50, math.min(50000, speed * (1.05 ^ wheel)))
        updateHud()
    end
    s.wheelHeld = wheel ~= 0
    local norm = math.max(1, math.sqrt(f*f+side*side+up*up))
    local d = speed * dt / norm
    s.actor:K2_SetActorLocationAndRotation({
        X=p.X+d*(f*math.cos(pitch)*math.cos(yaw)-side*math.sin(yaw)),
        Y=p.Y+d*(f*math.cos(pitch)*math.sin(yaw)+side*math.cos(yaw)),
        Z=p.Z+d*(f*math.sin(pitch)+up)
    }, rot, false, {}, true)
end
local function toggle()
    if state then stop() return end
    local pc = getPlayerController()
    if not valid(pc) or not valid(pc.Pawn) then return end
    local cam = pc.PlayerCameraManager
    local r = cam:GetCameraRotation()
    local rotation = {Pitch=r.Pitch,Yaw=r.Yaw,Roll=r.Roll}
    local actor = pc:GetWorld():SpawnActor(StaticFindObject("/Script/Engine.CameraActor"),
        cam:GetCameraLocation(), rotation)
    if not valid(actor) then error("CameraActor spawn failed") end
    local control = pc:GetControlRotation()
    state = {pc=pc, pawn=pc.Pawn, actor=actor, target=pc:GetViewTarget(),
        rotation={Pitch=control.Pitch,Yaw=control.Yaw,Roll=control.Roll},
        time=UEHelpers.GetGameplayStatics():GetRealTimeSeconds(pc)}
    actor.CameraComponent.bConstrainAspectRatio = false
    actor.CameraComponent.FieldOfView = cam:GetFOVAngle()
    pc:SetIgnoreMoveInput(true)
    pc:SetControlRotation(rotation)
    pc:SetViewTargetWithBlend(actor, 0, 0, 0, false)
    local ok, err = pcall(function() blockWheel(state) end)
    if not ok then print("Wheel mapping warning: " .. tostring(err)) end
    local hudOK, hudErr = pcall(updateHud)
    if not hudOK then print("HUD warning: " .. tostring(hudErr)) end
    inDebugCamera = true
    print("Free camera ON: WASD, Space up, Shift down, mouse wheel speed; middle mouse exits; left mouse teleports")
end
-- All engine calls stay on the game thread; no queued tick accumulation.
LoopAsync(16, function()
    if not state or queued then return false end
    queued = true
    ExecuteInGameThread(function()
        guarded(tick)
        queued = false
    end)
    return false
end)
RegisterKeyBind(Key.MIDDLE_MOUSE_BUTTON, function()
    ExecuteInGameThread(function() guarded(toggle) end)
end)
RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
    if not state then return end
    ExecuteInGameThread(function()
        guarded(function()
            local s = state
            if not s or not valid(s.pawn) then return end
            local p = s.actor:K2_GetActorLocation()
            local r = s.actor:K2_GetActorRotation()
            local hit = getImpactPoint(s.pawn, p, r)
            s.pawn.RootComponent:K2_SetWorldLocation({X=hit.X,Y=hit.Y,Z=hit.Z+100}, false, {}, true)
        end)
    end)
end)
-- The original controller still owns PlayerCameraManager and all SupraTools widgets.
function getCameraController() return getPlayerController() end
print("CameraActor free camera loaded")
