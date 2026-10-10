local helpers=require('UEHelpers')
local module={}
local pool={}
local worldName
local function valid(obj) return obj and obj:IsValid() end
function module.clear()
    for _,entry in pairs(pool) do
        if valid(entry.actor) then entry.actor:K2_DestroyActor() end
    end
    pool={}
end
local function asset(path)
    local obj=StaticFindObject(path)
    if not valid(obj) then obj=LoadAsset(path) end
    return obj
end
function module.update(candidates,limit)
    local world=helpers.GetWorld()
    if not valid(world) then module.clear();return end
    local name=world:GetFullName()
    if worldName~=name then module.clear();worldName=name end
    local wanted={}
    for i,entry in ipairs(candidates) do
        if i>limit then break end
        local key=entry.target.name
        wanted[key]=true
        if not pool[key] or not valid(pool[key].actor) then
            local mesh=asset('/Engine/BasicShapes/Cylinder.Cylinder')
            if not valid(mesh) then error('3D beacon cylinder asset unavailable') end
            local actor=world:SpawnActor(StaticFindObject('/Script/Engine.StaticMeshActor'),
                {X=entry.loc.X,Y=entry.loc.Y,Z=entry.loc.Z+500030},{Pitch=0,Yaw=0,Roll=0})
            if not valid(actor) then error('Could not spawn 3D beacon') end
            pool[key]={actor=actor}
            actor:SetActorEnableCollision(false)
            actor:SetReplicates(false)
            actor:SetMobility(2)
            local component=actor.StaticMeshComponent
            component:SetSimulatePhysics(false)
            component:SetCollisionEnabled(0)
            component:SetCastShadow(false)
            assert(component:SetStaticMesh(mesh),'Could not assign beacon mesh')
            actor:SetActorScale3D({X=0.4,Y=0.4,Z=10000})
            local material=asset('/SupraAssets/Materials/EmissiveGlowWhite.EmissiveGlowWhite')
            if not valid(material) then material=asset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial') end
            if valid(material) then
                component:SetMaterial(0,material)
                local dynamic=component:CreateDynamicMaterialInstance(0,material,FName('None'))
                if valid(dynamic) then
                    local c=entry.target.category.color
                    local glow={R=c.R*2,G=c.G*2,B=c.B*2,A=1}
                    dynamic:SetVectorParameterValue(FName('Color'),glow)
                    dynamic:SetVectorParameterValue(FName('EmissiveColor'),glow)
                    dynamic:SetVectorParameterValue(FName('EmissiveMultiply'),{R=1,G=1,B=1,A=1})
                    dynamic:SetScalarParameterValue(FName('EmissiveStrength'),8)
                    pool[key].material=dynamic
                end
            end
        end
    end
    for key,entry in pairs(pool) do
        if not wanted[key] then
            if valid(entry.actor) then entry.actor:K2_DestroyActor() end
            pool[key]=nil
        end
    end
end
return module
