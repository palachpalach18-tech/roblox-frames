local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GITHUB_BASE_URL = "https://raw.githubusercontent.com/palachpalach18-tech/roblox-frames/main/frames"
local LOCAL_DIR = "frames"
local FPS = 30
local FRAME_COUNT = 100
local LAYERS = 5
local SHOW_FPS_COUNTER = true
local SHOW_DEBUG_PANEL = true
local VERBOSE_LOG = true
local DISCOVERY_BATCH_SIZE = 15
local MAX_FRAME_CAP = 2000

local startClock = os.clock()
local function dbg(fmt, ...)
	if not VERBOSE_LOG then return end
	print(string.format("[%.3fs] " .. fmt, os.clock() - startClock, ...))
end

if not isfolder(LOCAL_DIR) then
	makefolder(LOCAL_DIR)
end

local function httpGet(url)
	local ok, result
	if syn and syn.request then
		ok, result = pcall(syn.request, { Url = url, Method = "GET" })
	elseif http_request then
		ok, result = pcall(http_request, { Url = url, Method = "GET" })
	elseif request then
		ok, result = pcall(request, { Url = url, Method = "GET" })
	else
		ok, result = pcall(function()
			return { StatusCode = 200, Body = game:HttpGet(url) }
		end)
	end
	if ok and result and result.StatusCode == 200 then
		return true, result.Body, result.StatusCode
	end
	return false, nil, result and result.StatusCode or "N/A"
end

-- ===== Parallel batch discovery + fetch =====
print("=== Discovery: probing GitHub in parallel batches ===")
local discoveryStart = os.clock()
local cacheHits, fetchedCount = 0, 0
local batchStart = 1
local stop = false
local actualFrameCount = 0

while not stop and batchStart <= MAX_FRAME_CAP do
	local batchEnd = math.min(batchStart + DISCOVERY_BATCH_SIZE - 1, MAX_FRAME_CAP)
	local results = {}
	local pending = 0

	for idx = batchStart, batchEnd do
		pending += 1
		task.spawn(function()
			local path = LOCAL_DIR .. "/f" .. idx .. ".jpg"
			if isfile(path) then
				results[idx] = true
				cacheHits += 1
				dbg("f%d: cache hit", idx)
			else
				local url = GITHUB_BASE_URL .. "/f" .. idx .. ".jpg"
				local ok, body, status = httpGet(url)
				if ok then
					writefile(path, body)
					results[idx] = true
					fetchedCount += 1
					dbg("f%d: fetched (%d bytes, status %s)", idx, #body, tostring(status))
				else
					results[idx] = false
					dbg("f%d: not found (status %s)", idx, tostring(status))
				end
			end
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end

	for idx = batchStart, batchEnd do
		if results[idx] then
			actualFrameCount = idx
		else
			stop = true
			break
		end
	end

	if batchEnd - batchStart + 1 > 0 and actualFrameCount < batchEnd then
		stop = true
	end

	batchStart = batchEnd + 1
end

local discoveryTime = os.clock() - discoveryStart

if actualFrameCount >= FRAME_COUNT then
	actualFrameCount = FRAME_COUNT
end

if actualFrameCount == 0 then
	error("No frames found — check GITHUB_BASE_URL and that f1.jpg exists.")
end

FRAME_COUNT = actualFrameCount

print(string.format(
	"=== Discovery done: %d frames (%d cached, %d fetched) in %.2fs ===",
	FRAME_COUNT, cacheHits, fetchedCount, discoveryTime
))

local FRAME_TIME = 1 / FPS

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FrameViewer"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local background = Instance.new("Frame")
background.Name = "Background"
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
	lbl.ScaleType = Enum.ScaleType.Fit
	lbl.Visible = true
	lbl.ZIndex = L
	lbl.Parent = screenGui
	labels[L] = lbl
end

local fpsLabel
if SHOW_FPS_COUNTER then
	fpsLabel = Instance.new("TextLabel")
	fpsLabel.Name = "FpsCounter"
	fpsLabel.Size = UDim2.fromOffset(220, 24)
	fpsLabel.Position = UDim2.new(0.5, -256, 0.5, -256 - 28)
	fpsLabel.AnchorPoint = Vector2.new(0, 0)
	fpsLabel.BackgroundTransparency = 1
	fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	fpsLabel.TextStrokeTransparency = 0
	fpsLabel.Font = Enum.Font.Code
	fpsLabel.TextSize = 18
	fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	fpsLabel.Text = "Target: " .. FPS .. " | Actual: --"
	fpsLabel.ZIndex = 100
	fpsLabel.Parent = screenGui
end

local debugLabel
if SHOW_DEBUG_PANEL then
	debugLabel = Instance.new("TextLabel")
	debugLabel.Name = "DebugPanel"
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
			warn("Missing after fetch:", path)
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

-- ===== Preload =====
print("=== Preloading via ContentProvider ===")
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
		if not ok then
			warn("Preload chunk failed:", err)
		end
	end)
end
print(string.format("Preloading started for %d chunks.", chunksTotal))

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

local currentFrame       = 1
local nextSwitchTime     = os.clock() + FRAME_TIME
local advancesThisSecond = 0
local skippedThisSecond  = 0
local totalSkipped       = 0
local totalAdvances      = 0
local fpsWindowStart     = os.clock()
local playbackStart      = os.clock()

local heartbeatConn
heartbeatConn = RunService.Heartbeat:Connect(function()
	if not screenGui.Parent then
		heartbeatConn:Disconnect()
		return
	end

	local now = os.clock()
	if now < nextSwitchTime then
		return
	end

	local previousFrame = currentFrame
	currentFrame = (currentFrame % FRAME_COUNT) + 1
	nextSwitchTime = now + FRAME_TIME

	advancesThisSecond += 1
	totalAdvances      += 1

	local primeFrame = ((currentFrame - 1 + (LAYERS - 1)) % FRAME_COUNT) + 1
	setSlotImage(primeFrame)

	labels[slotFor(currentFrame)].ZIndex  = FRONT_Z
	labels[slotFor(previousFrame)].ZIndex = slotFor(previousFrame)

	if now - fpsWindowStart >= 1 then
		if SHOW_FPS_COUNTER then
			fpsLabel.Text = string.format("Target: %d | Actual: %d", FPS, advancesThisSecond)
		end
		if SHOW_DEBUG_PANEL then
			debugLabel.Text = string.format(
				"Frame: %d / %d\nActual FPS: %d (target %d)\nSkipped/sec: %d (total %d)\nUptime: %.1fs\nAssets loaded: %d/%d\nLoad fails: %d\nDiscovery: %.2fs | Load: %.2fs",
				currentFrame, FRAME_COUNT,
				advancesThisSecond, FPS,
				skippedThisSecond, totalSkipped,
				now - playbackStart,
				FRAME_COUNT - #loadFailures, FRAME_COUNT,
				#loadFailures,
				discoveryTime, loadTime
			)
		end
		advancesThisSecond = 0
		skippedThisSecond  = 0
		fpsWindowStart     = now
	end
end)
