return function(point,width,height,occupied)
    local w,h=250,28
    if point.X<0 or point.Y<0 or point.X>width or point.Y>height then return nil end
    local x=math.floor(math.max(8,math.min(width-w-8,point.X+8))+0.5)
    local original=math.floor(math.max(8,math.min(height-h-8,point.Y))+0.5)
    for attempt=0,24 do
        local offset=attempt==0 and 0 or math.ceil(attempt/2)*32*(attempt%2==1 and -1 or 1)
        local y=original+offset
        if y>=8 and y+h<=height-8 then
            local free=true
            for _,box in ipairs(occupied) do
                if x<box.x+w and x+w>box.x and y<box.y+h and y+h>box.y then free=false;break end
            end
            if free then occupied[#occupied+1]={x=x,y=y};return {X=x,Y=y} end
        end
    end
    return nil
end
