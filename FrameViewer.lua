local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GITHUB_BASE_URL = "https://raw.githubusercontent.com/USER/roblox-frames/main/frames"
local LOCAL_DIR = "frames"
local FPS = 10
local FRAME_COUNT = 99
local LAYERS = 5
local SHOW_FPS_COUNTER = true
local SHOW_DEBUG_PANEL = true
local VERBOSE_LOG = true

local FRAME_TIME = 0.1

local startClock = os.clock()
local function dbg(fmt, ...)
    if not VERBOSE_LOG then return end
    print(string.format("[%.3fs] " .. fmt, os.clock() - startClock, ...))
end

if not isfolder(LOCAL_DIR) then
    makefolder(LOCAL_DIR)
end

-- ===== Local asset loading =====
print("=== Loading local assets via getcustomasset ===")
local loadStart = os.clock()
local assets = table.create(FRAME_COUNT)
local loaded = 0
local loadFailures = {}

for f = 1, FRAME_COUNT do
    task.spawn(function()
        local path = LOCAL_DIR .. "/f" .. f .. ".jpg"
        if isfile(path) then
            local ok, result = pcall(getcustomasset, path)
            if ok then
                assets[f] = result
                dbg("f%d: getcustomasset OK", f)
            else
                loadFailures[#loadFailures + 1] = f
                warn("getcustomasset failed for", path, result)
            end
        else
            loadFailures[#loadFailures + 1] = f
            warn("Missing file:", path)
        end
        loaded += 1
    end)
end

while loaded < FRAME_COUNT do
    task.wait()
end

local loadTime = os.clock() - loadStart
print(string.format(
    "=== Local load done: %d/%d ok, %d failed, in %.2fs ===",
    FRAME_COUNT - #loadFailures, FRAME_COUNT, #loadFailures, loadTime
))
if #loadFailures > 0 then
    warn("Failed frame indices:", table.concat(loadFailures, ", "))
end

-- ===== Preload in parallel chunks =====
print("=== Preloading via ContentProvider ===")
local preloadStart = os.clock()
local CHUNK_SIZE = 20
local chunksTotal = math.ceil(FRAME_COUNT / CHUNK_SIZE)
local chunksDone = 0

for startIndex = 1, FRAME_COUNT, CHUNK_SIZE do
    local chunk = {}
    for f = startIndex, math.min(startIndex + CHUNK_SIZE - 1, FRAME_COUNT) do
        if assets[f] then
            chunk[#chunk + 1] = assets[f]
        end
    end
    task.spawn(function()
        local ok, err = pcall(function()
            ContentProvider:PreloadAsync(chunk)
        end)
        chunksDone += 1
        if ok then
            dbg("Preload chunk %d/%d done (%d assets)", chunksDone, chunksTotal, #chunk)
        else
            warn("Preload chunk failed:", err)
        end
    end)
end

while chunksDone < chunksTotal do
    task.wait()
end
print(string.format("=== Preload done in %.2fs ===", os.clock() - preloadStart))

-- ===== Prime GPU cache =====
print("=== Priming GPU cache ===")
local primeGui = Instance.new("ScreenGui")
primeGui.Name = "PrimeGui"
primeGui.ResetOnSpawn = false
primeGui.Parent = playerGui

local primeLabel = Instance.new("ImageLabel")
primeLabel.Size = UDim2.fromOffset(1, 1)
primeLabel.BackgroundTransparency = 1
primeLabel.Visible = true
primeLabel.Parent = primeGui

for i = 1, FRAME_COUNT do
    if assets[i] then
        primeLabel.Image = assets[i]
    end
    RunService.RenderStepped:Wait()
end
primeGui:Destroy()
print("=== GPU cache primed ===")

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FrameViewer"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromOffset(512, 512)
background.Position = UDim2.fromScale(0.5, 0.5)
background.AnchorPoint = Vector2.new(0.5, 0.5)
background.BackgroundTransparency = 1
background.BorderSizePixel = 0
background.ZIndex = 0
background.Parent = screenGui

local labels = table.create(LAYERS)
for L = 1, LAYERS do
    local lbl = Instance.new("ImageLabel")
    lbl.Name = "Layer" .. L
    lbl.Size = UDim2.fromOffset(512, 512)
    lbl.Position = UDim2.fromScale(0.5, 0.5)
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.BackgroundTransparency = 1
    lbl.BorderSizePixel = 0
    lbl.ScaleType = Enum.ScaleType.Stretch
    lbl.Visible = true
    lbl.ZIndex = L
    lbl.Parent = screenGui
    labels[L] = lbl
end

local fpsLabel
if SHOW_FPS_COUNTER then
    fpsLabel = Instance.new("TextLabel")
    fpsLabel.Size = UDim2.fromOffset(220, 24)
    fpsLabel.Position = UDim2.new(0.5, -256, 0.5, -256 - 28)
    fpsLabel.AnchorPoint = Vector2.new(0, 0)
    fpsLabel.BackgroundTransparency = 1
    fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    fpsLabel.TextStrokeTransparency = 0
    fpsLabel.Font = Enum.Font.Code
    fpsLabel.TextSize = 18
    fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
    fpsLabel.Text = "Target: 10 | Actual: --"
    fpsLabel.ZIndex = 100
    fpsLabel.Parent = screenGui
end

local debugLabel
if SHOW_DEBUG_PANEL then
    debugLabel = Instance.new("TextLabel")
    debugLabel.Size = UDim2.fromOffset(320, 140)
    debugLabel.Position = UDim2.new(0.5, -256, 0.5, 256 + 8)
    debugLabel.AnchorPoint = Vector2.new(0, 0)
    debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    debugLabel.BackgroundTransparency = 0.5
    debugLabel.BorderSizePixel = 0
    debugLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
    debugLabel.Font = Enum.Font.Code
    debugLabel.TextSize = 14
    debugLabel.TextXAlignment = Enum.TextXAlignment.Left
    debugLabel.TextYAlignment = Enum.TextYAlignment.Top
    debugLabel.Text = "Initializing..."
    debugLabel.ZIndex = 100
    debugLabel.Parent = screenGui
end

-- ===== Playback =====
local FRONT_Z = 10

local function slotFor(frame)
    return ((frame - 1) % LAYERS) + 1
end

local function setSlotImage(frame)
    local slot = labels[slotFor(frame)]
    if assets[frame] then
        slot.Image = assets[frame]
    end
end

for f = 1, math.min(LAYERS, FRAME_COUNT) do
    setSlotImage(f)
end
labels[slotFor(1)].ZIndex = FRONT_Z

local currentFrame = 1
local nextSwitchTime = os.clock() + FRAME_TIME
local advancesThisSecond = 0
local skippedThisSecond = 0
local totalSkipped = 0
local totalAdvances = 0
local fpsWindowStart = os.clock()
local playbackStart = os.clock()

local heartbeatConn
heartbeatConn = RunService.Heartbeat:Connect(function()
    if not screenGui.Parent then
        heartbeatConn:Disconnect()
        return
    end

    local now = os.clock()
    if now < nextSwitchTime then return end

    local previousFrame = currentFrame
    local advancesThisTick = 0

    while now >= nextSwitchTime do
        nextSwitchTime += FRAME_TIME
        currentFrame += 1
        advancesThisTick += 1
        if currentFrame > FRAME_COUNT then
            currentFrame = 1
        end
    end

    advancesThisSecond += advancesThisTick
    totalAdvances += advancesThisTick

    if advancesThisTick > 1 then
        local skipped = advancesThisTick - 1
        skippedThisSecond += skipped
        totalSkipped += skipped
    end

    local primeFrame = ((currentFrame - 1 + (LAYERS - 1)) % FRAME_COUNT) + 1
    setSlotImage(primeFrame)

    labels[slotFor(currentFrame)].ZIndex = FRONT_Z
    labels[slotFor(previousFrame)].ZIndex = slotFor(previousFrame)

    local now2 = os.clock()
    if now2 - fpsWindowStart >= 1 then
        if SHOW_FPS_COUNTER and fpsLabel then
            fpsLabel.Text = string.format("Target: 10 | Actual: %d", advancesThisSecond)
        end
        if SHOW_DEBUG_PANEL and debugLabel then
            debugLabel.Text = string.format(
                "Frame: %d / %d\nActual FPS: %d (target 10)\nSkipped/sec: %d (total %d)\nUptime: %.1fs\nAssets loaded: %d/%d\nLoad fails: %d\nLoad time: %.2fs",
                currentFrame, FRAME_COUNT,
                advancesThisSecond,
                skippedThisSecond, totalSkipped,
                now2 - playbackStart,
                FRAME_COUNT - #loadFailures, FRAME_COUNT,
                #loadFailures,
                loadTime
            )
        end
        advancesThisSecond = 0
        skippedThisSecond = 0
        fpsWindowStart = now2
    end
end)
