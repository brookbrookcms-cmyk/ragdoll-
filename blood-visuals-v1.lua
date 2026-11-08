-- Ragdoll Physics: local blood visuals v1
-- Toggle with the small button. Effects are visible only to you.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local localPlayer = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if env.RagdollGoreV1Stop then
    pcall(env.RagdollGoreV1Stop)
end

local enabled = false
local connections = {}
local originalEmitters = {}
local originalParts = {}
local extraParts = {}
local rng = Random.new()
local stopped = false

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollGoreV1"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or localPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(142, 66)
panel.Position = UDim2.new(0, 12, 0.55, 0)
panel.BackgroundColor3 = Color3.fromRGB(32, 29, 32)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(136, 23)
title.Position = UDim2.fromOffset(3, 2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.SourceSansBold
title.TextSize = 17
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Blood visuals"
title.Parent = panel

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(128, 32)
toggle.Position = UDim2.fromOffset(7, 28)
toggle.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.SourceSansBold
toggle.TextSize = 17
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Text = "OFF"
toggle.Parent = panel

local function scaleSequence(sequence, factor)
    local points = {}
    for _, point in ipairs(sequence.Keypoints) do
        table.insert(points, NumberSequenceKeypoint.new(
            point.Time, point.Value * factor, point.Envelope * factor
        ))
    end
    return NumberSequence.new(points)
end

local function opacitySequence(sequence)
    local points = {}
    for _, point in ipairs(sequence.Keypoints) do
        table.insert(points, NumberSequenceKeypoint.new(
            point.Time, math.clamp(point.Value * 0.55, 0, 1),
            point.Envelope * 0.55
        ))
    end
    return NumberSequence.new(points)
end

local function isBloodEmitter(obj)
    if not obj:IsA("ParticleEmitter") or obj.Name == "dust" then
        return false
    end
    local parent = obj.Parent
    return parent and parent.Parent and parent.Parent.Name == "BloodEmitters"
end

local function boostEmitter(obj)
    if originalEmitters[obj] or not isBloodEmitter(obj) then return end
    originalEmitters[obj] = {
        size = obj.Size,
        transparency = obj.Transparency,
        lifetime = obj.Lifetime,
        color = obj.Color,
    }
    local factor = obj.Name:find("Mist") and 1.5 or 2.2
    obj.Size = scaleSequence(obj.Size, factor)
    obj.Transparency = opacitySequence(obj.Transparency)
    obj.Lifetime = NumberRange.new(
        obj.Lifetime.Min * 1.35, obj.Lifetime.Max * 1.35
    )
    obj.Color = ColorSequence.new(Color3.fromRGB(150, 12, 25))
end

local function isBloodPart(obj)
    return obj:IsA("BasePart")
        and (obj.Name == "BloodSplat" or obj.Name == "WoundMark"
            or obj.Name == "WoundStain")
        and not obj:GetAttribute("RagdollGoreExtra")
end

local function boostPart(part)
    if not enabled or not part.Parent or originalParts[part]
        or not isBloodPart(part) then return end

    local decal = part:FindFirstChildWhichIsA("Decal")
    if not decal then return end

    originalParts[part] = {
        size = part.Size,
        decal = decal,
        color = decal.Color3,
        transparency = decal.Transparency,
    }

    local floorSplat = part.Name == "BloodSplat"
    local scale = floorSplat and 2.1 or 1.8
    local size = part.Size
    if floorSplat then
        part.Size = Vector3.new(size.X * scale, size.Y, size.Z * scale)
    else
        part.Size = Vector3.new(size.X * scale, size.Y * scale, size.Z)
    end
    decal.Color3 = Color3.fromRGB(160, 25, 30)
    decal.Transparency = math.max(0, decal.Transparency * 0.55)

    -- Add a few offset copies of the game's own decal, so each hit looks fuller.
    local copies = floorSplat and 2 or 1
    for _ = 1, copies do
        for i = #extraParts, 1, -1 do
            if not extraParts[i].Parent then table.remove(extraParts, i) end
        end
        if #extraParts >= 120 then break end
        local clone = part:Clone()
        if not clone then break end
        clone.Name = "RagdollGoreExtra"
        clone:SetAttribute("RagdollGoreExtra", true)
        local x = rng:NextNumber(-0.8, 0.8)
        local side = rng:NextNumber(-0.8, 0.8)
        if floorSplat then
            clone.CFrame = part.CFrame * CFrame.new(x, 0.012, side)
                * CFrame.Angles(0, rng:NextNumber(-3, 3), 0)
        else
            clone.CFrame = part.CFrame * CFrame.new(x * 0.3, side * 0.3, 0.012)
                * CFrame.Angles(0, 0, rng:NextNumber(-1, 1))
        end
        clone.Parent = part.Parent
        table.insert(extraParts, clone)
        Debris:AddItem(clone, 25)
    end
end

local function restore()
    for obj, old in pairs(originalEmitters) do
        if obj.Parent then
            obj.Size = old.size
            obj.Transparency = old.transparency
            obj.Lifetime = old.lifetime
            obj.Color = old.color
        end
    end
    table.clear(originalEmitters)

    for part, old in pairs(originalParts) do
        if part.Parent then part.Size = old.size end
        if old.decal.Parent then
            old.decal.Color3 = old.color
            old.decal.Transparency = old.transparency
        end
    end
    table.clear(originalParts)

    for _, part in ipairs(extraParts) do
        if part.Parent then part:Destroy() end
    end
    table.clear(extraParts)
end

local function setEnabled(value)
    enabled = value
    toggle.Text = value and "ON" or "OFF"
    toggle.BackgroundColor3 = value
        and Color3.fromRGB(145, 28, 45)
        or Color3.fromRGB(80, 80, 80)

    if value then
        local fx = Workspace:FindFirstChild("ShooterFx")
        local emitters = fx and fx:FindFirstChild("BloodEmitters")
        if emitters then
            for _, obj in ipairs(emitters:GetDescendants()) do
                if isBloodEmitter(obj) then boostEmitter(obj) end
            end
        end
    else
        restore()
    end
end

table.insert(connections, toggle.MouseButton1Click:Connect(function()
    setEnabled(not enabled)
end))

table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
    if not enabled or stopped then return end
    if isBloodEmitter(obj) then
        task.defer(function()
            if enabled and obj.Parent then boostEmitter(obj) end
        end)
    elseif isBloodPart(obj) then
        task.delay(0.08, function()
            if enabled and not stopped then boostPart(obj) end
        end)
    end
end))

env.RagdollGoreV1Stop = function()
    stopped = true
    enabled = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
