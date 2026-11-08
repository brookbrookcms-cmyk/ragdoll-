-- Ragdoll Physics: body-specific damage visuals, client only.
-- Delta needs writefile + getcustomasset for the atlas texture.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for version = 1, 5 do
    local stop = env["RagdollGoreV" .. version .. "Stop"]
    if stop then pcall(stop) end
end

local ATLAS_URL = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/wound-atlas.png"
local ATLAS_FILE = "ragdoll_wound_atlas.png"
local BLOOD_URL = "https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-atlas.png"
local BLOOD_FILE = "ragdoll_blood_atlas.png"
local QUAD = 627
local rng = Random.new()
local atlas
local bloodAtlas
local active = false
local dead = false
local extras = {}
local changed = {}
local heads = {}
local connections = {}
local MAX_EXTRAS = 90

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollDamageV5"
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
label.Text = "Damage visuals v5"
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
        if part ~= wound and part.Name ~= "DamagedHeadV5"
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
    copy.Name = "DamagedHeadV5"
    for _, child in ipairs(copy:GetChildren()) do
        if child:IsA("SpecialMesh") then
            child.TextureId = ""
        else
            child:Destroy()
        end
    end
    if copy:IsA("MeshPart") then copy.TextureID = "" end
    copy.Color = Color3.fromRGB(82, 12, 19)
    copy.Material = Enum.Material.SmoothPlastic
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

local function putAtlas(wound, body, region, originalDecal)
    for i = #extras, 1, -1 do
        if not extras[i].Parent then table.remove(extras, i) end
    end
    if #extras >= MAX_EXTRAS then return end

    local carrier = Instance.new("Part")
    carrier.Name = "DamageTextureV5"
    carrier.Anchored = false
    carrier.Massless = true
    carrier.Transparency = 1
    carrier.CanCollide = false
    carrier.CanTouch = false
    carrier.CanQuery = false
    carrier.CastShadow = false
    local width = region == "head" and rng:NextNumber(0.75, 1.1)
        or region == "torso" and rng:NextNumber(0.65, 0.9)
        or region == "arm" and rng:NextNumber(0.28, 0.42)
        or rng:NextNumber(0.35, 0.52)
    local height = region == "head" and width
        or region == "torso" and width * 0.9
        or width * rng:NextNumber(1.25, 1.65)
    carrier.Size = Vector3.new(width, height, 0.01)
    carrier.CFrame = wound.CFrame * CFrame.new(0, 0, -0.045)
        * CFrame.Angles(0, 0, rng:NextNumber(-0.4, 0.4))
    carrier.Parent = body
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = body
    weld.Part1 = carrier
    weld.Parent = carrier

    local surface = Instance.new("SurfaceGui")
    surface.Name = "DamageAtlasV5"
    surface.Face = originalDecal.Face
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0.25
    surface.Parent = carrier

    local image = Instance.new("ImageLabel")
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = atlas
    local x = (region == "torso" or region == "leg") and QUAD or 0
    local y = (region == "arm" or region == "leg") and QUAD or 0
    image.ImageRectOffset = Vector2.new(x, y)
    image.ImageRectSize = Vector2.new(QUAD, QUAD)
    image.Parent = surface

    table.insert(extras, carrier)
    Debris:AddItem(carrier, 25)
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

    local carrier = Instance.new("Part")
    carrier.Name = "BloodAtlasV5"
    carrier.Anchored = true
    carrier.Transparency = 1
    carrier.CanCollide = false
    carrier.CanTouch = false
    carrier.CanQuery = false
    carrier.CastShadow = false
    local scale = rng:NextNumber(1.1, 2.0)
    carrier.Size = Vector3.new(source.Size.X * scale, 0.01,
        source.Size.Z * scale)
    carrier.CFrame = source.CFrame * CFrame.new(0, 0.014, 0)
        * CFrame.Angles(0, rng:NextNumber(-3, 3), 0)
    carrier.Parent = source.Parent

    local surface = Instance.new("SurfaceGui")
    surface.Face = original.Face
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0.3
    surface.Parent = carrier

    local image = Instance.new("ImageLabel")
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = bloodAtlas
    local variant = rng:NextInteger(0, 3)
    image.ImageRectOffset = Vector2.new((variant % 2) * QUAD,
        math.floor(variant / 2) * QUAD)
    image.ImageRectSize = Vector2.new(QUAD, QUAD)
    image.Parent = surface

    table.insert(extras, carrier)
    Debris:AddItem(carrier, 25)
end

local function woundEffect(wound)
    if dead or not active or not atlas or not wound.Parent then return end
    local decal = wound:FindFirstChildWhichIsA("Decal")
    if not decal or changed[decal] then return end
    local region, body = regionFor(wound)
    if not body then return end
    changed[decal] = decal.Transparency
    decal.Transparency = 1
    if region == "head" then hideHead(body) end
    putAtlas(wound, body, region, decal)
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
            warn("Damage visuals v5: " .. result)
            return
        end
        atlas = result
        ok, result = loadAsset(BLOOD_URL, BLOOD_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v5: " .. result)
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

env.RagdollGoreV5Stop = function()
    dead = true
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
