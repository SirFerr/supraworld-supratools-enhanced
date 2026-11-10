local UEHelpers = require("UEHelpers")
local state = nil
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
local cameraKeys = {
    "W", "A", "S", "D", "SpaceBar", "LeftShift",
    "MiddleMouseButton", "LeftMouseButton", "MouseWheelAxis", "MouseScrollUp", "MouseScrollDown",
}

local function captureInput(s)
    local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local class = StaticFindObject("/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem")
    local subsystem = library:GetLocalPlayerSubSystemFromPlayerController(s.pc, class)
    if not valid(subsystem) then error("Enhanced Input subsystem unavailable") end

    local context = StaticConstructObject(
        StaticFindObject("/Script/EnhancedInput.InputMappingContext"), subsystem)
    if not valid(context) then error("Free camera input context unavailable") end
    local actionClass = StaticFindObject("/Script/EnhancedInput.InputAction")
    for _, name in ipairs(cameraKeys) do
        -- Separate actions keep opposite wheel directions and held keys independent.
        local action = StaticConstructObject(actionClass, context)
        if not valid(action) then error("Free camera input action unavailable") end
        action.ValueType = 1 -- Axis1D also accepts the signed MouseWheelAxis value.
        action.bConsumeInput = true
        action.bConsumesActionAndAxisMappings = true
        action.TriggerEventsThatConsumeLegacyKeys = 31 -- All five ETriggerEvent flags.
        context:MapKey(action, {KeyName=FName(name)})
    end

    s.subsystem, s.inputContext = subsystem, context
    subsystem:AddMappingContext(context, 2147483647, {
        bForceImmediately=true, bIgnoreAllPressedKeysUntilRelease=false,
    })
end

local function copyProjection(component, camera)
    component.FieldOfView = camera:GetFOVAngle()
    local ok, err = pcall(function()
        local view = camera.CameraCachePrivate.POV
        component.AspectRatio = view.AspectRatio
        component.bConstrainAspectRatio = view.bConstrainAspectRatio
        component.ProjectionMode = view.ProjectionMode
        if view.ProjectionMode == 1 then component.OrthoWidth = view.OrthoWidth end

        local settings = StaticFindObject("/Script/Engine.Default__GameUserSettings"):GetGameUserSettings()
        if valid(settings) and settings.GetVerticalFOV then
            -- EAspectRatioAxisConstraint: MaintainYFOV = 0, MaintainXFOV = 1.
            component:SetAspectRatioAxisConstraint(settings:GetVerticalFOV() and 0 or 1)
            component.bOverrideAspectRatioAxisConstraint = true
        end
    end)
    if not ok then print("Free camera projection warning: " .. tostring(err)) end
end

local function cleanup(label, fn)
    local ok, err = pcall(fn)
    if not ok then print(label .. ": " .. tostring(err)) end
end

local function reduceCameraLatency(s)
    cleanup("Free camera mouse smoothing warning", function()
        local library = StaticFindObject("/Script/Engine.Default__InputSettings")
        if not valid(library) then return end
        local settings = library:GetInputSettings()
        if valid(settings) and settings.bEnableMouseSmoothing == true then
            s.inputSettings = settings
            settings.bEnableMouseSmoothing = false
        end
    end)
    cleanup("Free camera DLSS FG warning", function()
        local library = StaticFindObject("/Script/StreamlineDLSSGBlueprint.Default__StreamlineLibraryDLSSG")
        if not valid(library) then return end
        local mode = library:GetDLSSGMode()
        if type(mode) == "number" and mode ~= 0 then
            s.fgLibrary, s.fgMode = library, mode
            library:SetDLSSGMode(0)
            print("DLSS Frame Generation paused for free camera")
        end
    end)
end

local function stop()
    local s = state
    if not s then return end
    state = nil
    inDebugCamera = false
    if valid(s.inputSettings) then
        cleanup("Free camera mouse smoothing restore warning", function()
            s.inputSettings.bEnableMouseSmoothing = true
        end)
    end
    if valid(s.fgLibrary) then
        cleanup("Free camera DLSS FG restore warning", function()
            if s.fgLibrary:GetDLSSGMode() == 0 then
                s.fgLibrary:SetDLSSGMode(s.fgMode)
            end
        end)
    end
    if valid(s.subsystem) and valid(s.inputContext) then
        cleanup("Free camera input restore warning", function()
            s.subsystem:RemoveMappingContext(s.inputContext, {
                bForceImmediately=true, bIgnoreAllPressedKeysUntilRelease=true,
            })
        end)
    end
    if valid(s.pc) then
        if s.moveIgnored then
            cleanup("Free camera movement restore warning", function() s.pc:SetIgnoreMoveInput(false) end)
        end
        if s.viewChanged then
            cleanup("Free camera view restore warning", function()
                local target = valid(s.target) and s.target or s.pc.Pawn
                if valid(target) then s.pc:SetViewTargetWithBlend(target, 0, 0, 0, false) end
                s.pc:SetControlRotation(s.rotation)
            end)
        end
    end
    if valid(s.actor) then
        cleanup("Free camera actor cleanup warning", function() s.actor:K2_DestroyActor() end)
    end
    if valid(hud) then cleanup("Free camera HUD warning", function() hud:SetVisibility(2) end) end
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
    -- Use the game's processed look input, including sensitivity and inversion.
    local r = s.pc:GetControlRotation()
    local rot = {Pitch=r.Pitch, Yaw=r.Yaw, Roll=r.Roll}
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
local function updateEveryFrame(session)
    ExecuteInGameThreadAfterFrames(1, function()
        if state ~= session then return end
        guarded(tick)
        if state == session then updateEveryFrame(session) end
    end)
end

local function toggle()
    if state then stop() return end
    local pc = getPlayerController()
    if not valid(pc) or not valid(pc.Pawn) then return end
    local cam = pc.PlayerCameraManager
    local r = cam:GetCameraRotation()
    local rotation = {Pitch=r.Pitch,Yaw=r.Yaw,Roll=r.Roll}
    local control = pc:GetControlRotation()
    state = {pc=pc, pawn=pc.Pawn, target=pc:GetViewTarget(),
        rotation={Pitch=control.Pitch,Yaw=control.Yaw,Roll=control.Roll},
        time=UEHelpers.GetGameplayStatics():GetRealTimeSeconds(pc)}
    local actor = pc:GetWorld():SpawnActor(StaticFindObject("/Script/Engine.CameraActor"),
        cam:GetCameraLocation(), rotation)
    if not valid(actor) then error("CameraActor spawn failed") end
    state.actor = actor
    copyProjection(actor.CameraComponent, cam)
    captureInput(state)
    pc:SetIgnoreMoveInput(true)
    state.moveIgnored = true
    if valid(pc.Character) then pc.Character:StopJumping() end
    state.viewChanged = true
    pc:SetControlRotation(rotation)
    pc:SetViewTargetWithBlend(actor, 0, 0, 0, false)
    local hudOK, hudErr = pcall(updateHud)
    if not hudOK then print("HUD warning: " .. tostring(hudErr)) end
    reduceCameraLatency(state)
    updateEveryFrame(state)
    inDebugCamera = true
    print("Free camera ON: WASD, Space up, Shift down, mouse wheel speed; middle mouse exits; left mouse teleports")
end
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
