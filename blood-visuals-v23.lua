-- blood-visuals-v23.lua | Roblox Luau client | fitted anatomical cutaway renderer
-- Regional anatomical cutaways: source meshes retain actual bone and muscle topology.
-- Anatomical source and attribution: ANATOMY_ATTRIBUTION.md (CC BY-SA 4.0).
-- Named bone meshes are selected at each hit; they are not rigid bodies.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for v = 1, 23 do
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
local headHits = 0
local rng = Random.new()
local states, extras, connections, originalVisuals = {}, {}, {}, {}
local originalParticles = {}
local bloodSurfaces = {}
local bytesCache, parsedCache = {}, {}
local pending, bodyJobs, epoch, fileSerial = {}, {}, 0, 0
local bloodAsset, materialAsset, boneIndex
local staticAssetIds = {}
local BATCH_WINDOW = 0.19
local MAX_CUTS = 4
local MAX_ANATOMY_FACES = 8500
local MAX_SKIN_FACES = 24000
local quality = 2
local qualityNames = {"LOW", "MED", "HIGH"}
local qualityBones = {5, 10, 16}
local qualityDistance = {40, 70, 110}
local knownSplats = {"79548089109855", "127895607834399",
    "93546937207481"}
local knownWounds = {"79897068469762", "71544800327227"}

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollAnatomyV23"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(172, 94)
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
label.Text = "Anatomy v23 H:0"
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
local qualityButton = Instance.new("TextButton")
qualityButton.Position = UDim2.fromOffset(7, 64)
qualityButton.Size = UDim2.fromOffset(158, 23)
qualityButton.BorderSizePixel = 0
qualityButton.Font = Enum.Font.SourceSansBold
qualityButton.TextSize = 13
qualityButton.TextColor3 = Color3.new(1, 1, 1)
qualityButton.BackgroundColor3 = Color3.fromRGB(45, 46, 51)
qualityButton.Text = "QUALITY: MED"
qualityButton.Parent = frame

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
    local path = "ragdoll_v23_" .. tostring(fileSerial) .. "_" .. filename
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
                if candidate.Name=="Head" and d.Magnitude<0.22 then
                    score=score-0.28
                end
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
    local fit=body.Name=="Head" and 1.18 or 1
    return Vector3.new(body.Size.X/source.X,body.Size.Y/source.Y,
        body.Size.Z/source.Z)*fit
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
    holder.CastShadow = quality==3
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
    local phase=cut.p.X*9+cut.p.Y*5+cut.p.Z*8
    for j=0,15 do
        local angle=j*math.pi/8
        local direction=tangent*math.cos(angle)+bitangent*math.sin(angle)
        local offset=0.96+0.075*math.sin(angle*3+phase)
            +0.035*math.sin(angle*7-phase*0.7)
        local aspect=cut.aspect or 1
        local shape=math.sqrt((math.cos(angle)*aspect)^2
            +(math.sin(angle)/aspect)^2)
        planes[#planes+1]={direction=direction,
            limit=cut.r*factor*offset*shape}
    end
    if depthEnabled then
        local half=body.Size*0.5
        local thickness=2*(math.abs(n.X)*half.X+
            math.abs(n.Y)*half.Y+math.abs(n.Z)*half.Z)
        planes[#planes+1]={direction=n,limit=0.065}
        planes[#planes+1]={direction=-n,
            limit=thickness*(cut.depth or 0.48)}
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
    local factor=body.Name=="Head" and ({0.075,0.15,0.24})[tier]
        or ({0.085,0.19,0.30})[tier]
    return math.clamp(width*factor,0.045,
        body.Name=="Head" and 0.29 or 0.42)
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
        warn("Anatomy v23: unknown base mesh for " .. body.Name)
        return false
    end
    local sourceName=body.Name=="Head" and "v17-head.mesh"
        or "v15-clean-" .. PART_KEYS[body.Name] .. ".mesh"
    local sourceOk, source=pcall(parsedMesh,sourceName)
    if not sourceOk then warn(source); return false end
    local ratio=ratioFor(body)
    local ok, raw=pcall(skinMesh,source,body,state.cuts)
    if not ok or not raw then
        warn("Anatomy v23: fitted skin generation failed")
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
local function clipAnatomy(source,body,cut,tissue,firstFace,lastFace)
    local ratio=ratioFor(body)
    local outerPlanes=cutPlanes(body,cut,tissue=="bone" and 0.95 or 1.02,true)
    local innerPlanes=tissue=="muscle"
        and cutPlanes(body,cut,0.38,false) or nil

    local b=source.buf
    local rows={}
    local maxFaces=body.Name=="Head" and 14500 or MAX_ANATOMY_FACES
    local r=cut.r
    local n=cut.n
    local surfaceDepth=cutDepth(body,cut)*(cut.depth or 0.48)

    for face=firstFace or 0,lastFace or source.faces-1 do
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
    return triangleMesh(rows), #rows/3
end


local function regionMesh(body, state, cut, tissue)
    if quality==1 and tissue=="muscle" then return end
    local filename="v10-anatomy-"..body.Name:lower().."-"..tissue..".mesh"
    local ok, source=pcall(parsedMesh,filename)
    if not ok then
        warn("Anatomy v23 anatomy: "..tostring(source))
        return
    end
    local tint=tissue=="bone" and Color3.fromRGB(227,214,190)
        or Color3.fromRGB(148,68,71)
    if tissue=="bone" and boneIndex and boneIndex[body.Name] then
        local visible={}
        for _,structure in ipairs(boneIndex[body.Name]) do
            local first=structure.first
            local good,raw,count=pcall(clipAnatomy,source,body,cut,
                tissue,first,first+structure.count-1)
            if not good then
                warn("Anatomy v23 bone clipping: "..tostring(raw))
            elseif raw then
                visible[#visible+1]={name=structure.name,raw=raw,
                    count=count,bone=structure.bone}
            end
        end
        table.sort(visible,function(a,b) return a.count>b.count end)
        local holders={}
        for i=1,math.min(#visible,qualityBones[quality]) do
            local structure=visible[i]
            local idOk,id=pcall(customAsset,"named-bone.mesh",structure.raw)
            if idOk and active and not stopped and body.Parent then
                local label=(structure.bone and "Bone: " or "Anatomy: ")
                    ..structure.name
                local holder=addPart(state,createMesh(body,label,id,
                    materialAsset,tint,ratioFor(body),body.CFrame))
                if holder then holders[#holders+1]=holder end
            end
        end
        return holders
    end
    local good,raw=pcall(clipAnatomy,source,body,cut,tissue)
    if not good or not raw then
        if not good then warn("Anatomy v23 clipping: "..tostring(raw)) end
        return
    end
    local idOk,id=pcall(customAsset,tissue.."-region.mesh",raw)
    if not idOk or not active or stopped or not body.Parent then return end
    return addPart(state,createMesh(body,"Local anatomy: "..tissue,
        id,materialAsset,tint,ratioFor(body),body.CFrame))
end

local function organMesh(body,state,cut,organ)
    if body.Name~="UpperTorso" or quality==1 then return end
    if organ=="lungs" and quality<3 then return end
    local ok,source=pcall(parsedMesh,"v18-organ-"..organ..".mesh")
    if not ok then warn("Anatomy v23 organ: "..tostring(source)); return end
    local good,raw=pcall(clipAnatomy,source,body,cut,"organ")
    if not good then warn("Anatomy v23 organ clipping: "..tostring(raw)) end
    if not good or not raw then return end
    local idOk,id=pcall(customAsset,organ.."-wound.mesh",raw)
    if not idOk or not active or stopped or not body.Parent then return end
    local tint=organ=="heart" and Color3.fromRGB(130,50,59)
        or Color3.fromRGB(151,81,87)
    return addPart(state,createMesh(body,"Exposed "..organ,id,
        materialAsset,tint,ratioFor(body),body.CFrame))
end

local function woundFill(body,state,cut)
    local sourceOk,source=pcall(parsedMesh,
        "v15-clean-"..PART_KEYS[body.Name]..".mesh")
    if not sourceOk then return end
    local ratio=ratioFor(body)
    local depth=cutDepth(body,cut)*math.min(0.78,
        (cut.depth or 0.48)+0.08)
    local outerPlanes=cutPlanes(body,cut,0.94,true)
    local rows={}
    local sourceBuffer=source.buf
    for face=0,source.faces-1 do
        local at=source.faceOffset+face*12
        local i0=buffer.readu32(sourceBuffer,at)
        local i1=buffer.readu32(sourceBuffer,at+4)
        local i2=buffer.readu32(sourceBuffer,at+8)
        if i0<source.vertices and i1<source.vertices
            and i2<source.vertices then
            local clipped=intersectVolume({meshVertex(sourceBuffer,i0),
                meshVertex(sourceBuffer,i1),meshVertex(sourceBuffer,i2)},
                cut,outerPlanes,ratio)
            if clipped then
                for _,poly in ipairs({clipped}) do
                    local moved={}
                    for _,vertex in ipairs(poly) do
                        local row=table.clone(vertex)
                        row[1]=row[1]-cut.n.X*depth/ratio.X
                        row[2]=row[2]-cut.n.Y*depth/ratio.Y
                        row[3]=row[3]-cut.n.Z*depth/ratio.Z
                        row[7]=0.75+math.clamp((row[1]*ratio.X-cut.p.X)
                            /math.max(cut.r,0.01),-1,1)*0.13
                        row[8]=0.75+math.clamp((row[2]*ratio.Y-cut.p.Y)
                            /math.max(cut.r,0.01),-1,1)*0.13
                        moved[#moved+1]=row
                    end
                    if not appendFan(rows,moved,MAX_SKIN_FACES) then
                        return
                    end
                end
            end
        end
    end
    local raw=triangleMesh(rows)
    if not raw then return end
    local ok,id=pcall(customAsset,"deep-tissue.mesh",raw)
    if not ok or not active or not body.Parent then return end
    return addPart(state,createMesh(body,"Deep fitted tissue",
        id,materialAsset,Color3.fromRGB(106,54,59),ratio,body.CFrame))
end



local function suppressVisual(part, hidePart)
    if not part or not part.Parent then return end
    for _,obj in ipairs(part:GetDescendants()) do
        if obj:IsA("Decal") or obj:IsA("Texture") then
            if originalVisuals[obj]==nil then
                originalVisuals[obj]=obj.Transparency
            end
            obj.Transparency=1
        end
    end
    if hidePart and part:IsA("BasePart") then
        if originalVisuals[part]==nil then
            originalVisuals[part]=part.Transparency
        end
        part.Transparency=1
    end
end

local function toneParticle(emitter)
    if not emitter or not emitter.Parent or originalParticles[emitter] then
        return
    end
    local name=emitter.Name:lower()
    if not (name:find("spray",1,true) or name:find("mist",1,true)
        or name:find("blood",1,true)) then return end
    originalParticles[emitter]={color=emitter.Color,
        light=emitter.LightEmission,size=emitter.Size}
    emitter.Color=ColorSequence.new(Color3.fromRGB(87,20,27),
        Color3.fromRGB(47,12,18))
    emitter.LightEmission=0
    emitter.Size=NumberSequence.new(name:find("mist",1,true)
        and 0.18 or 0.11)
end

local function impactSpray(body,cut)
    if quality==1 or not active or not body.Parent then return end
    local profile=cut.profile or {speed=NumberRange.new(3,7),
        count=5,spread=25,kind="bullet"}
    local attachment=Instance.new("Attachment")
    attachment.Name="Local impact spray"
    attachment.CFrame=CFrame.lookAt(cut.p,cut.p+cut.n)
    attachment.Parent=body
    local emitter=Instance.new("ParticleEmitter")
    emitter.Name="Dark directional spray"
    emitter.Texture="rbxassetid://93548634539367"
    emitter.Color=ColorSequence.new(Color3.fromRGB(77,19,25),
        Color3.fromRGB(44,12,17))
    emitter.LightEmission=0
    emitter.Rate=0
    emitter.Enabled=false
    emitter.EmissionDirection=Enum.NormalId.Front
    emitter.SpreadAngle=Vector2.new(profile.spread,profile.spread)
    emitter.Speed=profile.speed
    emitter.Lifetime=profile.kind=="blast"
        and NumberRange.new(0.25,0.68) or NumberRange.new(0.20,0.46)
    emitter.Drag=2
    emitter.Acceleration=Vector3.new(0,-Workspace.Gravity*0.6,0)
    emitter.Size=NumberSequence.new({
        NumberSequenceKeypoint.new(0,0.08),
        NumberSequenceKeypoint.new(1,0.015),
    })
    emitter.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,0.14),
        NumberSequenceKeypoint.new(1,1),
    })
    emitter.Parent=attachment
    emitter:Emit(math.min(20,quality==3 and profile.count
        or math.max(2,math.floor(profile.count*0.65))))
    extras[#extras+1]=attachment
    Debris:AddItem(attachment,1.5)
end

local function restore()
    for body,state in pairs(states) do
        if body.Parent then body.LocalTransparencyModifier=state.old end
        if body.Parent and state.oldColor then body.Color=state.oldColor end
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
    table.clear(bloodSurfaces)
    for visual,old in pairs(originalVisuals) do
        if visual.Parent then visual.Transparency=old end
    end
    table.clear(originalVisuals)
    for emitter,old in pairs(originalParticles) do
        if emitter.Parent then
            emitter.Color=old.color
            emitter.LightEmission=old.light
            emitter.Size=old.size
        end
    end
    table.clear(originalParticles)
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

local function weaponProfile(marks)
    local name=""
    for _,mark in ipairs(marks) do
        for _,key in ipairs({"WeaponType","Weapon","WeaponName",
            "ToolName","Gun","DamageType"}) do
            local value=mark:GetAttribute(key)
            local child=mark:FindFirstChild(key)
            if type(value)=="string" and value~="" then
                name=value:lower()
                break
            elseif child and child:IsA("StringValue") then
                name=child.Value:lower()
                break
            end
        end
        if name~="" then break end
    end
    if name=="" and player.Character then
        local tool=player.Character:FindFirstChildOfClass("Tool")
        if tool then name=tool.Name:lower() end
    end
    local function contains(words)
        for _,word in ipairs(words) do
            if name:find(word,1,true) then return true end
        end
        return false
    end
    if contains({"rocket","grenade","explos","blast","c4"}) then
        return {kind="blast",radius=1.18,depth=0.68,
            speed=NumberRange.new(6,13),count=16,spread=65}
    end
    if contains({"shotgun","buck","spas","remington"}) then
        return {kind="shotgun",radius=1.10,depth=0.46,
            speed=NumberRange.new(4,8),count=12,spread=47}
    end
    if contains({"knife","blade","machete","sword"}) then
        return {kind="blade",radius=1.03,depth=0.23,
            speed=NumberRange.new(1.5,4),count=4,spread=12,
            aspect=1.7}
    end
    if contains({"ak","m4","ar","rifle","carbine","smg","mp5",
        "uzi"}) then
        return {kind="rifle",radius=0.94,depth=0.62,
            speed=NumberRange.new(5,10),count=7,spread=18}
    end
    if contains({"pistol","glock","revolver","9mm","desert"}) then
        return {kind="pistol",radius=0.83,depth=0.32,
            speed=NumberRange.new(3,6),count=4,spread=22}
    end
    if #marks>=3 then
        return {kind="burst",radius=1.05,depth=0.52,
            speed=NumberRange.new(4,8),count=8,spread=30}
    end
    return {kind="bullet",radius=1,depth=0.48,
        speed=NumberRange.new(3,7),count=5,spread=25}
end

local function severeHeadImpact(body,cut,marks,state)
    local boneOk,boneSource=pcall(parsedMesh,"v10-anatomy-head-bone.mesh")
    if not boneOk then warn("Anatomy v23 skull: "..tostring(boneSource)); return end
    local cutOk,boneRaw=pcall(skinMesh,boneSource,body,state.headCuts)
    if not cutOk or not boneRaw then
        warn("Anatomy v23 skull cut failed: "..tostring(boneRaw))
        return
    end
    local idOk,boneId=pcall(customAsset,"damaged-skull.mesh",boneRaw)
    if not idOk then warn("Anatomy v23 skull load: "..tostring(boneId)); return end
    if not active or stopped or not body.Parent then return end

    local ratio=ratioFor(body)
    if not state.headBone then
        state.headBone=addPart(state,createMesh(body,"Fitted full skull",
            boneId,materialAsset,Color3.fromRGB(225,211,188),ratio,
            body.CFrame))
    else
        local mesh=state.headBone:FindFirstChildOfClass("SpecialMesh")
        if mesh then mesh.MeshId=boneId end
    end
    local brainOk,brainId=pcall(staticAsset,"v21-brain.mesh")
    if brainOk and not state.brain then
        state.brain=addPart(state,createMesh(body,"Folded brain",
            brainId,materialAsset,Color3.fromRGB(153,91,101),ratio*1.08,
            body.CFrame))
    end
    local muscleOk,muscleSource=pcall(parsedMesh,
        "v10-anatomy-head-muscle.mesh")
    if muscleOk then
        local meshOk,muscleRaw=pcall(skinMesh,muscleSource,body,
            state.headCuts)
        if meshOk and muscleRaw then
            local assetOk,muscleId=pcall(customAsset,
                "damaged-face-muscle.mesh",muscleRaw)
            if assetOk then
                if not state.headMuscle then
                    state.headMuscle=addPart(state,createMesh(body,
                        "Fitted facial muscles",muscleId,materialAsset,
                        Color3.fromRGB(158,75,82),ratio,body.CFrame))
                else
                    local mesh=state.headMuscle:FindFirstChildOfClass(
                        "SpecialMesh")
                    if mesh then mesh.MeshId=muscleId end
                end
            end
        end
    end
    if state.headBone then
        body.LocalTransparencyModifier=1
        for _,decal in ipairs(body:GetChildren()) do
            if decal:IsA("Decal") then
                if state.decals[decal]==nil then
                    state.decals[decal]=decal.Transparency
                end
                decal.Transparency=1
            end
        end
        headHits=headHits+1
        label.Text="v23 H:"..headHits.." "..cut.profile.kind:upper()
        for _,mark in ipairs(marks) do suppressVisual(mark,true) end
        impactSpray(body,cut)
    end
end

local function headTissueAtSurface(body,state,cut,tissue,protrusion)
    local ok,source=pcall(parsedMesh,
        "v10-anatomy-head-"..tissue..".mesh")
    if not ok then return end
    local good,raw=pcall(clipAnatomy,source,body,cut,tissue)
    if not good or not raw then return end
    local data=buffer.fromstring(raw)
    local count=buffer.readu32(data,17)
    local ratio=ratioFor(body)
    local nearest=math.huge
    for i=0,count-1 do
        local at=25+i*36
        local p=Vector3.new(buffer.readf32(data,at)*ratio.X,
            buffer.readf32(data,at+4)*ratio.Y,
            buffer.readf32(data,at+8)*ratio.Z)
        nearest=math.min(nearest,(cut.p-p):Dot(cut.n))
    end
    local shift=math.clamp(nearest+protrusion,0,0.39)
    for i=0,count-1 do
        local at=25+i*36
        buffer.writef32(data,at,buffer.readf32(data,at)
            +cut.n.X*shift/ratio.X)
        buffer.writef32(data,at+4,buffer.readf32(data,at+4)
            +cut.n.Y*shift/ratio.Y)
        buffer.writef32(data,at+8,buffer.readf32(data,at+8)
            +cut.n.Z*shift/ratio.Z)
    end
    local idOk,id=pcall(customAsset,"localized-"..tissue..".mesh",
        buffer.tostring(data))
    if not idOk or not active or not body.Parent then return end
    local tint=tissue=="bone" and Color3.fromRGB(219,205,182)
        or Color3.fromRGB(152,74,79)
    return addPart(state,createMesh(body,"Local fitted head "..tissue,id,
        materialAsset,tint,ratio,body.CFrame))
end

local function localHeadImpact(body,cut,marks,state)
    local n=body.CFrame:VectorToWorldSpace(cut.n)
    local point=body.CFrame:PointToWorldSpace(cut.p)
    local color=body.Color
    if color.R>0.82 and color.G>0.82 and color.B>0.82
        and not state.oldColor then
        state.oldColor=color
        body.Color=Color3.fromRGB(194,152,132)
    end
    state.headSmallParts=state.headSmallParts or {}
    if bloodAsset then
        local anchor=Instance.new("Part")
        anchor.Name="Invisible wound surface"
        local width=math.clamp(cut.r*2.3,0.18,0.54)
        anchor.Size=Vector3.new(width,width,0.01)
        anchor.CFrame=CFrame.lookAt(point+n*0.018,point+n)
        anchor.Anchored=false
        anchor.Massless=true
        anchor.CanCollide=false
        anchor.CanTouch=false
        anchor.CanQuery=false
        anchor.Transparency=1
        anchor.Parent=body.Parent
        local weld=Instance.new("WeldConstraint")
        weld.Part0,weld.Part1=body,anchor
        weld.Parent=anchor
        state.parts[#state.parts+1]=anchor
        state.headSmallParts[#state.headSmallParts+1]=anchor
        local surface=Instance.new("SurfaceGui")
        surface.Name="Localized head wound"
        surface.Adornee=anchor
        surface.Face=Enum.NormalId.Front
        surface.CanvasSize=Vector2.new(256,256)
        surface.LightInfluence=0.8
        surface.Parent=gui.Parent
        local image=Instance.new("ImageLabel")
        image.Size=UDim2.fromScale(1,1)
        image.BackgroundTransparency=1
        image.Image=bloodAsset
        image.ImageRectOffset=Vector2.new(0,0)
        image.ImageRectSize=Vector2.new(627,627)
        image.ImageColor3=Color3.fromRGB(94,53,58)
        image.ImageTransparency=0.12
        image.Rotation=rng:NextInteger(-40,40)
        image.Parent=surface
        state.parts[#state.parts+1]=surface
        state.headSmallParts[#state.headSmallParts+1]=surface
    end
    local holder=headTissueAtSurface(body,state,cut,"bone",0.085)
    local muscle=headTissueAtSurface(body,state,cut,"muscle",0.025)
    if muscle then state.headSmallParts[#state.headSmallParts+1]=muscle end
    if not holder then
        local ok,id=pcall(staticAsset,"v10-skull-chip.mesh")
        if ok and body.Parent then
        local cf=CFrame.lookAt(point+n*0.055,point+n)
            *CFrame.Angles(0,0,rng:NextNumber(-1.4,1.4))
        local size=math.clamp(cut.r*10,0.9,1.6)
        holder=addPart(state,createMesh(body,
            "Local modeled skull fragment",id,materialAsset,
            Color3.fromRGB(222,207,182),Vector3.new(size,size,size),cf))
        end
    end
    if holder then state.headSmallParts[#state.headSmallParts+1]=holder end
    for _,mark in ipairs(marks) do suppressVisual(mark,true) end
    headHits=headHits+1
    label.Text="v23 H:"..headHits.." LOCAL"
    impactSpray(body,cut)
end

local function headImpact(body,cut,marks,state)
    state.headCuts=state.headCuts or {}
    local nearby
    for _,previous in ipairs(state.headCuts) do
        if (previous.p-cut.p).Magnitude<math.max(previous.r,cut.r)*0.65 then
            nearby=previous
            break
        end
    end
    if nearby then
        nearby.r=math.min(0.31,math.max(nearby.r,cut.r)*1.12)
        nearby.depth=math.max(nearby.depth or 0.48,cut.depth or 0.48)
    else
        if #state.headCuts>=3 then table.remove(state.headCuts,1) end
        table.insert(state.headCuts,cut)
    end
    local weight=cut.profile.kind=="blast" and 4
        or cut.profile.kind=="shotgun" and 3
        or cut.tier==3 and 2 or 1
    state.headDamage=(state.headDamage or 0)+weight
    if state.headDamage>=4 then
        if state.headSmallParts then
            for _,part in ipairs(state.headSmallParts) do
                if part.Parent then part:Destroy() end
            end
            table.clear(state.headSmallParts)
        end
        severeHeadImpact(body,cut,marks,state)
    elseif nearby then
        for _,mark in ipairs(marks) do suppressVisual(mark,true) end
        impactSpray(body,cut)
    else
        localHeadImpact(body,cut,marks,state)
    end
end

local function showHit(body, hit, tier, marks, profile)
    if not active or stopped or not body.Parent then return end
    local point, worldN=surfacePoint(body,hit)
    local camera=Workspace.CurrentCamera
    if camera and (camera.CFrame.Position-point).Magnitude
        > qualityDistance[quality] then return end
    local pos=body.CFrame:PointToObjectSpace(point)
    local n=body.CFrame:VectorToObjectSpace(worldN).Unit
    profile=profile or weaponProfile(marks)
    local cut={p=pos,n=n,r=radiusFor(body,worldN,tier)*profile.radius,
        tier=tier,depth=profile.depth,aspect=profile.aspect,
        profile=profile}

    local state=states[body]
    if not state then
        state={old=body.LocalTransparencyModifier,parts={},decals={},
            cuts={},woundParts={},skin=nil,revision=0}
        states[body]=state
    end
    if body.Name=="Head" then
        headImpact(body,cut,marks,state)
        return
    end

    -- Every hit cuts the clean source mesh, including a single small shot.
    -- Nearby shots expand or replace the existing cut.
    for i=#state.cuts,1,-1 do
        local oldCut=state.cuts[i]
        if (oldCut.p-cut.p).Magnitude < math.max(oldCut.r,cut.r)*0.68
            and oldCut.n:Dot(cut.n)>0.62 then
            if oldCut.r>=cut.r then
                -- The previous cut already covers this strike.
                for _,mark in ipairs(marks) do
                    suppressVisual(mark,true)
                end
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
        local fill=woundFill(body,state,cut)
        if fill then table.insert(woundParts,fill) end
        if body.Name=="UpperTorso" then
            local heart=organMesh(body,state,cut,"heart")
            if heart then table.insert(woundParts,heart) end
            local lungs=organMesh(body,state,cut,"lungs")
            if lungs then table.insert(woundParts,lungs) end
        end
        local exposedBones=regionMesh(body,state,cut,"bone")
        if exposedBones then
            for _,bone in ipairs(exposedBones) do
                table.insert(woundParts,bone)
            end
        end
        local muscle=regionMesh(body,state,cut,"muscle")
        if muscle then table.insert(woundParts,muscle) end
        if not active or stopped or state.revision~=revision then
            cleanupPending()
            return
        end
    end
    if opened then
        table.insert(state.woundParts,woundParts)
        label.Text="v23 H:"..headHits.." "..profile.kind:upper()
        impactSpray(body,cut)
    end

    for _,mark in ipairs(marks) do
        local decal=mark:FindFirstChildWhichIsA("Decal")
        if decal and decal.Parent then
            if state.decals[decal]==nil then
                state.decals[decal]=decal.Transparency
            end
            if opened then suppressVisual(mark,false) end
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
    jobs[#jobs+1]={hit=hit,tier=tier,marks=live,
        profile=weaponProfile(live),epoch=epoch}
    if #jobs>1 then return end
    task.spawn(function()
        while #jobs>0 do
            local job=jobs[1]
            if active and not stopped and job.epoch==epoch and body.Parent then
                local success,err=pcall(showHit,body,job.hit,job.tier,
                    job.marks,job.profile)
                if not success then warn("Anatomy v23 hit: "..tostring(err)) end
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

local function isBloodSurface(part)
    local name=part.Name:lower()
    if not name:find("blood",1,true) then return false end
    if name:find("emitter",1,true) or name:find("spray",1,true)
        or name:find("mist",1,true) then return false end
    return true
end

local function bloodSplat(part)
    if not active or stopped or not bloodAsset or not part.Parent then return end
    local decal=part:FindFirstChildWhichIsA("Decal")
    local face=decal and decal.Face or Enum.NormalId.Top
    if bloodSurfaces[part] and bloodSurfaces[part].Parent then return end
    local surface=Instance.new("SurfaceGui")
    surface.Name="BloodV23"
    surface.Face=face
    surface.Adornee=part
    surface.CanvasSize=Vector2.new(512,512)
    surface.LightInfluence=0.8
    surface.Parent=gui.Parent
    local image=Instance.new("ImageLabel")
    local size=part.Size
    local width,height=size.X,size.Z
    if face==Enum.NormalId.Front or face==Enum.NormalId.Back then
        width,height=size.X,size.Y
    elseif face==Enum.NormalId.Left
        or face==Enum.NormalId.Right then
        width,height=size.Z,size.Y
    end
    local maxStuds=quality==3 and 1.75 or 1.25
    image.AnchorPoint=Vector2.new(0.5,0.5)
    image.Position=UDim2.fromScale(0.5,0.5)
    image.Size=UDim2.fromScale(math.min(1,maxStuds/math.max(width,0.01)),
        math.min(1,maxStuds/math.max(height,0.01)))
    image.BackgroundTransparency=1
    image.Image=bloodAsset
    image.ImageColor3=Color3.fromRGB(119,73,75)
    image.ImageTransparency=0.14
    image.Rotation=rng:NextInteger(-90,90)
    local variant=rng:NextInteger(0,3)
    image.ImageRectOffset=Vector2.new((variant%2)*627,math.floor(variant/2)*627)
    image.ImageRectSize=Vector2.new(627,627)
    image.Parent=surface
    suppressVisual(part,true)
    bloodSurfaces[part]=surface
    table.insert(extras,surface)
    Debris:AddItem(surface,90)
end

local function knownBloodDecal(obj)
    if not obj:IsA("Decal") then return nil end
    local texture=obj.Texture
    for _,id in ipairs(knownSplats) do
        if texture:find(id,1,true) then return "splat" end
    end
    for _,id in ipairs(knownWounds) do
        if texture:find(id,1,true) then return "wound" end
    end
end

local function handleKnownDecal(obj)
    local kind=knownBloodDecal(obj)
    local part=obj.Parent
    if not kind or not part or not part:IsA("BasePart") then return end
    if kind=="splat" then bloodSplat(part)
    else suppressVisual(part,true) end
end

table.insert(connections,qualityButton.MouseButton1Click:Connect(function()
    quality=quality%3+1
    qualityButton.Text="QUALITY: "..qualityNames[quality]
end))

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
    local indexOk,index=pcall(function()
        return HttpService:JSONDecode(readBytes("v15-bone-index.json"))
    end)
    if not indexOk or type(index)~="table" then
        warn("Anatomy v23 bone index failed: "..tostring(index))
        updateButton("ASSET FAILED")
        return
    end
    boneIndex=index
    active=true
    epoch=epoch+1
    updateButton()
    local fx=Workspace:FindFirstChild("ShooterFx",true)
    if fx then
        local checked=0
        for _,obj in ipairs(fx:GetDescendants()) do
            if obj:IsA("ParticleEmitter") then
                toneParticle(obj)
            elseif obj:IsA("BasePart") then
                if obj.Name=="WoundStain" then
                    suppressVisual(obj,true)
                elseif isBloodSurface(obj) and checked<80 then
                    checked=checked+1
                    bloodSplat(obj)
                end
            end
        end
    end
    local checkedDecals=0
    for _,obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Decal") and knownBloodDecal(obj) then
            handleKnownDecal(obj)
            checkedDecals=checkedDecals+1
            if checkedDecals>=250 then break end
        end
    end
end))

table.insert(connections,Workspace.DescendantAdded:Connect(function(obj)
    if stopped or not active then return end
    if obj:IsA("ParticleEmitter") then
        if obj:FindFirstAncestor("ShooterFx") then toneParticle(obj) end
        return
    end
    if obj:IsA("Decal") and knownBloodDecal(obj) then
        task.delay(0.05,function()
            if active then handleKnownDecal(obj) end
        end)
        return
    end
    if not obj:IsA("BasePart") then return end
    if obj.Name=="WoundMark" then
        task.delay(0.07,function()
            if active then queueMark(obj) end
        end)
    elseif isBloodSurface(obj) and obj:FindFirstAncestor("ShooterFx") then
        task.delay(0.07,function() bloodSplat(obj) end)
    elseif obj.Name=="WoundStain" then
        task.delay(0.07,function()
            if active then suppressVisual(obj,true) end
        end)
    end
end))

env.RagdollGoreV23Stop=function()
    stopped=true
    active=false
    epoch=epoch+1
    table.clear(pending)
    table.clear(bodyJobs)
    for _,connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
