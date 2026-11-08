-- Ragdoll Physics v11: adaptive impact-scaled local anatomy visuals for the NPC2 R15 rig.
-- Mesh anatomy adaptation: Écorché / BodyParts3D / Z-Anatomy, CC BY-SA 4.0.
-- See ANATOMY_ATTRIBUTION.md in the repository for full credits.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for version = 1, 11 do
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
    Head = Vector3.new(1.1962, 1.2029, 1.1979),
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
gui.Name = "RagdollAnatomyV11"
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
title.Text = "Anatomy v11"
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
    local path = "ragdoll_v11_" .. filename
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

local function legacyWoundEffect(wound)
    if not active or stopped or not wound.Parent then return end
    local hit = wound.Position
    local body = nearestBody(hit)
    if not body then return end
    local decal = wound:FindFirstChildWhichIsA("Decal")
    if body.Name == "Head" then
        task.spawn(protrudingBone, body, hit, "v10-skull-chip.mesh", 0.85)
        if not states[body] then
            local boneOk, boneId = pcall(asset, "v10-anatomy-head-bone.mesh")
            local muscleOk, muscleId = pcall(asset, "v10-anatomy-head-muscle.mesh")
            if boneOk and muscleOk and active and body.Parent then
                local ratio = scaleRatio(body) * 0.78
                local state = {old = body.LocalTransparencyModifier,
                    parts = {}, decals = {}}
                local good = pcall(function()
                    table.insert(state.parts, makeMesh(body, "Skull anatomy",
                        boneId, anatomyAsset, Color3.new(1, 1, 1), ratio, 0))
                    table.insert(state.parts, makeMesh(body, "Head muscles",
                        muscleId, anatomyAsset, Color3.new(1, 1, 1), ratio, 0))
                end)
                if good then
                    states[body] = state
                else
                    for _, item in ipairs(state.parts) do
                        if item.Parent then item:Destroy() end
                    end
                end
            end
        end
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
    if not ok then warn("Anatomy v11: " .. tostring(holeId)); return end
    local boneOk, boneId = pcall(asset, "v10-anatomy-" .. anatomyKey .. "-bone.mesh")
    local muscleOk, muscleId = pcall(asset, "v10-anatomy-" .. anatomyKey .. "-muscle.mesh")
    if not boneOk or not muscleOk then
        warn("Anatomy v11: body anatomy download failed")
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


-- V11 adaptive impacts. The original v10 fitted anatomy meshes remain in use
-- for medium/large injuries; small wounds keep the original skin visible.
-- WoundMark is the only guaranteed signal, so clustered marks indicate a
-- multi-projectile burst. Optional attributes supply exact weapon information.
local IMPACT = {
    Window = 0.19,
    MediumMarks = 2,
    HeavyMarks = 3,
    MaximumPieces = 10,
    Lifetime = 22,
}
local pendingWounds = {}
local impactEpoch = 0

local function readNumber(wound, names)
    for _, name in ipairs(names) do
        local v = wound:GetAttribute(name)
        if type(v) == "number" then return v end
        local child = wound:FindFirstChild(name)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            return child.Value
        end
    end
    return nil
end

local function readString(wound, names)
    for _, name in ipairs(names) do
        local v = wound:GetAttribute(name)
        if type(v) == "string" and v ~= "" then return v end
        local child = wound:FindFirstChild(name)
        if child and child:IsA("StringValue") then return child.Value end
    end
    return ""
end

local function severityForWound(wound)
    local exact = readNumber(wound, {"ImpactTier", "WoundTier"})
    if exact then return math.clamp(math.floor(exact), 1, 3) end

    local weapon = readString(wound, {
        "WeaponType", "Weapon", "DamageType", "ProjectileType", "ImpactType",
    }):lower()
    if weapon:find("shotgun", 1, true)
        or weapon:find("buckshot", 1, true)
        or weapon:find("explos", 1, true)
        or weapon:find("blast", 1, true)
        or weapon:find("rocket", 1, true) then
        return 3
    end

    local pelletCount = readNumber(wound, {"PelletCount", "Pellets", "Projectiles"})
    if pelletCount then
        if pelletCount >= 3 then return 3 end
        if pelletCount >= 2 then return 2 end
    end
    local radius = readNumber(wound, {"ImpactRadius", "WoundRadius", "BlastRadius"})
    if radius then
        if radius >= 0.42 then return 3 end
        if radius >= 0.19 then return 2 end
    end
    local damage = readNumber(wound, {"HitDamage", "Damage"})
    if damage then
        if damage >= 65 then return 3 end
        if damage >= 32 then return 2 end
    end

    -- Flat WoundMark dimensions can be a fallback for wound size.
    -- Do not use a stock 1x1x1 Part as a shotgun indicator.
    local size = wound.Size
    local longest = math.max(size.X, size.Y, size.Z)
    local shortest = math.min(size.X, size.Y, size.Z)
    if shortest <= longest * 0.5 then
        if longest >= 0.72 then return 3 end
        if longest >= 0.38 then return 2 end
    end
    return 1
end

local function normalAt(body, hit)
    local offset = hit - body.Position
    if offset.Magnitude < 0.02 then
        return body.CFrame.LookVector
    end
    return offset.Unit
end

local function temporaryPart(body, name, size, cf, color, transparency, shape)
    if not body.Parent then return nil end
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = shape or Enum.PartType.Block
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = Enum.Material.SmoothPlastic
    p.Transparency = transparency or 0
    p.Anchored = false
    p.Massless = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Parent = body.Parent
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = body
    weld.Part1 = p
    weld.Parent = p
    table.insert(extras, p)
    Debris:AddItem(p, IMPACT.Lifetime)
    return p
end

local function chipFileFor(body)
    if body.Name == "Head" then return "v10-skull-chip.mesh" end
    if body.Name:find("Foot") then return "v10-foot-chip.mesh" end
    if body.Name:find("Hand") then return "v10-hand-chip.mesh" end
    return "v10-limb-chip.mesh"
end

-- Restrained surface-based wounds. Do not scale imported bone/rim meshes:
-- their native mesh units are much larger than Roblox body-part units.
local function impactSurface(body, hit)
    local n = normalAt(body, hit)
    local reach = math.max(body.Size.Magnitude, 1.5)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {body}
    params.IgnoreWater = true
    local result = Workspace:Raycast(hit + n * reach, -n * reach * 2, params)
    if result then
        return result.Position, result.Normal
    end

    -- Wound marks are normally already placed on the skin.
    -- A mark inside the mesh needs to be projected onto its bounding surface.
    local p = body.CFrame:PointToObjectSpace(hit)
    local half = body.Size * 0.5
    local nx = math.abs(p.X) / math.max(half.X, 0.01)
    local ny = math.abs(p.Y) / math.max(half.Y, 0.01)
    local nz = math.abs(p.Z) / math.max(half.Z, 0.01)
    if math.max(nx, ny, nz) >= 0.66 then return hit, n end

    local x, y, z = p.X, p.Y, p.Z
    local sign = function(v) return v >= 0 and 1 or -1 end
    if nx >= ny and nx >= nz then
        x = half.X * sign(x)
        n = body.CFrame.RightVector * sign(x)
    elseif ny >= nz then
        y = half.Y * sign(y)
        n = body.CFrame.UpVector * sign(y)
    else
        z = half.Z * sign(z)
        n = -body.CFrame.LookVector * sign(z)
    end
    return body.CFrame:PointToWorldSpace(Vector3.new(x, y, z)), n
end

local function woundDiameter(body, normal, tier)
    -- Use the face width, not the longest body axis: leg wounds must not
    -- grow into leg-length tubes and arm wounds must not exceed the arm.
    local localN = body.CFrame:VectorToObjectSpace(normal)
    local ax, ay, az = math.abs(localN.X), math.abs(localN.Y), math.abs(localN.Z)
    local faceWidth
    if ax >= ay and ax >= az then
        faceWidth = math.min(body.Size.Y, body.Size.Z)
    elseif ay >= az then
        faceWidth = math.min(body.Size.X, body.Size.Z)
    else
        faceWidth = math.min(body.Size.X, body.Size.Y)
    end
    local fraction = ({0.19, 0.44, 0.80})[tier]
    return math.clamp(faceWidth * fraction, 0.085, 1.05)
end

local function drawImpact(body, hit, tier, markCount)
    if not active or stopped or not body.Parent then return end

    local point, normal = impactSurface(body, hit)
    local diameter = woundDiameter(body, normal, tier)
    local base = CFrame.lookAt(point, point + normal)
        * CFrame.Angles(0, 0, rng:NextNumber(-math.pi, math.pi))

    -- Thin ellipsoids flush with the skin. The red irregular edge and dark
    -- center suggest depth without protruding anatomy or giant mesh spikes.
    local function oval(name, width, height, depth, color, x, y, lift, angle)
        if not active or stopped or not body.Parent then return end
        local cf = base * CFrame.new(x or 0, y or 0, -(lift or 0.012))
            * CFrame.Angles(0, 0, angle or 0)
        return temporaryPart(body, name,
            Vector3.new(width, height, depth), cf,
            color, 0, Enum.PartType.Ball)
    end

    oval("Wound rim", diameter, diameter * rng:NextNumber(0.76, 0.92),
        0.025, Color3.fromRGB(115, 33, 38), 0, 0, 0.010)
    oval("Wound recess", diameter * 0.78, diameter * 0.68,
        0.027, Color3.fromRGB(48, 12, 18), 0, 0, 0.017)
    oval("Raw tissue", diameter * 0.29, diameter * 0.22,
        0.025, Color3.fromRGB(133, 48, 50),
        -diameter * 0.14, -diameter * 0.18, 0.022, 0.4)

    if tier >= 2 then
        -- A couple of uneven flesh edges; no looping/tubular meshes.
        local edgeCount = tier == 3 and 3 or 2
        for i = 1, edgeCount do
            local a = 2 * math.pi * i / edgeCount + rng:NextNumber(-0.35, 0.35)
            local r = diameter * 0.29
            oval("Irregular wound edge",
                diameter * rng:NextNumber(0.15, 0.23),
                diameter * rng:NextNumber(0.09, 0.15),
                0.022, Color3.fromRGB(147, 51, 55),
                math.cos(a) * r, math.sin(a) * r, 0.025, a)
        end
    end

    -- For deeper injuries, small pale fragments remain *inside* the wound
    -- boundary. No native v10 chip mesh and no full-body anatomy replacement.
    if tier >= 2 then
        local limb = body.Name == "Head"
            or body.Name:find("Arm") or body.Name:find("Leg")
            or body.Name:find("Hand") or body.Name:find("Foot")
        if limb or body.Name == "UpperTorso" then
            local boneWidth = diameter * (tier == 3 and 0.43 or 0.23)
            oval("Exposed bone", boneWidth,
                diameter * (tier == 3 and 0.18 or 0.12),
                0.024, Color3.fromRGB(206, 190, 163),
                diameter * 0.07, diameter * 0.04, 0.026, -0.35)
        end
    end

    local pieces = tier == 3 and 3 or (tier == 2 and 1 or 0)
    pieces = math.min(4, pieces + math.max(0, markCount - 3))
    for i = 1, pieces do
        local a = rng:NextNumber(0, math.pi * 2)
        local r = diameter * rng:NextNumber(0.10, 0.29)
        local sz = diameter * rng:NextNumber(0.06, 0.11)
        oval("Embedded fragment", sz, sz * rng:NextNumber(0.38, 0.75),
            0.024, Color3.fromRGB(186, 167, 146),
            math.cos(a) * r, math.sin(a) * r,
            0.030, a)
    end

    if #extras > 480 then
        for i = #extras, 1, -1 do
            if not extras[i].Parent then table.remove(extras, i) end
        end
    end
end

local function processWoundBatch(batch)
    if stopped or not active or batch.epoch ~= impactEpoch then return end
    local body = batch.body
    if not body.Parent then return end
    local tier = 1
    local validCount = 0
    for _, wound in ipairs(batch.wounds) do
        if wound.Parent then
            validCount = validCount + 1
            tier = math.max(tier, severityForWound(wound))
        end
    end
    if validCount == 0 then return end
    if validCount >= IMPACT.HeavyMarks then
        tier = 3
    elseif validCount >= IMPACT.MediumMarks then
        tier = math.max(tier, 2)
    end

    -- Never call the legacy full-anatomy function: it hides the complete
    -- body mesh and exposes huge, non-localized anatomy on one hit.
    local hit = body.CFrame:PointToWorldSpace(batch.localCenter)
    drawImpact(body, hit, tier, validCount)
end

local function queueWound(wound)
    if stopped or not active or not wound.Parent then return end
    local body = nearestBody(wound.Position)
    if not body then return end
    local batches = pendingWounds[body]
    if not batches then
        batches = {}
        pendingWounds[body] = batches
    end
    local localHit = body.CFrame:PointToObjectSpace(wound.Position)
    local radius = math.clamp(body.Size.Magnitude * 0.42, 0.35, 0.95)
    for _, batch in ipairs(batches) do
        if (batch.localCenter - localHit).Magnitude <= radius then
            table.insert(batch.wounds, wound)
            local n = #batch.wounds
            batch.localCenter = batch.localCenter:Lerp(localHit, 1 / n)
            return
        end
    end
    local batch = {
        body = body, localCenter = localHit, wounds = {wound},
        epoch = impactEpoch,
    }
    table.insert(batches, batch)
    task.delay(IMPACT.Window, function()
        local index = table.find(batches, batch)
        if index then table.remove(batches, index) end
        if #batches == 0 and pendingWounds[body] == batches then
            pendingWounds[body] = nil
        end
        processWoundBatch(batch)
    end)
end

local function bloodSplat(source)
    if not active or not bloodAsset or not source.Parent then return end
    local decal = source:FindFirstChildWhichIsA("Decal")
    if not decal then return end
    local surface = Instance.new("SurfaceGui")
    surface.Name = "BloodV11"
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
        impactEpoch = impactEpoch + 1
        table.clear(pendingWounds)
        restore()
        updateButton()
        return
    end
    updateButton("LOADING...")
    local ok, result = pcall(asset, "blood-atlas.png")
    if not ok then warn(result); updateButton("ASSET FAILED"); return end
    bloodAsset = result
    active = true
    impactEpoch = impactEpoch + 1
    updateButton()
end))

table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
    if not active or stopped or not obj:IsA("BasePart") then return end
    if obj.Name == "WoundMark" then
        task.delay(0.07, function()
            if active then queueWound(obj) end
        end)
    elseif obj.Name == "BloodSplat" then
        task.delay(0.07, function() bloodSplat(obj) end)
    end
end))

env.RagdollGoreV11Stop = function()
    stopped = true
    active = false
    impactEpoch = impactEpoch + 1
    table.clear(pendingWounds)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
