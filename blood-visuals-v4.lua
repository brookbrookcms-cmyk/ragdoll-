-- Ragdoll Physics blood visuals v4 (client only)
-- Adds dark pools, impact spray, and small muscle/bone details at wounds.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if env.RagdollGoreV1Stop then pcall(env.RagdollGoreV1Stop) end
if env.RagdollGoreV2Stop then pcall(env.RagdollGoreV2Stop) end
if env.RagdollGoreV3Stop then pcall(env.RagdollGoreV3Stop) end
if env.RagdollGoreV4Stop then pcall(env.RagdollGoreV4Stop) end

local SPLAT_TEXTURES = {
    "rbxassetid://79548089109855",
    "rbxassetid://127895607834399",
    "rbxassetid://93546937207481",
}
local SPRAY_TEXTURE = "rbxassetid://93548634539367"
local rng = Random.new()
local enabled = false
local stopped = false
local connections = {}
local originalDecals = {}
local originalEmitters = {}
local extras = {}

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollBloodV4"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(140, 66)
frame.Position = UDim2.new(0, 12, 0.55, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 26, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(136, 23)
title.Position = UDim2.fromOffset(2, 2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Blood detail v4"
title.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(126, 32)
button.Position = UDim2.fromOffset(7, 28)
button.BorderSizePixel = 0
button.Font = Enum.Font.SourceSansBold
button.TextSize = 17
button.TextColor3 = Color3.new(1, 1, 1)
button.Parent = frame

local function updateButton()
    button.Text = enabled and "ON" or "OFF"
    button.BackgroundColor3 = enabled
        and Color3.fromRGB(135, 24, 35)
        or Color3.fromRGB(78, 78, 78)
end
updateButton()

local function rememberDecal(decal)
    if not originalDecals[decal] then
        originalDecals[decal] = {
            color = decal.Color3,
            transparency = decal.Transparency,
        }
    end
end

local function makeMark(source, sourceDecal, texture, color, transparency,
    width, height, offsetX, offsetY, angle)
    for i = #extras, 1, -1 do
        if not extras[i].Parent then table.remove(extras, i) end
    end
    if #extras >= 160 or not source.Parent then return end
    local mark = Instance.new("Part")
    mark.Name = "BloodDetailV4"
    mark:SetAttribute("BloodDetailV4", true)
    mark.Anchored = true
    mark.CanCollide = false
    mark.CanTouch = false
    mark.CanQuery = false
    mark.CastShadow = false
    mark.Transparency = 1
    mark.Size = Vector3.new(width, 0.01, height)
    mark.CFrame = source.CFrame * CFrame.new(offsetX, 0.013, offsetY)
        * CFrame.Angles(0, angle, 0)

    local decal = Instance.new("Decal")
    decal.Name = "BloodTexture"
    decal.Face = sourceDecal.Face
    decal.Texture = texture
    decal.Color3 = color
    decal.Transparency = transparency
    decal.Parent = mark

    mark.Parent = source.Parent
    table.insert(extras, mark)
    Debris:AddItem(mark, 25)
end

local function impactSpray(part)
    local attachment = Instance.new("Attachment")
    attachment.Name = "BloodDetailV4"
    attachment.Parent = part

    local spray = Instance.new("ParticleEmitter")
    spray.Name = "BloodDetailV4Spray"
    spray.Texture = SPRAY_TEXTURE
    spray.Rate = 0
    spray.Speed = NumberRange.new(5, 12)
    spray.Lifetime = NumberRange.new(0.25, 0.55)
    spray.Drag = 2
    spray.Acceleration = Vector3.new(0, -17, 0)
    spray.SpreadAngle = Vector2.new(55, 55)
    spray.EmissionDirection = Enum.NormalId.Front
    spray.Color = ColorSequence.new(
        Color3.fromRGB(145, 14, 25),
        Color3.fromRGB(75, 4, 10)
    )
    spray.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.11),
        NumberSequenceKeypoint.new(0.35, 0.08),
        NumberSequenceKeypoint.new(1, 0.01),
    })
    spray.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.6, 0.25),
        NumberSequenceKeypoint.new(1, 1),
    })
    spray.Parent = attachment
    spray:Emit(rng:NextInteger(28, 42))
    table.insert(extras, attachment)
    Debris:AddItem(attachment, 2)
end

local function tissuePiece(source, shape, size, color, x, y, z, angle)
    for i = #extras, 1, -1 do
        if not extras[i].Parent then table.remove(extras, i) end
    end
    if #extras >= 190 or not source.Parent then return end
    local piece = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
    piece.Name = "BloodDetailV4Tissue"
    if shape ~= "Wedge" then piece.Shape = shape end
    piece.Size = size
    piece.Color = color
    piece.Material = Enum.Material.SmoothPlastic
    piece.Reflectance = 0.03
    piece.Massless = true
    piece.CanCollide = false
    piece.CanTouch = false
    piece.CanQuery = false
    piece.CastShadow = false
    piece.CFrame = source.CFrame * CFrame.new(x, y, z)
        * CFrame.Angles(0, 0, angle)
    piece.Parent = source

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = source
    weld.Part1 = piece
    weld.Parent = piece

    table.insert(extras, piece)
    Debris:AddItem(piece, 20)
end

local function bodyRegion(wound)
    local closest, bestDistance
    for _, candidate in ipairs(Workspace:GetPartBoundsInRadius(wound.Position, 2.5)) do
        if candidate ~= wound and not candidate:IsDescendantOf(
            Workspace:FindFirstChild("ShooterFx") or wound
        ) then
            local name = candidate.Name:lower()
            local bodyName = name:find("head") or name:find("torso")
                or name:find("arm") or name:find("hand")
                or name:find("leg") or name:find("foot")
            if bodyName then
                local distance = (candidate.Position - wound.Position).Magnitude
                if not bestDistance or distance < bestDistance then
                    closest, bestDistance = candidate, distance
                end
            end
        end
    end
    if not closest then return "other", nil end
    local name = closest.Name:lower()
    if name:find("head") then return "head", closest end
    if name:find("torso") then return "torso", closest end
    if name:find("arm") or name:find("hand") then return "arm", closest end
    return "leg", closest
end

local function woundDetail(part)
    local region, body = bodyRegion(part)
    local axis = rng:NextNumber(-3, 3)
    if body then
        local up = part.CFrame:VectorToObjectSpace(body.CFrame.UpVector)
        if math.abs(up.X) + math.abs(up.Y) > 0.2 then
            axis = math.atan2(up.Y, up.X)
        end
    end
    axis = axis + rng:NextNumber(-0.35, 0.35)

    -- Dark inset gives the pieces depth without resizing the game's decal.
    local width = region == "head" and rng:NextNumber(0.32, 0.46)
        or region == "torso" and 0.27 or 0.19
    tissuePiece(part, Enum.PartType.Ball,
        Vector3.new(width, width * rng:NextNumber(0.65, 0.95), 0.018),
        Color3.fromRGB(48, 5, 10), 0, 0, -0.021, axis)

    if region == "head" then
        -- Irregular skull fragments with little exposed muscle.
        for i = 1, rng:NextInteger(2, 3) do
            tissuePiece(part, "Wedge",
                Vector3.new(rng:NextNumber(0.09, 0.18),
                    rng:NextNumber(0.025, 0.05), 0.025),
                Color3.fromRGB(rng:NextInteger(175, 211),
                    rng:NextInteger(168, 198), rng:NextInteger(145, 178)),
                rng:NextNumber(-0.15, 0.15),
                rng:NextNumber(-0.13, 0.13), -0.04,
                axis + (i - 2) * rng:NextNumber(0.3, 0.8))
        end
        for _ = 1, rng:NextInteger(2, 4) do
            tissuePiece(part, Enum.PartType.Cylinder,
                Vector3.new(rng:NextNumber(0.11, 0.22), 0.025, 0.025),
                Color3.fromRGB(rng:NextInteger(78, 119), 8, 19),
                rng:NextNumber(-0.12, 0.12),
                rng:NextNumber(-0.11, 0.11), -0.043,
                rng:NextNumber(-3, 3))
        end
    elseif region == "torso" then
        -- Fan-shaped fibers and short pale rib edges.
        for i = 1, rng:NextInteger(5, 7) do
            tissuePiece(part, Enum.PartType.Cylinder,
                Vector3.new(rng:NextNumber(0.12, 0.24),
                    rng:NextNumber(0.018, 0.035), 0.025),
                Color3.fromRGB(rng:NextInteger(78, 125), 9, 22),
                rng:NextNumber(-0.09, 0.09),
                rng:NextNumber(-0.09, 0.09), -0.039,
                axis + (i - 4) * 0.25)
        end
        for i = 1, rng:NextInteger(1, 2) do
            tissuePiece(part, Enum.PartType.Cylinder,
                Vector3.new(rng:NextNumber(0.08, 0.15), 0.03, 0.03),
                Color3.fromRGB(191, 180, 156),
                rng:NextNumber(-0.05, 0.05),
                rng:NextNumber(-0.07, 0.07), -0.048,
                axis + 1.1 + i * 0.25)
        end
    else
        -- Limb fibers run roughly along the limb; the bone is narrower.
        local count = region == "other" and 3 or rng:NextInteger(4, 6)
        for _ = 1, count do
            tissuePiece(part, Enum.PartType.Cylinder,
                Vector3.new(rng:NextNumber(0.10, 0.21),
                    rng:NextNumber(0.018, 0.03), 0.025),
                Color3.fromRGB(rng:NextInteger(77, 117), 8, 18),
                rng:NextNumber(-0.065, 0.065),
                rng:NextNumber(-0.065, 0.065), -0.037,
                axis + rng:NextNumber(-0.3, 0.3))
        end
        if region ~= "other" and rng:NextNumber() < 0.7 then
            local length = region == "leg" and 0.20 or 0.14
            tissuePiece(part, Enum.PartType.Cylinder,
                Vector3.new(length, 0.038, 0.038),
                Color3.fromRGB(199, 190, 164),
                rng:NextNumber(-0.025, 0.025), 0, -0.049, axis)
            tissuePiece(part, "Wedge",
                Vector3.new(0.05, 0.039, 0.038),
                Color3.fromRGB(174, 164, 139),
                length * 0.4, 0, -0.049, axis)
        end
    end
end

local function detailPart(part)
    if stopped or not enabled or not part.Parent then return end
    if part:GetAttribute("BloodDetailV4") then return end
    local name = part.Name
    if name ~= "BloodSplat" and name ~= "WoundMark"
        and name ~= "WoundStain" then return end

    local decal = part:FindFirstChildWhichIsA("Decal")
    if not decal or originalDecals[decal] then return end
    rememberDecal(decal)

    if name == "BloodSplat" then
        -- Keep the game's original size. Use its approved textures for finer layers.
        decal.Color3 = Color3.fromRGB(164, 37, 43)
        decal.Transparency = math.min(decal.Transparency, 0.08)
        local sx, sz = part.Size.X, part.Size.Z
        makeMark(part, decal, SPLAT_TEXTURES[rng:NextInteger(1, 3)],
            Color3.fromRGB(76, 8, 14), 0.25,
            sx * 0.55, sz * 0.55, 0, 0, rng:NextNumber(-3, 3))
        for _ = 1, 2 do
            makeMark(part, decal, SPLAT_TEXTURES[rng:NextInteger(1, 3)],
                Color3.fromRGB(112, 17, 25), rng:NextNumber(0.2, 0.4),
                sx * rng:NextNumber(0.22, 0.42),
                sz * rng:NextNumber(0.22, 0.42),
                rng:NextNumber(-0.28, 0.28),
                rng:NextNumber(-0.28, 0.28), rng:NextNumber(-3, 3))
        end
    elseif name == "WoundMark" then
        decal.Color3 = Color3.fromRGB(115, 13, 22)
        decal.Transparency = 0
        woundDetail(part)
        impactSpray(part)
    else
        decal.Color3 = Color3.fromRGB(105, 12, 20)
        decal.Transparency = math.min(decal.Transparency, 0.1)
    end
end

local function isBloodEmitter(obj)
    return obj:IsA("ParticleEmitter") and obj.Name ~= "dust"
        and obj.Parent and obj.Parent.Parent
        and obj.Parent.Parent.Name == "BloodEmitters"
end

local function detailEmitter(obj)
    if not isBloodEmitter(obj) or originalEmitters[obj] then return end
    originalEmitters[obj] = {
        color = obj.Color,
        transparency = obj.Transparency,
    }
    obj.Color = ColorSequence.new(Color3.fromRGB(148, 17, 28))
    local keys = {}
    for _, point in ipairs(obj.Transparency.Keypoints) do
        table.insert(keys, NumberSequenceKeypoint.new(
            point.Time, math.clamp(point.Value * 0.72, 0, 1),
            point.Envelope * 0.72
        ))
    end
    obj.Transparency = NumberSequence.new(keys)
end

local function clearExtras()
    for _, obj in ipairs(extras) do
        if obj.Parent then obj:Destroy() end
    end
    table.clear(extras)
end

local function restore()
    for decal, old in pairs(originalDecals) do
        if decal.Parent then
            decal.Color3 = old.color
            decal.Transparency = old.transparency
        end
    end
    table.clear(originalDecals)
    for emitter, old in pairs(originalEmitters) do
        if emitter.Parent then
            emitter.Color = old.color
            emitter.Transparency = old.transparency
        end
    end
    table.clear(originalEmitters)
    clearExtras()
end

local function toggle()
    enabled = not enabled
    updateButton()
    if enabled then
        local fx = Workspace:FindFirstChild("ShooterFx")
        local blood = fx and fx:FindFirstChild("BloodEmitters")
        if blood then
            for _, obj in ipairs(blood:GetDescendants()) do
                detailEmitter(obj)
            end
        end
    else
        restore()
    end
end

table.insert(connections, button.MouseButton1Click:Connect(toggle))
table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
    if not enabled or stopped then return end
    if isBloodEmitter(obj) then
        task.defer(function()
            if enabled and not stopped and obj.Parent then detailEmitter(obj) end
        end)
    elseif obj:IsA("BasePart") and (obj.Name == "BloodSplat"
        or obj.Name == "WoundMark" or obj.Name == "WoundStain") then
        task.delay(0.06, function() detailPart(obj) end)
    end
end))

env.RagdollGoreV4Stop = function()
    stopped = true
    enabled = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
