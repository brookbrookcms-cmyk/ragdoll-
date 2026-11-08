-- Ragdoll Physics: body-specific damage visuals, client only.
-- Delta needs writefile + getcustomasset for the atlas texture.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for version = 1, 6 do
    local stop = env["RagdollGoreV" .. version .. "Stop"]
    if stop then pcall(stop) end
end

local ATLAS_URL = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/wound-atlas.png"
local ATLAS_FILE = "ragdoll_wound_atlas.png"
local ALT_ATLAS_URL = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/wound-atlas-2.png"
local ALT_ATLAS_FILE = "ragdoll_wound_atlas_2.png"
local BLOOD_URL = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-atlas.png"
local BLOOD_FILE = "ragdoll_blood_atlas.png"
local QUAD = 627
local rng = Random.new()
local atlas
local altAtlas
local bloodAtlas
local active = false
local dead = false
local extras = {}
local changed = {}
local heads = {}
local connections = {}
local MAX_EXTRAS = 90

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollDamageV6"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(146, 66)
frame.Position = UDim2.new(0, 12, 0.55, 0)
frame.BackgroundColor3 = Color3.fromRGB(28, 26, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(140, 22)
label.Position = UDim2.fromOffset(3, 2)
label.BackgroundTransparency = 1
label.Font = Enum.Font.SourceSansBold
label.TextSize = 16
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = "Damage visuals v6"
label.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(132, 33)
button.Position = UDim2.fromOffset(7, 28)
button.BorderSizePixel = 0
button.Font = Enum.Font.SourceSansBold
button.TextSize = 16
button.TextColor3 = Color3.new(1, 1, 1)
button.Text = "OFF"
button.BackgroundColor3 = Color3.fromRGB(75, 75, 75)
button.Parent = frame

local function updateButton()
    button.Text = active and "ON" or "OFF"
    button.BackgroundColor3 = active
        and Color3.fromRGB(140, 27, 39)
        or Color3.fromRGB(75, 75, 75)
end

local function loadAsset(url, filename)
    local customAsset = getcustomasset or getsynasset
    if not customAsset or not writefile then
        return false, "Delta needs custom assets"
    end
    local ok, result = pcall(function()
        local bytes
        local requestFn = request or http_request or (syn and syn.request)
        if requestFn then
            local response = requestFn({Url = url, Method = "GET"})
            if response.StatusCode ~= 200 then error("Download failed") end
            bytes = response.Body
        else
            bytes = game:HttpGet(url)
        end
        if not bytes or #bytes < 1000 then error("Empty atlas") end
        writefile(filename, bytes)
        return customAsset(filename)
    end)
    if ok then return true, result end
    return false, tostring(result)
end

local function regionFor(wound)
    local fx = Workspace:FindFirstChild("ShooterFx")
    local best, distance
    for _, part in ipairs(Workspace:GetPartBoundsInRadius(wound.Position, 3)) do
        if part ~= wound and part.Name ~= "DamagedHeadV6"
            and (not fx or not part:IsDescendantOf(fx)) then
            local name = part.Name:lower()
            if name:find("head") or name:find("torso")
                or name:find("arm") or name:find("hand")
                or name:find("leg") or name:find("foot") then
                local d = (part.Position - wound.Position).Magnitude
                if not distance or d < distance then
                    best, distance = part, d
                end
            end
        end
    end
    if not best then return nil, nil end
    local name = best.Name:lower()
    if name:find("head") then return "head", best end
    if name:find("torso") then return "torso", best end
    if name:find("arm") or name:find("hand") then return "arm", best end
    return "leg", best
end

local function hideHead(head)
    if heads[head] or not head.Parent then return end
    local copy = head:Clone()
    if not copy then return end
    copy.Name = "DamagedHeadV6"
    for _, child in ipairs(copy:GetChildren()) do
        if not child:IsA("SpecialMesh") then
            child:Destroy()
        end
    end
    copy.Color = head.Color
    copy.Transparency = 0
    copy.LocalTransparencyModifier = 0
    copy.CanCollide = false
    copy.CanTouch = false
    copy.CanQuery = false
    copy.Massless = true
    copy.CFrame = head.CFrame
    copy.Parent = head.Parent
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = head
    weld.Part1 = copy
    weld.Parent = copy

    local record = {copy = copy, old = head.LocalTransparencyModifier, decals = {}}
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            record.decals[child] = child.Transparency
            child.Transparency = 1
        end
    end
    head.LocalTransparencyModifier = 1
    heads[head] = record
end

local function faceAndUV(body, worldPoint)
    local point = body.CFrame:PointToObjectSpace(worldPoint)
    local size = body.Size
    local nx = point.X / math.max(size.X * 0.5, 0.01)
    local ny = point.Y / math.max(size.Y * 0.5, 0.01)
    local nz = point.Z / math.max(size.Z * 0.5, 0.01)
    local face, u, v, faceWidth, faceHeight
    if math.abs(nx) >= math.abs(ny) and math.abs(nx) >= math.abs(nz) then
        if nx > 0 then
            face = Enum.NormalId.Right
            u = 0.5 - point.Z / size.Z
        else
            face = Enum.NormalId.Left
            u = 0.5 + point.Z / size.Z
        end
        v = 0.5 - point.Y / size.Y
        faceWidth, faceHeight = size.Z, size.Y
    elseif math.abs(ny) >= math.abs(nz) then
        face = ny > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
        u = 0.5 + point.X / size.X
        v = 0.5 + (ny > 0 and point.Z or -point.Z) / size.Z
        faceWidth, faceHeight = size.X, size.Z
    else
        face = nz > 0 and Enum.NormalId.Back or Enum.NormalId.Front
        u = 0.5 + (nz > 0 and -point.X or point.X) / size.X
        v = 0.5 - point.Y / size.Y
        faceWidth, faceHeight = size.X, size.Y
    end
    return face, math.clamp(u, 0.1, 0.9), math.clamp(v, 0.1, 0.9),
        faceWidth, faceHeight
end

local function putAtlas(wound, body, region)
    for i = #extras, 1, -1 do
        if not extras[i].Parent then table.remove(extras, i) end
    end
    if #extras >= MAX_EXTRAS then return false end

    -- Draw on the NPC's own body surface. No wound plate or floating part.
    local visual = region == "head" and heads[body] and heads[body].copy or body
    if not visual or not visual.Parent then return false end
    local face, u, v, faceWidth, faceHeight = faceAndUV(body, wound.Position)
    local surface = Instance.new("SurfaceGui")
    surface.Name = "IntegratedWoundV6"
    surface.Face = face
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0.6
    surface.AlwaysOnTop = false
    surface.Parent = visual

    local worldWidth = region == "head" and rng:NextNumber(0.65, 0.95)
        or region == "torso" and rng:NextNumber(0.48, 0.72)
        or region == "arm" and rng:NextNumber(0.22, 0.34)
        or rng:NextNumber(0.28, 0.40)
    local worldHeight = region == "head" and worldWidth
        or region == "torso" and worldWidth * 0.85
        or worldWidth * rng:NextNumber(1.25, 1.55)
    local width = math.clamp(worldWidth / faceWidth, 0.1, 1.2)
    local height = math.clamp(worldHeight / faceHeight, 0.1, 1.2)
    local rotation = rng:NextInteger(-35, 35)

    local fringe = Instance.new("ImageLabel")
    fringe.Name = "IrregularBloodEdge"
    fringe.AnchorPoint = Vector2.new(0.5, 0.5)
    fringe.Position = UDim2.fromScale(u, v)
    fringe.Size = UDim2.fromScale(width * 1.12, height * 1.12)
    fringe.Rotation = rotation + rng:NextInteger(-12, 12)
    fringe.BackgroundTransparency = 1
    fringe.Image = bloodAtlas
    fringe.ImageTransparency = rng:NextNumber(0.15, 0.35)
    local variant = rng:NextInteger(0, 3)
    fringe.ImageRectOffset = Vector2.new((variant % 2) * QUAD,
        math.floor(variant / 2) * QUAD)
    fringe.ImageRectSize = Vector2.new(QUAD, QUAD)
    fringe.Parent = surface

    local image = Instance.new("ImageLabel")
    image.Name = "AnatomyLayer"
    image.AnchorPoint = Vector2.new(0.5, 0.5)
    image.Position = UDim2.fromScale(u + rng:NextNumber(-0.025, 0.025),
        v + rng:NextNumber(-0.025, 0.025))
    image.Size = UDim2.fromScale(width, height)
    image.Rotation = rotation
    image.BackgroundTransparency = 1
    image.Image = rng:NextNumber() < 0.5 and atlas or altAtlas
    image.ImageColor3 = Color3.fromRGB(rng:NextInteger(205, 255),
        rng:NextInteger(205, 255), rng:NextInteger(205, 255))
    local x = (region == "torso" or region == "leg") and QUAD or 0
    local y = (region == "arm" or region == "leg") and QUAD or 0
    image.ImageRectOffset = Vector2.new(x, y)
    image.ImageRectSize = Vector2.new(QUAD, QUAD)
    image.Parent = surface

    table.insert(extras, surface)
    Debris:AddItem(surface, 25)
    return true
end

local function bloodSplat(source)
    if dead or not active or not bloodAtlas or not source.Parent then return end
    local original = source:FindFirstChildWhichIsA("Decal")
    if not original or changed[original] then return end
    for i = #extras, 1, -1 do
        if not extras[i].Parent then table.remove(extras, i) end
    end
    if #extras >= MAX_EXTRAS then return end
    changed[original] = original.Transparency
    original.Transparency = 1

    -- Reuse the game's splat part, which is already aligned to the floor.
    local surface = Instance.new("SurfaceGui")
    surface.Name = "IntegratedBloodV6"
    surface.Face = original.Face
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0.6
    surface.Parent = source
    local image = Instance.new("ImageLabel")
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = bloodAtlas
    image.Rotation = rng:NextInteger(-90, 90)
    local variant = rng:NextInteger(0, 3)
    image.ImageRectOffset = Vector2.new((variant % 2) * QUAD,
        math.floor(variant / 2) * QUAD)
    image.ImageRectSize = Vector2.new(QUAD, QUAD)
    image.Parent = surface
    table.insert(extras, surface)
end

local function woundEffect(wound)
    if dead or not active or not atlas or not wound.Parent then return end
    local decal = wound:FindFirstChildWhichIsA("Decal")
    if not decal or changed[decal] then return end
    local region, body = regionFor(wound)
    if not body then return end
    if region == "head" then hideHead(body) end
    if putAtlas(wound, body, region) then
        changed[decal] = decal.Transparency
        decal.Transparency = 1
    end
end

local function restore()
    for decal, value in pairs(changed) do
        if decal.Parent then decal.Transparency = value end
    end
    table.clear(changed)
    for head, record in pairs(heads) do
        if head.Parent then head.LocalTransparencyModifier = record.old end
        for decal, value in pairs(record.decals) do
            if decal.Parent then decal.Transparency = value end
        end
        if record.copy.Parent then record.copy:Destroy() end
    end
    table.clear(heads)
    for _, item in ipairs(extras) do
        if item.Parent then item:Destroy() end
    end
    table.clear(extras)
end

table.insert(connections, button.MouseButton1Click:Connect(function()
    if active then
        active = false
        restore()
        updateButton()
        return
    end
    if not atlas then
        button.Text = "LOADING..."
        local ok, result = loadAsset(ATLAS_URL, ATLAS_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v6: " .. result)
            return
        end
        atlas = result
        ok, result = loadAsset(ALT_ATLAS_URL, ALT_ATLAS_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v6: " .. result)
            return
        end
        altAtlas = result
        ok, result = loadAsset(BLOOD_URL, BLOOD_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v6: " .. result)
            return
        end
        bloodAtlas = result
    end
    active = true
    updateButton()
end))

table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
    if not active or dead then return end
    if obj:IsA("BasePart") and obj.Name == "WoundMark" then
        task.delay(0.07, function() woundEffect(obj) end)
    elseif obj:IsA("BasePart") and obj.Name == "BloodSplat" then
        task.delay(0.07, function() bloodSplat(obj) end)
    end
end))

env.RagdollGoreV6Stop = function()
    dead = true
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
