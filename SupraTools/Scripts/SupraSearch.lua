local UEHelpers=require("UEHelpers")
local rules=require("SearchRules")
local project=require("SearchProjection")
local placeLabel=require("SearchLabelLayout")
local worldBeacons=require("SearchWorldBeacons")
local VISIBLE,HIDDEN=3,2 -- Whole overlay ignores mouse hits; the game keeps receiving input.
local menuOpen=false
local beamsOn=false
local radius=20000
local limit=16
local selection=1
local tab="search"
local widget,canvas,panel,menuText
local markers={}
local targets={}
local ticks=0
local queued=false
local errors=0
local counts={}
local diagnostics={}
local lastMenuText
local configPath=(os.getenv("LOCALAPPDATA") or ".") .. "/Supraworld/SupraSearch.ini"

local function valid(obj) return obj and obj:IsValid() end
local function text(value) return UEHelpers.GetKismetTextLibrary():Conv_StringToText(value) end
local function save()
    local file=io.open(configPath,"w")
    if not file then return end
    for _,category in ipairs(rules.categories) do file:write(category.id,"=",tostring(rules.enabled[category.id]),"\n") end
    file:write("radius=",radius,"\n", "limit=",limit,"\n", "beams=",tostring(beamsOn),"\n")
    file:close()
end
local file=io.open(configPath,"r")
if file then
    for line in file:lines() do
        local key,value=line:match("^(%w+)=(.+)$")
        if rules.enabled[key]~=nil then rules.enabled[key]=value=="true"
        elseif key=="radius" and tonumber(value) then radius=math.max(2000,math.min(100000,tonumber(value)))
        elseif key=="limit" and tonumber(value) then limit=math.max(1,math.min(24,tonumber(value)))
        elseif key=="beams" then beamsOn=value=="true" end
    end
    file:close()
end

local function make(class,outer,name)
    -- RF_Transient | RF_MarkAsRootSet: keep this bounded overlay alive across world GC.
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. class),outer,FName(name),0xC0)
end
local function makeText(outer,name,size)
    local label=make("TextBlock",outer,name)
    label.Font.Size=size
    label:SetColorAndOpacity({SpecifiedColor={R=1,G=1,B=1,A=1},ColorUseRule=0})
    label:SetShadowOffset({X=1,Y=1})
    label:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.8})
    label:SetVisibility(VISIBLE)
    return label
end
local function ensureWidget()
    if valid(widget) then return end
    markers={}
    widget=make("UserWidget",UEHelpers.GetGameInstance(),"SupraSearchWidget")
    widget.WidgetTree=make("WidgetTree",widget,"SupraSearchTree")
    canvas=make("CanvasPanel",widget.WidgetTree,"SupraSearchCanvas")
    widget.WidgetTree.RootWidget=canvas
    canvas:SetClipping(1)
    panel=make("Border",canvas,"SupraSearchPanel")
    panel:SetBrushColor({R=0.015,G=0.025,B=0.04,A=0.92})
    panel:SetPadding({Left=24,Top=18,Right=24,Bottom=18})
    local slot=canvas:AddChildToCanvas(panel)
    slot:SetPosition({X=40,Y=120})
    slot:SetAutoSize(true)
    slot:SetZOrder(100)
    menuText=makeText(panel,"SupraSearchMenuText",20)
    panel:SetContent(menuText)
    widget:AddToViewport(110)
    widget:SetVisibility(VISIBLE)
end
local function menu()
    if not valid(panel) then return end
    local lines={"SUPRATOOLS", "Alt+H закрыть  •  Alt+← сменить вкладку", ""}
    if tab=="general" then
        lines[#lines+1]="[Управление]    Поиск"
        lines[#lines+1]="F — быстрое перемещение"
        lines[#lines+1]="Средняя кнопка мыши — полёт камерой"
        lines[#lines+1]="Левая кнопка в полёте — телепорт"
        lines[#lines+1]="Alt+E — удалённое управление"
        lines[#lines+1]="Alt+P — собрать предметы"
        lines[#lines+1]="Alt+I — экипировать всё"
        lines[#lines+1]="Alt+F — заполнить костюм"
        lines[#lines+1]="Alt+Z/X/C/V — редактирование"
        lines[#lines+1]="Alt+M — миникарта"
        lines[#lines+1]="Alt+O — статистика"
        lines[#lines+1]="Alt+K — защита от урона"
        lines[#lines+1]="Alt+B — 3D-маяки"
        lines[#lines+1]=""
        lines[#lines+1]="Основа: SupraTools 1.0.3, Joric"
        local value=table.concat(lines,"\n")
        if value~=lastMenuText then menuText:SetText(text(value));lastMenuText=value end
        panel:SetVisibility(menuOpen and VISIBLE or HIDDEN)
        return
    end
    lines[#lines+1]="Управление    [Поиск]"
    local rows={}
    for _,category in ipairs(rules.categories) do
        rows[#rows+1]=(rules.enabled[category.id] and "[✓] " or "[ ] ") .. category.label .. "  (" .. (counts[category.id] or 0) .. ")"
    end
    rows[#rows+1]="Лучи: " .. (beamsOn and "ВКЛ" or "ВЫКЛ")
    rows[#rows+1]="Радиус: " .. math.floor(radius/100) .. " м"
    rows[#rows+1]="Максимум лучей: " .. limit
    for i,row in ipairs(rows) do lines[#lines+1]=(i==selection and "▶ " or "  ") .. row end
    lines[#lines+1]=""
    lines[#lines+1]="Alt+↑/↓ — выбрать   Alt+→ — изменить"
    lines[#lines+1]="Alt+B — лучи   Alt+M — миникарта"
    lines[#lines+1]="Только несобранные вещи в загруженном районе"
    local value=table.concat(lines,"\n")
    if value~=lastMenuText then menuText:SetText(text(value));lastMenuText=value end
    panel:SetVisibility(menuOpen and VISIBLE or HIDDEN)
end
local function scan()
    targets=rules.gather(true)
    counts={}
    for _,target in ipairs(targets) do
        local key=target.category.id
        counts[key]=(counts[key] or 0)+1
    end
end
local function marker(index)
    if markers[index] then return markers[index] end
    local beam=make("Border",canvas,"SearchBeam" .. index)
    beam:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    local beamSlot=canvas:AddChildToCanvas(beam)
    beamSlot:SetZOrder(1)
    beam:SetRenderTransformPivot({X=0.5,Y=1})
    local label=makeText(canvas,"SearchLabel" .. index,15)
    local labelSlot=canvas:AddChildToCanvas(label)
    labelSlot:SetAutoSize(true)
    labelSlot:SetZOrder(2)
    markers[index]={beam=beam,label=label}
    return markers[index]
end
local function hideMarkers()
    for _,item in ipairs(markers) do
        if valid(item.beam) then item.beam:SetVisibility(HIDDEN) end
        if valid(item.label) then item.label:SetVisibility(HIDDEN) end
    end
end
local function update()
    if not menuOpen and not beamsOn then
        if valid(widget) then widget:SetVisibility(HIDDEN) end
        worldBeacons.clear()
        return
    end
    local pc=getCameraController and getCameraController() or UEHelpers.GetPlayerController()
    if not valid(pc) or not valid(pc.PlayerCameraManager) then return end
    ensureWidget()
    if not widget:IsInViewport() then widget:AddToViewport(110) end
    widget:SetVisibility(VISIBLE)
    local nowSearchTime=os.clock()
    ticks=ticks+1
    if not diagnostics.lastScan or nowSearchTime-diagnostics.lastScan>=2 then scan();diagnostics.lastScan=nowSearchTime end
    menu()
    hideMarkers()
    if not beamsOn then worldBeacons.clear();return end
    local nativeCamera=pc.PlayerCameraManager:GetCameraLocation()
    local camera={X=nativeCamera.X,Y=nativeCamera.Y,Z=nativeCamera.Z}
    local candidates={}
    for _,target in ipairs(targets) do
        if rules.enabled[target.category.id] and not rules.wasPicked(target.name) then
            local loc=target.loc
            local dx,dy,dz=loc.X-camera.X,loc.Y-camera.Y,loc.Z-camera.Z
            local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
            if dist<=radius then candidates[#candidates+1]={target=target,loc=loc,dist=dist} end
        end
    end
    table.sort(candidates,function(a,b) return a.dist<b.dist end)
    worldBeacons.update(candidates,limit)
    diagnostics.candidates=#candidates
    diagnostics.camera=camera
    local nearest
    for _,target in ipairs(targets) do
        local loc=target.loc
        local d=math.sqrt((loc.X-camera.X)^2+(loc.Y-camera.Y)^2+(loc.Z-camera.Z)^2)
        nearest=not nearest and d or math.min(nearest,d)
    end
    diagnostics.nearest=nearest
    local layout=StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local nativeViewport=layout:GetViewportSize(pc)
    local viewport={X=nativeViewport.X,Y=nativeViewport.Y}
    local scale=layout:GetViewportScale(pc)
    local nativeRotation=pc.PlayerCameraManager:GetCameraRotation()
    local rotation={Yaw=nativeRotation.Yaw,Pitch=nativeRotation.Pitch,Roll=nativeRotation.Roll}
    local fov=pc.PlayerCameraManager:GetFOVAngle()
    local used=0
    local occupied={}
    for index,entry in ipairs(candidates) do
        if index>limit then break end
        local origin={X=entry.loc.X,Y=entry.loc.Y,Z=entry.loc.Z+30}
        local bottom=project(camera,rotation,fov,viewport,scale,origin)
        if bottom then
            local position=placeLabel(bottom,viewport.X/scale,viewport.Y/scale,occupied)
            if position then
                used=used+1
                local item=marker(used)
                item.beam:SetVisibility(HIDDEN)
                item.label.Slot:SetPosition(position)
                item.label:SetColorAndOpacity({SpecifiedColor=entry.target.category.color,ColorUseRule=0})
                local value=entry.target.category.label .. " · " .. math.floor(entry.dist/100) .. " м"
                if item.lastText~=value then item.label:SetText(text(value));item.lastText=value end
                item.label:SetVisibility(VISIBLE)
            end
        end
    end
    diagnostics.drawn=used
end
local actions={}
local function run(fn) actions[#actions+1]=fn end
local function change()
    if selection<=#rules.categories then
        local id=rules.categories[selection].id
        rules.enabled[id]=not rules.enabled[id]
    elseif selection==#rules.categories+1 then beamsOn=not beamsOn
    elseif selection==#rules.categories+2 then
        local values={5000,20000,50000,100000}
        local nextValue=values[1]
        for i,value in ipairs(values) do if value==radius then nextValue=values[i%#values+1] end end
        radius=nextValue
    else limit=limit==8 and 16 or limit==16 and 24 or 8 end
    save(); scan(); menu()
    if SupraSearchRefreshMap then SupraSearchRefreshMap() end
end
function SupraSearchSetMenuOpen(open)
    run(function() menuOpen=open==true; scan(); update() end)
end
RegisterKeyBind(Key.H,{ModifierKey.ALT},function()
    run(function()
        if SupraToolsHideLegacyHelp then SupraToolsHideLegacyHelp() end
        menuOpen=not menuOpen;scan();update()
    end)
end)
RegisterKeyBind(0x25,{ModifierKey.ALT},function()
    if menuOpen then run(function() tab=tab=="search" and "general" or "search";menu() end) end
end)
RegisterKeyBind(Key.B,{ModifierKey.ALT},function() run(function() beamsOn=not beamsOn; save(); scan(); update() end) end)
RegisterKeyBind(0x26,{ModifierKey.ALT},function() if menuOpen and tab=="search" then run(function() selection=(selection-2)%(#rules.categories+3)+1; menu() end) end end)
RegisterKeyBind(0x28,{ModifierKey.ALT},function() if menuOpen and tab=="search" then run(function() selection=selection%(#rules.categories+3)+1; menu() end) end end)
RegisterKeyBind(0x27,{ModifierKey.ALT},function() if menuOpen and tab=="search" then run(change) end end)
RegisterConsoleCommandHandler("supra_search",function(_,params)
    run(function()
        local action=params[1]
        if action=="beams" then beamsOn=not beamsOn
        elseif action=="status" then
            scan(); print("Search targets",#targets,"beams",beamsOn,"errors",errors,"nearby",diagnostics.candidates,"drawn",diagnostics.drawn)
            local p=diagnostics.projection or {};print("Projection",p.ok,p.topOk,p.x,p.y,p.tx,p.ty,"nearest cm",diagnostics.nearest);return
        elseif action=="radius" and tonumber(params[2]) then radius=math.max(2000,math.min(100000,tonumber(params[2])*100))
        elseif rules.enabled[action]~=nil then rules.enabled[action]=not rules.enabled[action]
        else menuOpen=not menuOpen end
        save(); scan(); update()
        if SupraSearchRefreshMap then SupraSearchRefreshMap() end
    end)
    return true
end)
local lastUpdate=0
function SupraSearchTick()
    local now=os.clock()
    if now-lastUpdate<1/30 then return end
    lastUpdate=now
    local pending=actions; actions={}
    lastUpdate=now
    local ok,err=pcall(function()
        for _,fn in ipairs(pending) do fn() end
        update()
    end)
    if not ok then
        errors=errors+1
        if errors<=3 then print("Search update error",tostring(err)) end
        beamsOn=false;menuOpen=false;hideMarkers()
        pcall(worldBeacons.clear)
        if valid(widget) then widget:SetVisibility(HIDDEN) end
    end
end
print("SupraSearch ready: Alt+H help and search, Alt+B beams")
