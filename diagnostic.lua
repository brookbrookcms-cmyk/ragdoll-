-- Ragdoll Physics visual effect diagnostic (Delta / client side)
-- Tap CAPTURE, shoot or explode a ragdoll, then tap COPY REPORT.
-- This reads visible effects only. It does not invoke remotes or change gameplay.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if env.RagdollDiagnosticCleanup then
    pcall(env.RagdollDiagnosticCleanup)
end

local connections = {}
local gui = Instance.new("ScreenGui")
gui.Name = "RagdollDiagnostic"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(250, 115)
frame.Position = UDim2.new(0, 12, 0.5, -58)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local function label(text, y, height)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, -12, 0, height)
    item.Position = UDim2.fromOffset(6, y)
    item.BackgroundTransparency = 1
    item.TextColor3 = Color3.new(1, 1, 1)
    item.TextScaled = true
    item.Font = Enum.Font.SourceSansBold
    item.Text = text
    item.Parent = frame
    return item
end

label("Ragdoll effect capture", 5, 25)
local status = label("Tap CAPTURE, then shoot once", 31, 22)

local function button(text, x)
    local item = Instance.new("TextButton")
    item.Size = UDim2.fromOffset(112, 38)
    item.Position = UDim2.fromOffset(x, 67)
    item.BackgroundColor3 = Color3.fromRGB(130, 30, 45)
    item.TextColor3 = Color3.new(1, 1, 1)
    item.TextScaled = true
    item.Font = Enum.Font.SourceSansBold
    item.Text = text
    item.Parent = frame
    return item
end

local captureButton = button("CAPTURE", 7)
local copyButton = button("COPY REPORT", 130)

local active = false
local report = "No capture yet"
local records = {}
local seen = {}
local started = 0
local watched = {}
local captureConnection
local MAX_RECORDS = 180
local DURATION = 12

local function path(inst)
    local parts = {}
    local cursor = inst
    for _ = 1, 7 do
        if not cursor then break end
        table.insert(parts, 1, cursor.Name)
        cursor = cursor.Parent
    end
    return table.concat(parts, "/")
end

local function position(inst)
    local cursor = inst
    for _ = 1, 5 do
        if not cursor then break end
        if cursor:IsA("BasePart") then return cursor.Position end
        cursor = cursor.Parent
    end
end

local function nearby(inst)
    local pos = position(inst)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return pos and root and (pos - root.Position).Magnitude < 150
end

local function details(inst)
    local data = {class = inst.ClassName, path = path(inst)}
    local pos = position(inst)
    if pos then
        data.pos = {math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z)}
    end
    if inst:IsA("ParticleEmitter") then
        data.texture = inst.Texture
        data.enabled = inst.Enabled
        data.rate = inst.Rate
        data.lifetime = tostring(inst.Lifetime)
        data.speed = tostring(inst.Speed)
        data.color = tostring(inst.Color)
    elseif inst:IsA("Decal") or inst:IsA("Texture") then
        data.texture = inst.Texture
        data.transparency = inst.Transparency
    elseif inst:IsA("Trail") or inst:IsA("Beam") then
        data.texture = inst.Texture
        data.enabled = inst.Enabled
        data.color = tostring(inst.Color)
    elseif inst:IsA("Sound") then
        data.sound = inst.SoundId
        data.playing = inst.IsPlaying
    elseif inst:IsA("BasePart") then
        data.color = tostring(inst.Color)
        data.size = tostring(inst.Size)
        data.material = tostring(inst.Material)
        data.transparency = inst.Transparency
    end
    return data
end

local function relevant(inst)
    local name = string.lower(inst.Name)
    local named = name:find("blood", 1, true) or name:find("gore", 1, true)
        or name:find("splat", 1, true) or name:find("wound", 1, true)
        or name:find("hit", 1, true)
    if named then return true end
    if not nearby(inst) then return false end
    return inst:IsA("ParticleEmitter") or inst:IsA("Decal")
        or inst:IsA("Texture") or inst:IsA("Trail")
        or inst:IsA("Beam") or inst:IsA("Sound")
end

local function add(kind, inst)
    if #records >= MAX_RECORDS then return end
    local data = details(inst)
    data.kind = kind
    data.time = math.floor((os.clock() - started) * 10) / 10
    table.insert(records, data)
end

local function finish()
    if not active then return end
    active = false
    if captureConnection then captureConnection:Disconnect(); captureConnection = nil end
    local payload = {
        placeId = game.PlaceId,
        durationSeconds = DURATION,
        records = records,
        truncated = #records >= MAX_RECORDS,
    }
    report = "RAGDOLL_DIAGNOSTIC\n" .. game:GetService("HttpService"):JSONEncode(payload)
    status.Text = "Done: " .. #records .. " records. Tap COPY"
end

connect(captureButton.MouseButton1Click, function()
    if active then finish(); return end
    active = true
    records = {}
    seen = {}
    watched = {}
    started = os.clock()
    status.Text = "Capturing for 12 seconds..."
    captureButton.Text = "STOP"

    -- Existing templates can reveal the blood texture even if effects are reused.
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if relevant(inst) and #records < 25 then add("template", inst) end
    end
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if relevant(inst) then
            watched[inst] = tostring(details(inst).enabled) .. tostring(details(inst).playing)
            if #records < 50 then add("existing", inst) end
        end
    end

    captureConnection = Workspace.DescendantAdded:Connect(function(inst)
        if not active then return end
        task.defer(function()
            if active and inst.Parent and relevant(inst) and not seen[inst] then
                seen[inst] = true
                watched[inst] = tostring(details(inst).enabled) .. tostring(details(inst).playing)
                add("new", inst)
            end
        end)
    end)

    task.spawn(function()
        while active and os.clock() - started < DURATION do
            task.wait(0.15)
            for inst, old in pairs(watched) do
                if inst.Parent then
                    local data = details(inst)
                    local state = tostring(data.enabled) .. tostring(data.playing)
                    if state ~= old then
                        watched[inst] = state
                        add("stateChanged", inst)
                    end
                else
                    watched[inst] = nil
                end
            end
        end
        finish()
        captureButton.Text = "CAPTURE"
    end)
end)

connect(copyButton.MouseButton1Click, function()
    if active then finish() end
    if setclipboard then
        setclipboard(report)
        status.Text = "Copied! Paste it into chat"
    else
        status.Text = "Clipboard unavailable; see console"
        print(report)
    end
end)

env.RagdollDiagnosticCleanup = function()
    active = false
    if captureConnection then captureConnection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    gui:Destroy()
end
