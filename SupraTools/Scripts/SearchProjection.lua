-- Project plain coordinates without retaining native actors or using out-parameter tables.
return function(camera,rotation,fov,viewport,scale,point)
    if not viewport or viewport.X<=0 or viewport.Y<=0 then return nil end
    scale=math.max(scale or 1,0.01)
    local yaw,pitch,roll=math.rad(rotation.Yaw),math.rad(rotation.Pitch),math.rad(rotation.Roll or 0)
    local cy,sy,cp,sp,cr,sr=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch),math.cos(roll),math.sin(roll)
    local dx,dy,dz=point.X-camera.X,point.Y-camera.Y,point.Z-camera.Z
    local depth=dx*cp*cy+dy*cp*sy+dz*sp
    if depth<1 then return nil end
    local right=-dx*sy+dy*cy
    local up=-dx*sp*cy-dy*sp*sy+dz*cp
    local x,y=right*cr+up*sr,up*cr-right*sr
    local focal=viewport.X/(2*math.tan(math.rad(math.max(10,math.min(170,fov)))/2))
    return {X=(viewport.X/2+x*focal/depth)/scale,Y=(viewport.Y/2-y*focal/depth)/scale}
end
