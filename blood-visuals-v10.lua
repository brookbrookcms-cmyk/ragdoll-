-- Ragdoll Physics v10: fitted local anatomy visuals for the NPC2 R15 rig.
-- Mesh anatomy adaptation: Écorché / BodyParts3D / Z-Anatomy, CC BY-SA 4.0.
-- See ANATOMY_ATTRIBUTION.md in the repository for full credits.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for version = 1, 10 do
    local stop = env["RagdollGoreV" .. version .. "Stop"]
    if stop then pcall(stop) end
end

local BASE = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/"
local EXPECTED = {
    UpperTorso = "8650495328", LowerTorso = "8650495385",
    RightUpperArm = "8650495303", RightLowerArm = "8650495271",
    RightHand = "8650495280", LeftUpperArm = "8650495273",
    LeftLowerArm = "8650495270", LeftHand = "8650495301",
    LeftUpperLeg = "8650495362", LeftLowerLeg = "8650495364",
    LeftFoot = "8650495382", RightUpperLeg = "8650495376",
    RightLowerLeg = "8650495379", RightFoot = "8650495330",
}
local SOURCE_SIZE = {
    UpperTorso = Vector3.new(1.8154, 1.7732, 1.1102),
    LowerTorso = Vector3.new(1.6962, 0.5661, 0.9525),
    RightUpperArm = Vector3.new(0.5699, 1.0948, 0.7828),
    RightLowerArm = Vector3.new(0.6271, 0.9477, 0.6166),
    RightHand = Vector3.new(0.6933, 1.1018, 0.7443),
    LeftUpperArm = Vector3.new(0.5699, 1.0948, 0.7828),
    LeftLowerArm = Vector3.new(0.6271, 0.9477, 0.6166),
    LeftHand = Vector3.new(0.6933, 1.1018, 0.7443),
    LeftUpperLeg = Vector3.new(0.7597, 1.3789, 0.7694),
    LeftLowerLeg = Vector3.new(0.7420, 1.0774, 0.8213),
    LeftFoot = Vector3.new(0.8362, 0.6279, 1.2425),
    RightUpperLeg = Vector3.new(0.7597, 1.3789, 0.7694),
    RightLowerLeg = Vector3.new(0.7420, 1.0774, 0.8213),
    RightFoot = Vector3.new(0.8362, 0.6279, 1.2425),
}

local active = false
local stopped = false
local rng = Random.new()
local cache = {}
local states = {}
local extras = {}
local connections = {}
local bloodAsset
local anatomyAsset

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollAnatomyV10"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(148, 67)
frame.Position = UDim2.new(0, 12, 0.55, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 27, 29)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(142, 23)
title.Position = UDim2.fromOffset(3, 2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Anatomy v10"
title.Parent = frame
local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(134, 32)
button.Position = UDim2.fromOffset(7, 29)
button.BackgroundColor3 = Color3.fromRGB(76, 76, 76)
button.BorderSizePixel = 0
button.Font = Enum.Font.SourceSansBold
button.TextSize = 17
button.TextColor3 = Color3.new(1, 1, 1)
button.Text = "OFF"
button.Parent = frame

local function updateButton(message)
    button.Text = message or (active and "ON" or "OFF")
    button.BackgroundColor3 = active
        and Color3.fromRGB(132, 27, 39)
        or Color3.fromRGB(76, 76, 76)
end

local function asset(filename)
    if cache[filename] then return cache[filename] end
    local customAsset = getcustomasset or getsynasset
    if not customAsset or not writefile then error("Delta needs custom assets") end
    local url = BASE .. filename
    local requestFn = request or http_request or (syn and syn.request)
    local bytes
    if requestFn then
        local response = requestFn({Url = url, Method = "GET"})
        if response.StatusCode ~= 200 then error("Download: " .. filename) end
        bytes = response.Body
    else
        bytes = game:HttpGet(url)
    end
    if not bytes or #bytes < 64 then error("Empty: " .. filename) end
    local path = "ragdoll_v10_" .. filename
    writefile(path, bytes)
    local id = customAsset(path)
    cache[filename] = id
    return id
end

local function owningModel(part)
    local model = part:FindFirstAncestorOfClass("Model")
    return model and model:FindFirstChildOfClass("Humanoid") and model
end

local function nearestBody(position)
    local best, bestScore
    for _, candidate in ipairs(Workspace:GetPartBoundsInRadius(position, 2)) do
        if candidate:IsA("MeshPart")
            and (EXPECTED[candidate.Name] or candidate.Name == "Head")
            and owningModel(candidate)
            and owningModel(candidate) ~= player.Character then
            local localPoint = candidate.CFrame:PointToObjectSpace(position)
            local size = candidate.Size * 0.5
            local dx = math.max(math.abs(localPoint.X) - size.X, 0)
            local dy = math.max(math.abs(localPoint.Y) - size.Y, 0)
            local dz = math.max(math.abs(localPoint.Z) - size.Z, 0)
            local score = math.sqrt(dx * dx + dy * dy + dz * dz)
                + (candidate.Position - position).Magnitude * 0.02
            if not bestScore or score < bestScore then
                best, bestScore = candidate, score
            end
        end
    end
    return best
end

local function scaleRatio(body)
    local source = SOURCE_SIZE[body.Name]
    return Vector3.new(body.Size.X / source.X,
        body.Size.Y / source.Y, body.Size.Z / source.Z)
end

local function chooseVariant(body, worldPosition)
    local localHit = body.CFrame:PointToObjectSpace(worldPosition)
    local size = body.Size
    local nx = localHit.X / math.max(size.X * 0.5, 0.01)
    local ny = localHit.Y / math.max(size.Y * 0.5, 0.01)
    local nz = localHit.Z / math.max(size.Z * 0.5, 0.01)
    local name = body.Name
    if name:find("Foot") then
        if math.abs(ny) > math.abs(nz) * 0.8 then
            if nz < -0.22 then return "top_toes", "Y" end
            if nz > 0.22 then return "top_heel", "Y" end
            return "top_center", "Y"
        end
        return "front_center", "Z"
    end
    if name:find("Hand") then
        if math.abs(ny) > math.abs(nz) then return "top_center", "Y" end
        if ny < -0.22 then return "front_fingers", "Z" end
        return "front_center", "Z"
    end
    if math.abs(nx) > math.abs(nz) * 1.1 then
        return "side_center", "X"
    end
    if name:find("Torso") then
        if math.abs(nx) > 0.25 and math.abs(nx) > math.abs(ny) then
            return nx < 0 and "front_left" or "front_right", "Z"
        end
        if ny > 0.27 then return "front_upper", "Z" end
        if ny < -0.27 then return "front_lower", "Z" end
        return "front_center", "Z"
    end
    if ny > 0.25 then return "front_upper", "Z" end
    if ny < -0.25 then return "front_lower", "Z" end
    return "front_center", "Z"
end

local function makeMesh(body, name, meshId, textureId, color, size,
    transparency, placement)
    local holder = Instance.new("Part")
    holder.Name = name
    holder.Size = Vector3.new(0.01, 0.01, 0.01) -- failed loads stay tiny
    holder.Anchored = false
    holder.Massless = true
    holder.CanCollide = false
    holder.CanTouch = false
    holder.CanQuery = false
    holder.CastShadow = false
    holder.Color = color
    holder.Transparency = transparency or 0
    holder.CFrame = placement or body.CFrame
    holder.Parent = body.Parent
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = meshId
    mesh.TextureId = textureId or ""
    mesh.Scale = size
    mesh.Parent = holder
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = body
    weld.Part1 = holder
    weld.Parent = holder
    return holder
end

local function protrudingBone(body, position, filename, amount)
    local ok, meshId = pcall(asset, filename)
    if not ok or not active or not body.Parent then return end
    local normal = position - body.Position
    if normal.Magnitude < 0.01 then normal = body.CFrame.LookVector end
    normal = normal.Unit
    local placement = CFrame.lookAt(position - normal * 0.035,
        position + normal) * CFrame.Angles(0, 0, rng:NextNumber(-3, 3))
    local holder = makeMesh(body, "Small bone fragment", meshId,
        anatomyAsset, Color3.fromRGB(235, 225, 204),
        Vector3.new(amount, amount, amount), 0, placement)
    table.insert(extras, holder)
    Debris:AddItem(holder, 20)
end

local function restore()
    for body, state in pairs(states) do
        if body.Parent then body.LocalTransparencyModifier = state.old end
        for decal, value in pairs(state.decals) do
            if decal.Parent then decal.Transparency = value end
        end
        for _, item in ipairs(state.parts) do
            if item.Parent then item:Destroy() end
        end
    end
    table.clear(states)
    for _, item in ipairs(extras) do
        if item.Parent then item:Destroy() end
    end
    table.clear(extras)
end

local function woundEffect(wound)
    if not active or stopped or not wound.Parent then return end
    local hit = wound.Position
    local body = nearestBody(hit)
    if not body then return end
    local decal = wound:FindFirstChildWhichIsA("Decal")
    if body.Name == "Head" then
        task.spawn(protrudingBone, body, hit, "v10-skull-chip.mesh", 0.85)
        return
    end
    if not EXPECTED[body.Name]
        or not tostring(body.MeshId):find(EXPECTED[body.Name], 1, true) then
        return
    end
    if states[body] then
        local chip = body.Name:find("Foot") and "v10-foot-chip.mesh"
            or body.Name:find("Hand") and "v10-hand-chip.mesh"
            or "v10-limb-chip.mesh"
        task.spawn(protrudingBone, body, hit, chip, 0.55)
        return
    end

    local variant = chooseVariant(body, hit)
    local partKey = body.Name:lower():gsub("upper", "_upper_")
        :gsub("lower", "_lower_")
    -- Use the exact snake-case source names in the generated asset files.
    local keys = {
        UpperTorso="upper_torso", LowerTorso="lower_torso",
        RightUpperArm="right_upper_arm", RightLowerArm="right_lower_arm",
        RightHand="right_hand", LeftUpperArm="left_upper_arm",
        LeftLowerArm="left_lower_arm", LeftHand="left_hand",
        RightUpperLeg="right_upper_leg", RightLowerLeg="right_lower_leg",
        RightFoot="right_foot", LeftUpperLeg="left_upper_leg",
        LeftLowerLeg="left_lower_leg", LeftFoot="left_foot",
    }
    partKey = keys[body.Name] or partKey
    local holeFile = "v10-hole-" .. partKey .. "-" .. variant .. ".mesh"
    local anatomyKey = body.Name:lower()
    local ok, holeId = pcall(asset, holeFile)
    if not ok then warn("Anatomy v10: " .. tostring(holeId)); return end
    local boneOk, boneId = pcall(asset, "v10-anatomy-" .. anatomyKey .. "-bone.mesh")
    local muscleOk, muscleId = pcall(asset, "v10-anatomy-" .. anatomyKey .. "-muscle.mesh")
    if not boneOk or not muscleOk then
        warn("Anatomy v10: body anatomy download failed")
        return
    end
    local rimOk, rimId = pcall(asset, "v10-tissue-rim.mesh")
    local heartId, lungId
    if body.Name == "UpperTorso" then
        local heartOk, result = pcall(asset, "torso-heart.mesh")
        if heartOk then heartId = result end
        local lungOk, result2 = pcall(asset, "torso-lungs.mesh")
        if lungOk then lungId = result2 end
    end
    if not active or stopped or not body.Parent or states[body] then return end

    local ratio = scaleRatio(body)
    local shirt = body.Parent:FindFirstChildOfClass("Shirt")
    local garment = shirt and shirt.ShirtTemplate or ""
    if garment == "" then garment = body.TextureID end
    local state = {old = body.LocalTransparencyModifier,
        parts = {}, decals = {}}
    local good, err = pcall(function()
        table.insert(state.parts, makeMesh(body, "Fitted damaged body",
            holeId, garment, body.Color, ratio, 0))
        local bones = makeMesh(body, "Internal bones",
            boneId, anatomyAsset, Color3.new(1, 1, 1), ratio, 0)
        table.insert(state.parts, bones)
        local light = Instance.new("PointLight")
        light.Brightness = 0.28
        light.Range = 1.6
        light.Color = Color3.fromRGB(245, 180, 170)
        light.Parent = bones
        table.insert(state.parts, makeMesh(body, "Internal muscles",
            muscleId, anatomyAsset, Color3.new(1, 1, 1), ratio, 0.22))
        if rimOk then
            local normal = hit - body.Position
            if normal.Magnitude < 0.01 then normal = body.CFrame.LookVector end
            normal = normal.Unit
            local radius = math.min(body.Size.X, body.Size.Y,
                body.Size.Z) * (body.Name:find("Torso") and 0.13 or 0.15)
            local placement = CFrame.lookAt(hit - normal * 0.025,
                hit + normal)
            table.insert(state.parts, makeMesh(body, "Tissue at opening",
                rimId, anatomyAsset, Color3.fromRGB(205, 100, 100),
                Vector3.new(radius, radius, radius * 0.7), 0, placement))
        end
        if heartId then
            table.insert(state.parts, makeMesh(body, "Heart", heartId,
                anatomyAsset, Color3.new(1, 1, 1), body.Size * 0.85, 0))
        end
        if lungId then
            table.insert(state.parts, makeMesh(body, "Lungs", lungId,
                anatomyAsset, Color3.new(1, 1, 1), body.Size * 0.85, 0))
        end
    end)
    if not good then
        for _, item in ipairs(state.parts) do
            if item.Parent then item:Destroy() end
        end
        warn("Anatomy v10 mesh: " .. tostring(err))
        return
    end
    if decal and decal.Parent then
        state.decals[decal] = decal.Transparency
        decal.Transparency = 1
    end
    body.LocalTransparencyModifier = 1
    states[body] = state

    if body.Name:find("Foot") then
        task.spawn(protrudingBone, body, hit, "v10-foot-chip.mesh", 0.55)
    elseif body.Name:find("Hand") then
        task.spawn(protrudingBone, body, hit, "v10-hand-chip.mesh", 0.45)
    end
end

local function bloodSplat(source)
    if not active or not bloodAsset or not source.Parent then return end
    local decal = source:FindFirstChildWhichIsA("Decal")
    if not decal then return end
    local surface = Instance.new("SurfaceGui")
    surface.Name = "BloodV10"
    surface.Face = decal.Face
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0.5
    surface.Parent = source
    local image = Instance.new("ImageLabel")
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = bloodAsset
    image.Rotation = rng:NextInteger(-90, 90)
    local variant = rng:NextInteger(0, 3)
    image.ImageRectOffset = Vector2.new((variant % 2) * 627,
        math.floor(variant / 2) * 627)
    image.ImageRectSize = Vector2.new(627, 627)
    image.Parent = surface
    table.insert(extras, surface)
    Debris:AddItem(surface, 20)
end

table.insert(connections, button.MouseButton1Click:Connect(function()
    if active then
        active = false
        restore()
        updateButton()
        return
    end
    updateButton("LOADING...")
    local ok, result = pcall(asset, "anatomy-materials.png")
    if not ok then warn(result); updateButton("ASSET FAILED"); return end
    anatomyAsset = result
    ok, result = pcall(asset, "blood-atlas.png")
    if not ok then warn(result); updateButton("ASSET FAILED"); return end
    bloodAsset = result
    active = true
    updateButton()
end))

table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
    if not active or stopped or not obj:IsA("BasePart") then return end
    if obj.Name == "WoundMark" then
        task.delay(0.07, function()
            if active then task.spawn(woundEffect, obj) end
        end)
    elseif obj.Name == "BloodSplat" then
        task.delay(0.07, function() bloodSplat(obj) end)
    end
end))

env.RagdollGoreV10Stop = function()
    stopped = true
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
