-- blood-visuals-v15.lua | Roblox Luau client | fitted anatomical cutaway renderer
-- Regional anatomical cutaways: source meshes retain actual bone and muscle topology.
-- Anatomical source and attribution: ANATOMY_ATTRIBUTION.md (CC BY-SA 4.0).
-- The 206-bone count describes the source atlas, not 206 simulated rigid bodies.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for v = 1, 15 do
    local stop = env["RagdollGoreV" .. v .. "Stop"]
    if type(stop) == "function" then pcall(stop) end
end

local BASE = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/"
local SOURCE_SIZE = {
    Head=Vector3.new(1.1962,1.2029,1.1979),
    UpperTorso=Vector3.new(1.8154,1.7732,1.1102),
    LowerTorso=Vector3.new(1.6962,0.5661,0.9525),
    RightUpperArm=Vector3.new(0.5699,1.0948,0.7828),
    RightLowerArm=Vector3.new(0.6271,0.9477,0.6166),
    RightHand=Vector3.new(0.6933,1.1018,0.7443),
    LeftUpperArm=Vector3.new(0.5699,1.0948,0.7828),
    LeftLowerArm=Vector3.new(0.6271,0.9477,0.6166),
    LeftHand=Vector3.new(0.6933,1.1018,0.7443),
    LeftUpperLeg=Vector3.new(0.7597,1.3789,0.7694),
    LeftLowerLeg=Vector3.new(0.7420,1.0774,0.8213),
    LeftFoot=Vector3.new(0.8362,0.6279,1.2425),
    RightUpperLeg=Vector3.new(0.7597,1.3789,0.7694),
    RightLowerLeg=Vector3.new(0.7420,1.0774,0.8213),
    RightFoot=Vector3.new(0.8362,0.6279,1.2425),
}
local EXPECTED = {
    Head="123480233606534",
    UpperTorso="8650495328", LowerTorso="8650495385",
    RightUpperArm="8650495303", RightLowerArm="8650495271",
    RightHand="8650495280", LeftUpperArm="8650495273",
    LeftLowerArm="8650495270", LeftHand="8650495301",
    LeftUpperLeg="8650495362", LeftLowerLeg="8650495364",
    LeftFoot="8650495382", RightUpperLeg="8650495376",
    RightLowerLeg="8650495379", RightFoot="8650495330",
}
local PART_KEYS = {
    Head="head",
    UpperTorso="upper_torso", LowerTorso="lower_torso",
    RightUpperArm="right_upper_arm", RightLowerArm="right_lower_arm",
    RightHand="right_hand", LeftUpperArm="left_upper_arm",
    LeftLowerArm="left_lower_arm", LeftHand="left_hand",
    RightUpperLeg="right_upper_leg", RightLowerLeg="right_lower_leg",
    RightFoot="right_foot", LeftUpperLeg="left_upper_leg",
    LeftLowerLeg="left_lower_leg", LeftFoot="left_foot",
}

local active, stopped = false, false
local rng = Random.new()
local states, extras, connections = {}, {}, {}
local bytesCache, parsedCache = {}, {}
local pending, bodyJobs, epoch, fileSerial = {}, {}, 0, 0
local bloodAsset, materialAsset
local staticAssetIds = {}
local BATCH_WINDOW = 0.19
local MAX_CUTS = 4
local MAX_ANATOMY_FACES = 8500
local MAX_SKIN_FACES = 24000

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollAnatomyV15"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(172, 68)
frame.Position = UDim2.new(0, 12, 0.54, 0)
frame.BackgroundColor3 = Color3.fromRGB(24, 25, 29)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(4, 2)
label.Size = UDim2.fromOffset(164, 23)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 15
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = "Anatomy v15"
label.Parent = frame
local button = Instance.new("TextButton")
button.Position = UDim2.fromOffset(7, 29)
button.Size = UDim2.fromOffset(158, 32)
button.BorderSizePixel = 0
button.Font = Enum.Font.SourceSansBold
button.TextSize = 16
button.TextColor3 = Color3.new(1, 1, 1)
button.BackgroundColor3 = Color3.fromRGB(76, 76, 76)
button.Text = "OFF"
button.Parent = frame

local function updateButton(message)
    button.Text = message or (active and "ON" or "OFF")
    button.BackgroundColor3 = active
        and Color3.fromRGB(121, 27, 41)
        or Color3.fromRGB(76, 76, 76)
end

local function readBytes(filename)
    if bytesCache[filename] then return bytesCache[filename] end
    local req = request or http_request or (syn and syn.request)
    local data
    if req then
        local response = req({Url=BASE .. filename,Method="GET"})
        if not response or response.StatusCode ~= 200 then
            error("v15 download failed: " .. filename)
        end
        data = response.Body
    else
        data = game:HttpGet(BASE .. filename)
    end
    if type(data) ~= "string" or #data < 25 then
        error("v15 invalid or missing: " .. filename)
    end
    bytesCache[filename] = data
    return data
end

local function customAsset(filename, data)
    local getAsset = getcustomasset or getsynasset
    if not getAsset or not writefile then
        error("v15 needs getcustomasset and writefile")
    end
    fileSerial = fileSerial + 1
    local path = "ragdoll_v15_" .. tostring(fileSerial) .. "_" .. filename
    writefile(path, data)
    return getAsset(path)
end

local function staticAsset(filename)
    if staticAssetIds[filename] then return staticAssetIds[filename] end
    local id=customAsset(filename,readBytes(filename))
    staticAssetIds[filename]=id
    return id
end

local function parsedMesh(filename)
    if parsedCache[filename] then return parsedCache[filename] end
    if not buffer or not buffer.fromstring then
        error("v15 needs the Roblox Luau buffer library")
    end
    local b = buffer.fromstring(readBytes(filename))
    if buffer.readstring(b, 0, 13) ~= "version 2.00\n" then
        error("v15 unsupported mesh version: " .. filename)
    end
    local stride = buffer.readu8(b, 15)
    local vertices = buffer.readu32(b, 17)
    local faces = buffer.readu32(b, 21)
    local faceOffset = 25 + stride * vertices
    if stride ~= 36 or faces == 0 or faces > 125000
        or faceOffset + faces * 12 > buffer.len(b) then
        error("v15 unsupported mesh layout: " .. filename)
    end
    local mesh = {buf=b, stride=stride, vertices=vertices,
        faces=faces, faceOffset=faceOffset}
    parsedCache[filename] = mesh
    -- Release the initial string after conversion; avoid retaining duplicates.
    bytesCache[filename] = nil
    return mesh
end

local function owningModel(part)
    local model = part:FindFirstAncestorOfClass("Model")
    return model and model:FindFirstChildOfClass("Humanoid") and model
end

local function nearestBody(position)
    local best, bestScore
    for _, candidate in ipairs(Workspace:GetPartBoundsInRadius(position, 2)) do
        if candidate:IsA("MeshPart") and SOURCE_SIZE[candidate.Name] then
            local model = owningModel(candidate)
            if model and model ~= player.Character then
                local localPos = candidate.CFrame:PointToObjectSpace(position)
                local h = candidate.Size * 0.5
                local d = Vector3.new(
                    math.max(math.abs(localPos.X)-h.X,0),
                    math.max(math.abs(localPos.Y)-h.Y,0),
                    math.max(math.abs(localPos.Z)-h.Z,0))
                local score = d.Magnitude
                    + (candidate.Position-position).Magnitude * 0.02
                if not bestScore or score < bestScore then
                    bestScore, best = score, candidate
                end
            end
        end
    end
    return best
end

local function ratioFor(body)
    local source = SOURCE_SIZE[body.Name]
    return Vector3.new(body.Size.X/source.X,body.Size.Y/source.Y,
        body.Size.Z/source.Z)
end

local function worldNormal(body, position)
    local v = position - body.Position
    if v.Magnitude < 0.02 then return body.CFrame.LookVector end
    return v.Unit
end

local function surfacePoint(body, hit)
    local normal = worldNormal(body, hit)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {body}
    params.IgnoreWater = true
    local distance = math.max(body.Size.Magnitude, 1.5)
    local result = Workspace:Raycast(hit+normal*distance, -normal*distance*2, params)
    if result then return result.Position, result.Normal end
    return hit, normal
end

local function createMesh(body, name, meshId, textureId, tint, scale, cf)
    if not body.Parent then return nil end
    local holder = Instance.new("Part")
    holder.Name = name
    holder.Size = Vector3.new(0.01,0.01,0.01)
    holder.CFrame = cf or body.CFrame
    holder.Anchored = false
    holder.Massless = true
    holder.CanCollide = false
    holder.CanTouch = false
    holder.CanQuery = false
    holder.CastShadow = false
    holder.Color = tint or Color3.new(1,1,1)
    holder.Parent = body.Parent
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = meshId
    mesh.TextureId = textureId or ""
    mesh.Scale = scale or Vector3.new(1,1,1)
    mesh.Parent = holder
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1 = body, holder
    weld.Parent = holder
    return holder
end

local function addPart(state, holder)
    if holder then table.insert(state.parts, holder) end
    return holder
end

-- V15 keeps every original skin face until it reaches a real wound cut.
-- No centroid deletion and no random triangle thinning.
local function triangleMesh(triangles)
    if #triangles == 0 then return nil end
    local vertexCount = #triangles
    local faces = vertexCount/3
    local b = buffer.create(25+vertexCount*36+faces*12)
    buffer.writestring(b,0,"version 2.00\n")
    buffer.writeu8(b,13,12)
    buffer.writeu8(b,14,0)
    buffer.writeu8(b,15,36)
    buffer.writeu8(b,16,12)
    buffer.writeu32(b,17,vertexCount)
    buffer.writeu32(b,21,faces)
    for i, p in ipairs(triangles) do
        local k = 25+(i-1)*36
        for axis = 1,3 do buffer.writef32(b,k+(axis-1)*4,p[axis]) end
        for axis = 1,3 do buffer.writef32(b,k+12+(axis-1)*4,p[axis+3]) end
        buffer.writef32(b,k+24,p[7] or 0.5)
        buffer.writef32(b,k+28,p[8] or 0.75)
        buffer.writef32(b,k+32,0)
        buffer.writeu32(b,25+vertexCount*36+(i-1)*4,i-1)
    end
    return buffer.tostring(b)
end


-- Exact polygon subtraction: split each existing body triangle along the
-- wound boundary. All 9 mesh attributes are interpolated, preserving UVs.
local function meshVertex(buf, index)
    local pos = 25 + index * 36
    local row = {}
    for j=0,8 do row[j+1] = buffer.readf32(buf,pos+j*4) end
    return row
end

local function lerpVertex(a,b,t)
    local result={}
    for j=1,9 do result[j]=a[j]+(b[j]-a[j])*t end
    return result
end

local function cutPlanes(body,cut,factor,depthEnabled)
    local n=cut.n
    local up=math.abs(n.Y)>0.9 and Vector3.new(1,0,0)
        or Vector3.new(0,1,0)
    local tangent=up:Cross(n).Unit
    local bitangent=n:Cross(tangent).Unit
    local planes={}
    for j=0,15 do
        local angle=j*math.pi/8
        local direction=tangent*math.cos(angle)+bitangent*math.sin(angle)
        local offset=0.96+0.045*math.sin(angle*3+cut.p.X*9+cut.p.Z*8)
        planes[#planes+1]={direction=direction,limit=cut.r*factor*offset}
    end
    if depthEnabled then
        local half=body.Size*0.5
        local thickness=2*(math.abs(n.X)*half.X+
            math.abs(n.Y)*half.Y+math.abs(n.Z)*half.Z)
        planes[#planes+1]={direction=n,limit=0.065}
        planes[#planes+1]={direction=-n,limit=thickness*0.48}
    end
    return planes
end

local function signedDistance(vertex,cut,plane,ratio)
    local p=Vector3.new(vertex[1]*ratio.X,vertex[2]*ratio.Y,
        vertex[3]*ratio.Z)-cut.p
    return p:Dot(plane.direction)-plane.limit
end

-- Return the portion inside a half-space and the portion outside it.
local function splitFace(poly,cut,plane,ratio)
    local ins,outs={},{}
    local prev=poly[#poly]
    local previousDistance=signedDistance(prev,cut,plane,ratio)
    for _,current in ipairs(poly) do
        local d=signedDistance(current,cut,plane,ratio)
        local prevInside=previousDistance<=0
        local currInside=d<=0
        if prevInside~=currInside then
            local t=math.clamp(previousDistance/(previousDistance-d),0,1)
            local intersection=lerpVertex(prev,current,t)
            ins[#ins+1]=intersection
            outs[#outs+1]=intersection
        end
        if currInside then
            ins[#ins+1]=current
        else
            outs[#outs+1]=current
        end
        prev,previousDistance=current,d
    end
    return ins,outs
end

local function intersectVolume(poly,cut,planes,ratio)
    for _,plane in ipairs(planes) do
        local inside=splitFace(poly,cut,plane,ratio)
        if #inside<3 then return nil end
        poly=inside
    end
    return poly
end

local function subtractVolume(poly,cut,planes,ratio)
    -- Outside pieces are emitted immediately; the surviving inside
    -- polygon is checked against the remaining convex halfspaces.
    local output={}
    local pending={poly}
    for _,plane in ipairs(planes) do
        local nextPending={}
        for _,candidate in ipairs(pending) do
            local inside,outside=splitFace(candidate,cut,plane,ratio)
            if #outside>=3 then output[#output+1]=outside end
            if #inside>=3 then nextPending[#nextPending+1]=inside end
        end
        pending=nextPending
        if #pending==0 then break end
    end
    return output
end

local function appendFan(rows,poly,maxFaces)
    for j=2,#poly-1 do
        if #rows+3>maxFaces*3 then return false end
        rows[#rows+1]=poly[1]
        rows[#rows+1]=poly[j]
        rows[#rows+1]=poly[j+1]
    end
    return true
end


local function skinMesh(source,body,cuts)
    local ratio=ratioFor(body)
    local planes={}
    for i,cut in ipairs(cuts) do
        planes[i]=cutPlanes(body,cut,1,true)
    end
    local b=source.buf
    local rows={}
    for face=0,source.faces-1 do
        local at=source.faceOffset+face*12
        local i0=buffer.readu32(b,at)
        local i1=buffer.readu32(b,at+4)
        local i2=buffer.readu32(b,at+8)
        if i0<source.vertices and i1<source.vertices
            and i2<source.vertices then
            local polys={{meshVertex(b,i0),meshVertex(b,i1),meshVertex(b,i2)}}
            for cutIndex,cut in ipairs(cuts) do
                local kept={}
                for _,poly in ipairs(polys) do
                    local remaining=subtractVolume(poly,cut,
                        planes[cutIndex],ratio)
                    for _,piece in ipairs(remaining) do
                        kept[#kept+1]=piece
                    end
                end
                polys=kept
                if #polys==0 then break end
            end
            for _,poly in ipairs(polys) do
                -- Fail closed rather than publishing a partial surface.
                if not appendFan(rows,poly,MAX_SKIN_FACES) then
                    return nil
                end
            end
        end
        if face>0 and face%1700==0 then task.wait() end
    end
    return triangleMesh(rows)
end

local function cutDepth(body, cut)
    local n = cut.n
    local half = body.Size*0.5
    return 2*(math.abs(n.X)*half.X+
        math.abs(n.Y)*half.Y+math.abs(n.Z)*half.Z)
end

local function radiusFor(body, normal, tier)
    local n = body.CFrame:VectorToObjectSpace(normal)
    local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
    local width
    if ax>=ay and ax>=az then
        width = math.min(body.Size.Y,body.Size.Z)
    elseif ay>=az then
        width = math.min(body.Size.X,body.Size.Z)
    else
        width = math.min(body.Size.X,body.Size.Y)
    end
    return math.clamp(width*({0.095,0.25,0.42})[tier],
        0.055, tier==3 and 0.55 or 0.34)
end

local function bodyTexture(body)
    local model=body.Parent
    if body.Name=="Head" then return body.TextureID end
    local garment
    if body.Name=="LowerTorso" or body.Name:find("Leg")
        or body.Name:find("Foot") then
        garment=model and model:FindFirstChildOfClass("Pants")
        if garment and garment.PantsTemplate~="" then
            return garment.PantsTemplate
        end
    else
        garment=model and model:FindFirstChildOfClass("Shirt")
        if garment and garment.ShirtTemplate~="" then
            return garment.ShirtTemplate
        end
    end
    return body.TextureID
end

local function updateSkin(body, state)
    local revision=state.revision
    local expect=EXPECTED[body.Name]
    if not expect or not tostring(body.MeshId):find(expect,1,true) then
        warn("Anatomy v15: unknown base mesh for " .. body.Name)
        return false
    end
    local sourceName="v15-clean-" .. PART_KEYS[body.Name] .. ".mesh"
    local sourceOk, source=pcall(parsedMesh,sourceName)
    if not sourceOk then warn(source); return false end
    local ratio=ratioFor(body)
    local ok, raw=pcall(skinMesh,source,body,state.cuts)
    if not ok or not raw then
        warn("Anatomy v15: fitted skin generation failed")
        return false
    end
    local idOk, id=pcall(customAsset,"fitted-skin.mesh",raw)
    if not idOk then warn(id); return false end
    if not active or stopped or not body.Parent
        or state.revision~=revision then return false end
    if not state.skin then
        state.skin=addPart(state,createMesh(body,"Real cut skin",
            id,bodyTexture(body),body.Color,ratio))
    else
        local mesh=state.skin:FindFirstChildOfClass("SpecialMesh")
        if mesh then mesh.MeshId=id end
    end
    if state.skin then
        body.LocalTransparencyModifier=1
        if body.Name=="Head" then
            for _,decal in ipairs(body:GetChildren()) do
                if decal:IsA("Decal") then
                    if state.decals[decal]==nil then
                        state.decals[decal]=decal.Transparency
                    end
                    decal.Transparency=1
                end
            end
        end
        return true
    end
    return false
end

-- Clip original source triangles at the wound boundary. Unlike v12,
-- this does not randomly skip triangles or leave long facets hanging out.
-- All positions remain in body-local source units; UV and normals interpolate.
local function clipAnatomy(source,body,cut,tissue)
    local ratio=ratioFor(body)
    local outerPlanes=cutPlanes(body,cut,tissue=="bone" and 0.95 or 1.02,true)
    local innerPlanes=tissue=="muscle"
        and cutPlanes(body,cut,0.77,false) or nil

    local b=source.buf
    local rows={}
    local maxFaces=MAX_ANATOMY_FACES
    local r=cut.r
    local n=cut.n
    local surfaceDepth=cutDepth(body,cut)*0.48

    for face=0,source.faces-1 do
        local at=source.faceOffset+face*12
        local i0=buffer.readu32(b,at)
        local i1=buffer.readu32(b,at+4)
        local i2=buffer.readu32(b,at+8)
        if i0<source.vertices and i1<source.vertices
            and i2<source.vertices then
            local a=25+i0*36
            local bb=25+i1*36
            local c=25+i2*36
            local va=Vector3.new(buffer.readf32(b,a)*ratio.X,
                buffer.readf32(b,a+4)*ratio.Y,buffer.readf32(b,a+8)*ratio.Z)
            local vb=Vector3.new(buffer.readf32(b,bb)*ratio.X,
                buffer.readf32(b,bb+4)*ratio.Y,buffer.readf32(b,bb+8)*ratio.Z)
            local vc=Vector3.new(buffer.readf32(b,c)*ratio.X,
                buffer.readf32(b,c+4)*ratio.Y,buffer.readf32(b,c+8)*ratio.Z)
            local center=(va+vb+vc)/3
            local reach=math.max((va-center).Magnitude,
                (vb-center).Magnitude,(vc-center).Magnitude)
            local delta=center-cut.p
            local depth=-delta:Dot(n)
            local sideways=(delta+n*depth).Magnitude
            if sideways<r*1.1+reach and depth>-(0.04+reach)
                and depth<surfaceDepth+0.04+reach then
                local clipped=intersectVolume({
                    meshVertex(b,i0),meshVertex(b,i1),meshVertex(b,i2)
                },cut,outerPlanes,ratio)
                if clipped and #clipped>=3 then
                    local pieces
                    if tissue=="muscle" then
                        pieces=subtractVolume(clipped,cut,innerPlanes,ratio)
                    else
                        pieces={clipped}
                    end
                    for _,poly in ipairs(pieces) do
                        -- Avoid partial unconnected pieces if the output
                        -- budget is exceeded.
                        if not appendFan(rows,poly,maxFaces) then
                            return nil
                        end
                    end
                end
            end
        end
        if face>0 and face%7000==0 then task.wait() end
    end
    return triangleMesh(rows)
end


local function regionMesh(body, state, cut, tissue)
    local filename="v10-anatomy-"..body.Name:lower().."-"..tissue..".mesh"
    local ok, source=pcall(parsedMesh,filename)
    if not ok then
        warn("Anatomy v15 anatomy: "..tostring(source))
        return
    end
    local good,raw=pcall(clipAnatomy,source,body,cut,tissue)
    if not good or not raw then
        if not good then warn("Anatomy v15 clipping: "..tostring(raw)) end
        return
    end
    local idOk,id=pcall(customAsset,tissue.."-region.mesh",raw)
    if not idOk or not active or stopped or not body.Parent then return end
    local tint=tissue=="bone" and Color3.fromRGB(227,214,190)
        or Color3.fromRGB(148,68,71)
    return addPart(state,createMesh(body,
        (tissue=="bone" and "Local real anatomy: bone"
            or "Local real anatomy: muscle"),id,materialAsset,tint,
        ratioFor(body),body.CFrame))
end



local function restore()
    for body,state in pairs(states) do
        if body.Parent then body.LocalTransparencyModifier=state.old end
        for decal,old in pairs(state.decals) do
            if decal.Parent then decal.Transparency=old end
        end
        for _,part in ipairs(state.parts) do
            if part and part.Parent then part:Destroy() end
        end
    end
    table.clear(states)
    for _,part in ipairs(extras) do
        if part.Parent then part:Destroy() end
    end
    table.clear(extras)
end

local function readNumber(mark,keys)
    for _,key in ipairs(keys) do
        local value=mark:GetAttribute(key)
        if type(value)=="number" then return value end
        local child=mark:FindFirstChild(key)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            return child.Value
        end
    end
end

local function tierFor(mark)
    local tier=readNumber(mark,{"ImpactTier","WoundTier"})
    if tier then return math.clamp(math.floor(tier),1,3) end
    for _,key in ipairs({"WeaponType","Weapon","DamageType","ImpactType"}) do
        local w=mark:GetAttribute(key)
        if type(w)=="string" then
            w=w:lower()
            if w:find("shotgun",1,true) or w:find("buckshot",1,true)
                or w:find("blast",1,true) or w:find("explos",1,true)
                or w:find("rocket",1,true) then
                return 3
            end
        end
    end
    local n=readNumber(mark,{"PelletCount","Pellets","Projectiles"})
    if n then
        if n>=3 then return 3 end
        if n>=2 then return 2 end
    end
    local radius=readNumber(mark,{"ImpactRadius","WoundRadius"})
    if radius then
        if radius>=0.42 then return 3 end
        if radius>=0.19 then return 2 end
    end
    local dmg=readNumber(mark,{"HitDamage","Damage"})
    if dmg then
        if dmg>=65 then return 3 end
        if dmg>=32 then return 2 end
    end
    return 1
end

local function showHit(body, hit, tier, marks)
    if not active or stopped or not body.Parent then return end
    local point, worldN=surfacePoint(body,hit)
    local pos=body.CFrame:PointToObjectSpace(point)
    local n=body.CFrame:VectorToObjectSpace(worldN).Unit
    local cut={p=pos,n=n,r=radiusFor(body,worldN,tier),tier=tier}

    local state=states[body]
    if not state then
        state={old=body.LocalTransparencyModifier,parts={},decals={},
            cuts={},woundParts={},skin=nil,revision=0}
        states[body]=state
    end

    -- Every hit cuts the clean source mesh, including a single small shot.
    -- Nearby shots expand or replace the existing cut.
    for i=#state.cuts,1,-1 do
        local oldCut=state.cuts[i]
        if (oldCut.p-cut.p).Magnitude < math.max(oldCut.r,cut.r)*0.68
            and oldCut.n:Dot(cut.n)>0.62 then
            if oldCut.r>=cut.r then
                -- The previous cut already covers this strike.
                return
            end
            table.remove(state.cuts,i)
            local oldParts=table.remove(state.woundParts,i)
            if oldParts then
                for _,holder in ipairs(oldParts) do
                    if holder.Parent then holder:Destroy() end
                end
            end
        end
    end
    if #state.cuts >= MAX_CUTS then
        table.remove(state.cuts,1)
        local oldest=table.remove(state.woundParts,1)
        if oldest then
            for _,holder in ipairs(oldest) do
                if holder.Parent then holder:Destroy() end
            end
        end
    end
    table.insert(state.cuts,cut)
    state.revision=state.revision+1
    local revision=state.revision
    local woundParts={}

    local function cleanupPending()
        for _,holder in ipairs(woundParts) do
            if holder and holder.Parent then holder:Destroy() end
        end
    end

    local opened=updateSkin(body,state)
    if not active or stopped or not body.Parent
        or state.revision~=revision then
        cleanupPending()
        return
    end
    if not opened then
        cleanupPending()
        local index=table.find(state.cuts,cut)
        if index then table.remove(state.cuts,index) end
        if not state.skin then body.LocalTransparencyModifier=state.old end
    end

    if opened then
        local exposedBone=regionMesh(body,state,cut,"bone")
        if exposedBone then table.insert(woundParts,exposedBone) end
        local muscle=regionMesh(body,state,cut,"muscle")
        if muscle then table.insert(woundParts,muscle) end
        if not active or stopped or state.revision~=revision then
            cleanupPending()
            return
        end
    end
    if opened then
        table.insert(state.woundParts,woundParts)
    end

    for _,mark in ipairs(marks) do
        local decal=mark:FindFirstChildWhichIsA("Decal")
        if decal and decal.Parent then
            if state.decals[decal]==nil then
                state.decals[decal]=decal.Transparency
            end
            if opened then decal.Transparency=1 end
        end
    end
end

local function processBatch(batch)
    if stopped or not active or batch.epoch~=epoch then return end
    local body=batch.body
    if not body.Parent then return end
    local live, tier={},1
    for _,mark in ipairs(batch.marks) do
        if mark.Parent then
            table.insert(live,mark)
            tier=math.max(tier,tierFor(mark))
        end
    end
    if #live==0 then return end
    if #live>=3 then tier=3
    elseif #live>=2 then tier=math.max(tier,2) end
    local hit=body.CFrame:PointToWorldSpace(batch.localCenter)
    local jobs=bodyJobs[body]
    if not jobs then
        jobs={}
        bodyJobs[body]=jobs
    end
    jobs[#jobs+1]={hit=hit,tier=tier,marks=live,epoch=epoch}
    if #jobs>1 then return end
    task.spawn(function()
        while #jobs>0 do
            local job=jobs[1]
            if active and not stopped and job.epoch==epoch and body.Parent then
                local success,err=pcall(showHit,body,job.hit,job.tier,job.marks)
                if not success then warn("Anatomy v15 hit: "..tostring(err)) end
            end
            table.remove(jobs,1)
        end
        if bodyJobs[body]==jobs then bodyJobs[body]=nil end
    end)
end

local function queueMark(mark)
    if stopped or not active or not mark.Parent then return end
    local body=nearestBody(mark.Position)
    if not body then return end
    local localHit=body.CFrame:PointToObjectSpace(mark.Position)
    local batches=pending[body]
    if not batches then
        batches={}
        pending[body]=batches
    end
    local radius=math.clamp(body.Size.Magnitude*0.42,0.35,0.95)
    for _,batch in ipairs(batches) do
        if (batch.localCenter-localHit).Magnitude <= radius then
            table.insert(batch.marks,mark)
            batch.localCenter=batch.localCenter:Lerp(localHit,1/#batch.marks)
            return
        end
    end
    local batch={body=body,marks={mark},localCenter=localHit,epoch=epoch}
    table.insert(batches,batch)
    task.delay(BATCH_WINDOW,function()
        local index=table.find(batches,batch)
        if index then table.remove(batches,index) end
        if #batches==0 and pending[body]==batches then
            pending[body]=nil
        end
        processBatch(batch)
    end)
end

local function bloodSplat(part)
    if not active or stopped or not bloodAsset or not part.Parent then return end
    local decal=part:FindFirstChildWhichIsA("Decal")
    if not decal then return end
    local surface=Instance.new("SurfaceGui")
    surface.Name="BloodV15"
    surface.Face=decal.Face
    surface.CanvasSize=Vector2.new(512,512)
    surface.LightInfluence=0.6
    surface.Parent=part
    local image=Instance.new("ImageLabel")
    image.Size=UDim2.fromScale(1,1)
    image.BackgroundTransparency=1
    image.Image=bloodAsset
    image.Rotation=rng:NextInteger(-90,90)
    local variant=rng:NextInteger(0,3)
    image.ImageRectOffset=Vector2.new((variant%2)*627,math.floor(variant/2)*627)
    image.ImageRectSize=Vector2.new(627,627)
    image.Parent=surface
    table.insert(extras,surface)
    Debris:AddItem(surface,20)
end

table.insert(connections,button.MouseButton1Click:Connect(function()
    if active then
        active=false
        epoch=epoch+1
        table.clear(pending)
        table.clear(bodyJobs)
        restore()
        updateButton()
        return
    end
    updateButton("LOADING...")
    local ok,materials=pcall(staticAsset,"anatomy-materials.png")
    if not ok then
        warn(materials)
        updateButton("ASSET FAILED")
        return
    end
    local bloodOk,blood=pcall(staticAsset,"blood-atlas.png")
    if not bloodOk then
        warn(blood)
        updateButton("ASSET FAILED")
        return
    end
    materialAsset=materials
    bloodAsset=blood
    active=true
    epoch=epoch+1
    updateButton()
end))

table.insert(connections,Workspace.DescendantAdded:Connect(function(obj)
    if stopped or not active or not obj:IsA("BasePart") then return end
    if obj.Name=="WoundMark" then
        task.delay(0.07,function()
            if active then queueMark(obj) end
        end)
    elseif obj.Name=="BloodSplat" then
        task.delay(0.07,function() bloodSplat(obj) end)
    end
end))

env.RagdollGoreV15Stop=function()
    stopped=true
    active=false
    epoch=epoch+1
    table.clear(pending)
    table.clear(bodyJobs)
    for _,connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
