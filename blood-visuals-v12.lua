-- blood-visuals-v12.lua | Roblox Luau client | Delta-compatible custom mesh renderer
-- Regional anatomical cutaways: source meshes retain actual bone and muscle topology.
-- Anatomical source and attribution: ANATOMY_ATTRIBUTION.md (CC BY-SA 4.0).
-- The 206-bone count describes the source atlas, not 206 simulated rigid bodies.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for v = 1, 12 do
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
    UpperTorso="8650495328", LowerTorso="8650495385",
    RightUpperArm="8650495303", RightLowerArm="8650495271",
    RightHand="8650495280", LeftUpperArm="8650495273",
    LeftLowerArm="8650495270", LeftHand="8650495301",
    LeftUpperLeg="8650495362", LeftLowerLeg="8650495364",
    LeftFoot="8650495382", RightUpperLeg="8650495376",
    RightLowerLeg="8650495379", RightFoot="8650495330",
}
local PART_KEYS = {
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
local pending, epoch, fileSerial = {}, 0, 0
local bloodAsset, materialAsset
local BATCH_WINDOW = 0.19
local MAX_CUTS = 8
local MAX_ANATOMY_FACES = 2600
local MAX_SKIN_FACES = 3500

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollAnatomyV12"
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
label.Text = "Anatomy v12"
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
            error("v12 download failed: " .. filename)
        end
        data = response.Body
    else
        data = game:HttpGet(BASE .. filename)
    end
    if type(data) ~= "string" or #data < 25 then
        error("v12 invalid or missing: " .. filename)
    end
    bytesCache[filename] = data
    return data
end

local function customAsset(filename, data)
    local getAsset = getcustomasset or getsynasset
    if not getAsset or not writefile then
        error("v12 needs getcustomasset and writefile")
    end
    fileSerial = fileSerial + 1
    local path = "ragdoll_v12_" .. tostring(fileSerial) .. "_" .. filename
    writefile(path, data)
    return getAsset(path)
end

local function staticAsset(filename)
    return customAsset(filename, readBytes(filename))
end

local function parsedMesh(filename)
    if parsedCache[filename] then return parsedCache[filename] end
    if not buffer or not buffer.fromstring or not buffer.copy then
        error("v12 needs the Roblox Luau buffer library")
    end
    local b = buffer.fromstring(readBytes(filename))
    if buffer.readstring(b, 0, 13) ~= "version 2.00\n" then
        error("v12 unsupported mesh version: " .. filename)
    end
    local stride = buffer.readu8(b, 15)
    local vertices = buffer.readu32(b, 17)
    local faces = buffer.readu32(b, 21)
    local faceOffset = 25 + stride * vertices
    if stride ~= 36 or faces == 0 or faces > 125000
        or faceOffset + faces * 12 > buffer.len(b) then
        error("v12 unsupported mesh layout: " .. filename)
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

local function chooseVariant(body, localHit)
    local half = body.Size * 0.5
    local nx = localHit.X/math.max(half.X,0.01)
    local ny = localHit.Y/math.max(half.Y,0.01)
    local nz = localHit.Z/math.max(half.Z,0.01)
    local name = body.Name
    if name:find("Foot") then
        if math.abs(ny)>math.abs(nz)*0.8 then
            if nz < -0.22 then return "top_toes" end
            if nz > 0.22 then return "top_heel" end
            return "top_center"
        end
        return "front_center"
    end
    if name:find("Hand") then
        if math.abs(ny)>math.abs(nz) then return "top_center" end
        return ny < -0.22 and "front_fingers" or "front_center"
    end
    if math.abs(nx)>math.abs(nz)*1.1 then return "side_center" end
    if name:find("Torso") then
        if math.abs(nx)>0.25 and math.abs(nx)>math.abs(ny) then
            return nx < 0 and "front_left" or "front_right"
        end
        if ny>0.27 then return "front_upper" end
        if ny< -0.27 then return "front_lower" end
        return "front_center"
    end
    if ny>0.25 then return "front_upper" end
    if ny< -0.25 then return "front_lower" end
    return "front_center"
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

-- Mesh v2 writer: copy selected source faces without replacing their detailed
-- geometry with balls/cylinders. No enlargement of source bones is performed.
local function subsetMesh(source, predicate, maxScanFaces, maxResultFaces)
    local step = math.max(1, math.ceil(source.faces/maxScanFaces))
    local selected = {}
    local b = source.buf
    local vertexOffset = 25
    for f = 0, source.faces-1, step do
        local idx = source.faceOffset+f*12
        local i0 = buffer.readu32(b,idx)
        local i1 = buffer.readu32(b,idx+4)
        local i2 = buffer.readu32(b,idx+8)
        if i0 < source.vertices and i1 < source.vertices
            and i2 < source.vertices then
            local v0, v1, v2 = vertexOffset+i0*36,
                vertexOffset+i1*36, vertexOffset+i2*36
            local x = (buffer.readf32(b,v0)+buffer.readf32(b,v1)
                +buffer.readf32(b,v2))/3
            local y = (buffer.readf32(b,v0+4)+buffer.readf32(b,v1+4)
                +buffer.readf32(b,v2+4))/3
            local z = (buffer.readf32(b,v0+8)+buffer.readf32(b,v1+8)
                +buffer.readf32(b,v2+8))/3
            if predicate(x,y,z) then
                selected[#selected+1] = i0
                selected[#selected+1] = i1
                selected[#selected+1] = i2
                if #selected >= maxResultFaces*3 then break end
            end
        end
        if f > 0 and f%9000 == 0 then task.wait() end
    end
    local numV = #selected
    if numV < 9 then return nil end
    local numF = numV/3
    local out = buffer.create(25+numV*36+numF*12)
    buffer.copy(out,0,b,0,17)
    buffer.writeu32(out,17,numV)
    buffer.writeu32(out,21,numF)
    local faceStart = 25+numV*36
    for i = 0, numV-1 do
        buffer.copy(out,25+i*36,b,25+selected[i+1]*36,36)
        buffer.writeu32(out,faceStart+i*4,i)
    end
    return buffer.tostring(out)
end

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

local function cutDepth(body, cut)
    local n = cut.n
    local half = body.Size*0.5
    return 2*(math.abs(n.X)*half.X+
        math.abs(n.Y)*half.Y+math.abs(n.Z)*half.Z)
end

local function testCut(body, ratio, cut, x, y, z)
    local p = Vector3.new(x*ratio.X,y*ratio.Y,z*ratio.Z)
    local d = p-cut.p
    local depth = -d:Dot(cut.n)
    local lateral = (d+cut.n*depth).Magnitude
    return lateral, depth
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

local function buildRim(body, state, cut)
    local n = cut.n
    local up = math.abs(n.Y)>0.9 and Vector3.new(1,0,0)
        or Vector3.new(0,1,0)
    local tangent = up:Cross(n).Unit
    local bitangent = n:Cross(tangent).Unit
    local shape = {}
    local segments = 18
    local bumps = {}
    for i=1,segments do
        bumps[i] = rng:NextNumber(0.79,1.17)
    end
    local point = cut.p
    local radius = cut.r
    local function vertex(angle, radiusFactor, inward)
        local j = (math.floor(angle/(2*math.pi)*segments+0.5)%segments)+1
        local jitter = bumps[j]
        local off = tangent*(math.cos(angle)*radius*radiusFactor*jitter)
            + bitangent*(math.sin(angle)*radius*radiusFactor*jitter*0.84)
            - n*inward
        local position = point+off
        local normal = (n+off.Unit*0.16).Unit
        return {position.X,position.Y,position.Z,
            normal.X,normal.Y,normal.Z,0.72,0.72}
    end
    local function quad(a,b,c,d)
        shape[#shape+1]=a
        shape[#shape+1]=b
        shape[#shape+1]=c
        shape[#shape+1]=a
        shape[#shape+1]=c
        shape[#shape+1]=d
    end
    for i=0,segments-1 do
        local a=2*math.pi*i/segments
        local b=2*math.pi*(i+1)/segments
        local outerA=vertex(a,1.16,0.008)
        local outerB=vertex(b,1.16,0.008)
        local innerA=vertex(a,0.88,0.018)
        local innerB=vertex(b,0.88,0.018)
        quad(outerA,outerB,innerB,innerA)
        local deepA=vertex(a,0.73,0.083)
        local deepB=vertex(b,0.73,0.083)
        quad(innerA,innerB,deepB,deepA)
    end
    local raw = triangleMesh(shape)
    if not raw then return end
    local ok, rimAsset = pcall(customAsset,"tissue.mesh",raw)
    if not ok or not active or stopped or not body.Parent then return end
    -- Vertices already use the body's local coordinate system.
    addPart(state,createMesh(body,"Fitted irregular tissue rim",
        rimAsset,"",Color3.fromRGB(158,55,56),
        Vector3.new(1,1,1)))
end

local function bodyTexture(body)
    local shirt=body.Parent and body.Parent:FindFirstChildOfClass("Shirt")
    local texture=shirt and shirt.ShirtTemplate or ""
    if texture=="" then texture=body.TextureID end
    return texture
end

local function updateSkin(body, state)
    if body.Name=="Head" then return true end
    local expect=EXPECTED[body.Name]
    if not expect or not tostring(body.MeshId):find(expect,1,true) then
        warn("Anatomy v12: unknown base mesh for " .. body.Name)
        return false
    end
    local sourceName="v10-hole-" .. PART_KEYS[body.Name]
        .. "-" .. state.variant .. ".mesh"
    local sourceOk, source=pcall(parsedMesh,sourceName)
    if not sourceOk then warn(source); return false end
    local ratio=ratioFor(body)
    local ok, raw=pcall(subsetMesh,source,function(x,y,z)
        for _,cut in ipairs(state.cuts) do
            local lateral,depth=testCut(body,ratio,cut,x,y,z)
            local penetration=cutDepth(body,cut)*0.48
            -- Delete only the struck surface, not the opposite side.
            local jitter=1+0.06*math.sin(x*47+y*33+z*29)
            if depth > -0.10 and depth < penetration
                and lateral < cut.r*jitter then
                return false
            end
        end
        return true
    end,MAX_SKIN_FACES,MAX_SKIN_FACES)
    if not ok or not raw then
        warn("Anatomy v12: fitted skin generation failed")
        return false
    end
    local idOk, id=pcall(customAsset,"fitted-skin.mesh",raw)
    if not idOk then warn(id); return false end
    if not active or stopped or not body.Parent then return false end
    if not state.skin then
        state.skin=addPart(state,createMesh(body,"Real cut skin",
            id,bodyTexture(body),body.Color,ratio))
    else
        local mesh=state.skin:FindFirstChildOfClass("SpecialMesh")
        if mesh then mesh.MeshId=id end
    end
    if state.skin then
        body.LocalTransparencyModifier=1
        return true
    end
    return false
end

local function regionMesh(body, state, cut, tissue)
    local filename="v10-anatomy-"..body.Name:lower().."-"..tissue..".mesh"
    local ok, source=pcall(parsedMesh,filename)
    if not ok then warn("Anatomy v12 anatomy: "..tostring(source)); return end
    local ratio=ratioFor(body)
    local r=cut.r
    local penetration=cutDepth(body,cut)
    local success,raw=pcall(subsetMesh,source,function(x,y,z)
        local lateral,depth=testCut(body,ratio,cut,x,y,z)
        if depth < -0.06 or depth > penetration*1.05 then return false end
        if tissue=="bone" then
            return lateral < r*0.87
        end
        -- Leave a central window onto the bones and preserve adjacent
        -- genuine muscle geometry along the irregular opening edges.
        return lateral < r*1.08 and lateral > r*0.48
    end,9000,MAX_ANATOMY_FACES)
    if not success or not raw then return end
    local idOk, id=pcall(customAsset,tissue.."-region.mesh",raw)
    if not idOk or not active or stopped or not body.Parent then return end
    local placement=body.CFrame
    if body.Name=="Head" then
        -- The original NPC head asset cannot be downloaded for local
        -- boolean cuts. Shift only the clipped skull forward to be visible.
        local outward=body.CFrame:VectorToWorldSpace(cut.n)
        placement=body.CFrame + outward*(body.Size.Magnitude*0.12)
    end
    local tint=tissue=="bone" and Color3.fromRGB(230,219,200)
        or Color3.fromRGB(175,82,87)
    return addPart(state,createMesh(body,
        (tissue=="bone" and "Regional actual bones" or "Regional actual muscles"),
        id,materialAsset,tint,ratio,placement))
end

local function chipFile(body)
    local name=body.Name
    if name=="Head" then return "v10-skull-chip.mesh" end
    if name:find("Foot") then return "v10-foot-chip.mesh" end
    if name:find("Hand") then return "v10-hand-chip.mesh" end
    return "v10-limb-chip.mesh"
end

local function localChip(body, state, cut)
    local ok, id=pcall(staticAsset,chipFile(body))
    if not ok or not active or stopped or not body.Parent then return end
    local n=body.CFrame:VectorToWorldSpace(cut.n)
    local at=body.CFrame:PointToWorldSpace(cut.p)
    local cf=CFrame.lookAt(at+n*0.017,at+n)
        * CFrame.Angles(0,0,rng:NextNumber(-3.14,3.14))
    local scale=math.clamp(cut.r*1.6,0.17,0.48)
    addPart(state,createMesh(body,"Part-specific bone shard",id,
        materialAsset,Color3.fromRGB(224,213,195),
        Vector3.new(scale,scale,scale),cf))
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
            cuts={},skin=nil,variant=chooseVariant(body,pos)}
        states[body]=state
    end
    if #state.cuts >= MAX_CUTS then
        -- Only keep the latest independent openings to bound mobile work.
        table.remove(state.cuts,1)
    end
    table.insert(state.cuts,cut)

    -- A real opening in the fitted R15 body mesh, not a circular decal.
    local opened=updateSkin(body,state)
    if not opened then
        -- Never hide the intact body when its source mesh cannot be replaced.
        body.LocalTransparencyModifier=state.old
    end

    -- Each body part loads its own bone and muscle topology from the
    -- Écorché atlas: skull, ribs, pelvis, humerus, radius/ulna, carpals,
    -- phalanges, femur, tibia/fibula, tarsals and metatarsals.
    if opened or body.Name=="Head" then
        local exposedBone=regionMesh(body,state,cut,"bone")
        if tier>=2 then regionMesh(body,state,cut,"muscle") end
        -- When a narrow cut misses the underlying triangles, fall back to
        -- the proper anatomical chip for that body region, not a generic oval.
        if not exposedBone then localChip(body,state,cut) end
        -- Without an authorized head source we cannot cut its skin mesh.
        -- Avoid drawing a deceptive large red circle over the intact face.
        if opened then buildRim(body,state,cut) end
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
    local success,err=pcall(showHit,body,hit,tier,live)
    if not success then warn("Anatomy v12 hit: "..tostring(err)) end
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
    surface.Name="BloodV12"
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

env.RagdollGoreV12Stop=function()
    stopped=true
    active=false
    epoch=epoch+1
    table.clear(pending)
    for _,connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
