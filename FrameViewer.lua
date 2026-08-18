local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FRAME_COUNT = 10
local FPS = 10
local FRAME_TIME = 0.1

--// GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FrameViewer"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local imageLabel = Instance.new("ImageLabel")
imageLabel.Name = "Animation"
imageLabel.Size = UDim2.fromOffset(512, 512)
imageLabel.Position = UDim2.fromScale(0.5, 0.5)
imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
imageLabel.BackgroundTransparency = 1
imageLabel.BorderSizePixel = 0
imageLabel.ScaleType = Enum.ScaleType.Stretch
imageLabel.Visible = false
imageLabel.Parent = screenGui

--// Get all local asset IDs in parallel
local assets = table.create(FRAME_COUNT)
local completed = 0

for i = 1, FRAME_COUNT do
    task.spawn(function()
        local path = "frames/f" .. i .. ".jpg"
        if isfile(path) then
            local success, asset = pcall(getcustomasset, path)
            if success then
                assets[i] = asset
            else
                warn("Failed:", path)
            end
        else
            warn("Missing:", path)
        end
        completed += 1
    end)
end

while completed < FRAME_COUNT do
    task.wait()
end
print("Asset IDs ready.")

--// Build preload list
local preloadList = {}
for i = 1, FRAME_COUNT do
    if assets[i] then
        preloadList[#preloadList + 1] = assets[i]
    end
end

--// Preload
local preloadSuccess, preloadError = pcall(function()
    ContentProvider:PreloadAsync(preloadList)
end)
if not preloadSuccess then
    warn("Preload error:", preloadError)
end
print("All frames preloaded.")

--// Prime GPU cache
for i = 1, FRAME_COUNT do
    if assets[i] then
        imageLabel.Image = assets[i]
    end
    RunService.RenderStepped:Wait()
end
print("Frames primed.")

--// Start playback
imageLabel.Image = assets[1]
imageLabel.Visible = true

local currentFrame = 1
local elapsed = 0
local connection

connection = RunService.RenderStepped:Connect(function(deltaTime)
    if not screenGui.Parent then
        connection:Disconnect()
        return
    end

    elapsed = math.min(elapsed + deltaTime, FRAME_TIME * 3)

    if elapsed >= FRAME_TIME then
        elapsed -= FRAME_TIME
        currentFrame += 1
        if currentFrame > FRAME_COUNT then
            currentFrame = 1
        end
        local asset = assets[currentFrame]
        if asset then
            imageLabel.Image = asset
        end
    end
end)
