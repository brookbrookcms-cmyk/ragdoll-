-- Ragdoll Physics: body-specific damage visuals, client only.
-- Delta needs writefile + getcustomasset for the atlas texture.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
for version = 1, 7 do
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
local torsos = {}
local connections = {}
local MAX_EXTRAS = 90

local gui = Instance.new("ScreenGui")
gui.Name = "RagdollDamageV7"
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
label.Text = "Damage visuals v7"
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
        if part ~= wound and part.Name ~= "DamagedHeadV7"
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
    copy.Name = "DamagedHeadV7"
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
    surface.Name = "IntegratedWoundV7"
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
    surface.Name = "IntegratedBloodV7"
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

local function replaceTorso(body, wound)
    if torsos[body] or not body.Parent then return end
    local size = body.Size
    local w, h, d = size.X, size.Y, size.Z
    if w < 0.3 or h < 0.3 or d < 0.2 then return end

    local record = {
        old = body.LocalTransparencyModifier,
        decals = {},
        pieces = {},
    }
    torsos[body] = record
    for _, child in ipairs(body:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            record.decals[child] = child.Transparency
            child.Transparency = 1
        end
    end
    body.LocalTransparencyModifier = 1

    local skin = body.Color
    local dark = Color3.fromRGB(66, 8, 15)
    local muscle = Color3.fromRGB(113, 25, 34)
    local bone = Color3.fromRGB(190, 180, 154)

    local function piece(shape, name, partSize, localFrame, color, material)
        local part = Instance.new("Part")
        part.Name = name
        part.Shape = shape
        part.Size = partSize
        part.Color = color
        part.Material = material or Enum.Material.SmoothPlastic
        part.Reflectance = (name == "Heart" or name == "Lung") and 0.07 or 0
        part.Massless = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.CFrame = body.CFrame * localFrame
        part.Parent = body.Parent
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = part
        weld.Parent = part
        table.insert(record.pieces, part)
        return part
    end

    local function box(name, x, y, z, sx, sy, sz, color)
        if sx <= 0 or sy <= 0 or sz <= 0 then return end
        piece(Enum.PartType.Block, name, Vector3.new(sx, sy, sz),
            CFrame.new(x, y, z), color)
    end

    local function rod(name, a, b, thickness, color)
        local vector = b - a
        local mid = (a + b) * 0.5
        local xAxis = vector.Unit
        local helper = math.abs(xAxis:Dot(Vector3.yAxis)) > 0.95
            and Vector3.xAxis or Vector3.yAxis
        local zAxis = xAxis:Cross(helper).Unit
        local yAxis = zAxis:Cross(xAxis).Unit
        piece(Enum.PartType.Cylinder, name,
            Vector3.new(vector.Magnitude, thickness, thickness),
            CFrame.fromMatrix(mid, xAxis, yAxis, zAxis),
            color)
    end

    local localHit = body.CFrame:PointToObjectSpace(wound.Position)
    local holeW, holeH = w * 0.58, h * 0.62
    local cx = math.clamp(localHit.X, -w * 0.12, w * 0.12)
    local cy = math.clamp(localHit.Y, -h * 0.12, h * 0.12)
    local left = (w - holeW) * 0.5 + cx
    local right = w - holeW - left
    local top = (h - holeH) * 0.5 - cy
    local bottom = h - holeH - top
    local thick = math.max(0.035, d * 0.06)

    -- Four skin panels around each opening leave the center genuinely open.
    for _, side in ipairs({-1, 1}) do
        local z = side * (d * 0.5 - thick * 0.5)
        box("Left chest shell", -w * 0.5 + left * 0.5, 0, z,
            left, h, thick, skin)
        box("Right chest shell", w * 0.5 - right * 0.5, 0, z,
            right, h, thick, skin)
        box("Upper chest shell", cx, h * 0.5 - top * 0.5, z,
            holeW, top, thick, skin)
        box("Lower chest shell", cx, -h * 0.5 + bottom * 0.5, z,
            holeW, bottom, thick, skin)

        local rimZ = z + side * thick * 0.6
        local rim = math.max(0.035, w * 0.035)
        box("Torn tissue edge", cx - holeW * 0.5, cy, rimZ,
            rim, holeH, rim, muscle)
        box("Torn tissue edge", cx + holeW * 0.5, cy, rimZ,
            rim, holeH, rim, muscle)
        box("Torn tissue edge", cx, cy + holeH * 0.5, rimZ,
            holeW, rim, rim, muscle)
        box("Torn tissue edge", cx, cy - holeH * 0.5, rimZ,
            holeW, rim, rim, muscle)
    end
    box("Chest side", -w * 0.5 + thick * 0.5, 0, 0,
        thick, h, d, skin)
    box("Chest side", w * 0.5 - thick * 0.5, 0, 0,
        thick, h, d, skin)
    box("Chest top", 0, h * 0.5 - thick * 0.5, 0,
        w, thick, d, skin)
    box("Chest bottom", 0, -h * 0.5 + thick * 0.5, 0,
        w, thick, d, skin)

    -- Interior geometry stays inside the replacement shell and follows the rig.
    for side = -1, 1, 2 do
        for lobe = 1, 2 do
            piece(Enum.PartType.Ball, "Lung",
                Vector3.new(w * 0.23, h * 0.34, d * 0.47),
                CFrame.new(side * w * 0.19,
                    h * (lobe == 1 and 0.13 or -0.12), 0),
                lobe == 1 and Color3.fromRGB(123, 54, 61)
                    or Color3.fromRGB(96, 39, 49))
        end
    end
    piece(Enum.PartType.Ball, "Heart",
        Vector3.new(w * 0.19, h * 0.29, d * 0.37),
        CFrame.new(-w * 0.035, h * 0.05, -d * 0.09)
            * CFrame.Angles(0, 0, -0.24),
        Color3.fromRGB(112, 15, 31))
    rod("Spine", Vector3.new(0, -h * 0.35, d * 0.34),
        Vector3.new(0, h * 0.35, d * 0.34),
        math.max(0.045, w * 0.055), bone)

    for side = -1, 1, 2 do
        for index = 1, 4 do
            local y = h * (0.29 - index * 0.14)
            local inner = Vector3.new(side * w * 0.07, y, -d * 0.12)
            local outer = Vector3.new(side * w * 0.39, y - h * 0.035,
                -d * 0.28)
            rod("Rib", inner, outer,
                math.max(0.028, w * 0.027), bone)
        end
    end
    rod("Vessel", Vector3.new(-w * 0.035, h * 0.12, -d * 0.16),
        Vector3.new(w * 0.18, h * 0.31, -d * 0.03),
        math.max(0.025, w * 0.027), dark)
end

local function poolBelow(wound, body)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {body.Parent}
    local hit = Workspace:Raycast(wound.Position, Vector3.new(0, -25, 0), params)
    if not hit or hit.Normal.Y < 0.65 then return end
    for _ = 1, 3 do
        local pool = Instance.new("Part")
        pool.Name = "BloodPoolV7"
        pool.Shape = Enum.PartType.Ball
        pool.Anchored = true
        pool.CanCollide = false
        pool.CanTouch = false
        pool.CanQuery = false
        pool.CastShadow = false
        pool.Material = Enum.Material.SmoothPlastic
        pool.Reflectance = 0.12
        pool.Color = Color3.fromRGB(rng:NextInteger(65, 100), 6, 13)
        pool.Size = Vector3.new(0.05, 0.018, 0.05)
        pool.Position = hit.Position + Vector3.new(
            rng:NextNumber(-0.5, 0.5), 0.014,
            rng:NextNumber(-0.5, 0.5))
        pool.Parent = Workspace
        table.insert(extras, pool)
        local target = Vector3.new(rng:NextNumber(0.28, 0.75),
            0.025, rng:NextNumber(0.22, 0.68))
        TweenService:Create(pool, TweenInfo.new(rng:NextNumber(1.1, 2.3),
            Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = target}):Play()
        Debris:AddItem(pool, 18)
    end
end

local function woundEffect(wound)
    if dead or not active or not atlas or not wound.Parent then return end
    local decal = wound:FindFirstChildWhichIsA("Decal")
    if not decal or changed[decal] then return end
    local region, body = regionFor(wound)
    if not body then return end
    if region == "torso" then
        replaceTorso(body, wound)
        if torsos[body] then
            changed[decal] = decal.Transparency
            decal.Transparency = 1
            poolBelow(wound, body)
        end
        return
    end
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
    for body, record in pairs(torsos) do
        if body.Parent then body.LocalTransparencyModifier = record.old end
        for decal, value in pairs(record.decals) do
            if decal.Parent then decal.Transparency = value end
        end
        for _, part in ipairs(record.pieces) do
            if part.Parent then part:Destroy() end
        end
    end
    table.clear(torsos)
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
            warn("Damage visuals v7: " .. result)
            return
        end
        atlas = result
        ok, result = loadAsset(ALT_ATLAS_URL, ALT_ATLAS_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v7: " .. result)
            return
        end
        altAtlas = result
        ok, result = loadAsset(BLOOD_URL, BLOOD_FILE)
        if not ok then
            button.Text = "ASSET FAILED"
            warn("Damage visuals v7: " .. result)
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

env.RagdollGoreV7Stop = function()
    dead = true
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    restore()
    gui:Destroy()
end
