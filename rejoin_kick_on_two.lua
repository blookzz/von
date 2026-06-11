--[[
    auto kick/rejoin on 2s
    discord.gg/rNvAU6cjVB
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local localPlayer = Players.LocalPlayer

local configPath = "von_plot_config.json"
local cfg = { timerEsp = false, rejoinOnTwo = false, kickOnTwo = false, posX = -120, posY = -89, minimized = false }

local function saveConfig()
    if writefile then
        pcall(writefile, configPath, HttpService:JSONEncode(cfg))
    end
end

local function loadConfig()
    if readfile and isfile and isfile(configPath) then
        local ok, dec = pcall(function() return HttpService:JSONDecode(readfile(configPath)) end)
        if ok and type(dec) == "table" then
            for k, v in pairs(dec) do cfg[k] = v end
        end
    end
end

loadConfig()

local C = {
    bg0       = Color3.fromRGB(12, 12, 12),
    bg1       = Color3.fromRGB(18, 18, 18),
    bg2       = Color3.fromRGB(26, 26, 26),
    accent    = Color3.fromRGB(220, 160, 60),
    accentDim = Color3.fromRGB(100, 72, 28),
    accentSec = Color3.fromRGB(255, 200, 90),
    toggleOff = Color3.fromRGB(38, 34, 26),
    toggleOn  = Color3.fromRGB(180, 120, 40),
    knob      = Color3.fromRGB(255, 220, 140),
    textPri   = Color3.fromRGB(235, 215, 170),
    textMuted = Color3.fromRGB(100, 85, 60),
    tweenFast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    tweenMed  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    toggleW   = 40,
    toggleH   = 20,
    knobSz    = 16,
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0, 8)
    c.Parent = p
end

local function stroke(p, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or C.accent
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = p
end

-- esp state
local espBillboard, espTimer, espAccent, espSpawnPart = nil, nil, nil, nil

local function getMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if not plot:IsA("Model") then continue end
        local sign = plot:FindFirstChild("PlotSign")
        if sign then
            local yb = sign:FindFirstChild("YourBase")
            if yb and yb:IsA("BillboardGui") and yb.Enabled then return plot end
            local sg = sign:FindFirstChild("SurfaceGui")
            local fr = sg and sg:FindFirstChild("Frame")
            local tl = fr and fr:FindFirstChild("TextLabel")
            if tl then
                local t = tl.Text:lower()
                if t:find(localPlayer.Name:lower()) or t:find(localPlayer.DisplayName:lower()) then
                    return plot
                end
            end
        end
    end
    return nil
end

local function getPlotTimer(plot)
    local pb    = plot:FindFirstChild("Purchases")
    local block = pb and pb:FindFirstChild("PlotBlock")
    local main  = block and block:FindFirstChild("Main")
    local bg    = main and main:FindFirstChild("BillboardGui")
    local rt    = bg and bg:FindFirstChild("RemainingTime")
    return rt and rt.Text or nil
end

-- returns the numeric seconds from a timer string like "1:45", "0:02", "2s", or "0"
local function parseTimer(text)
    if not text then return nil end
    -- "1:45" format
    local m, s = text:match("^(%d+):(%d+)$")
    if m and s then return tonumber(m) * 60 + tonumber(s) end
    -- "2s" or "0s" format
    local withSuffix = text:match("^(%d+)s$")
    if withSuffix then return tonumber(withSuffix) end
    -- plain number
    local raw = tonumber(text)
    return raw
end

local function createEspBillboard(spawnPart)
    if espBillboard then espBillboard:Destroy() end
    local bill = Instance.new("BillboardGui")
    bill.Name           = "vonPlotESP"
    bill.Adornee        = spawnPart
    bill.Size           = UDim2.new(0, 150, 0, 42)
    bill.StudsOffset    = Vector3.new(0, 5, 0)
    bill.AlwaysOnTop    = true
    bill.LightInfluence = 0
    bill.MaxDistance    = 5000
    bill.Parent         = game:GetService("CoreGui")

    local container = Instance.new("Frame", bill)
    container.Size                   = UDim2.new(1, 0, 1, 0)
    container.BackgroundColor3       = C.bg0
    container.BackgroundTransparency = 0.12
    container.BorderSizePixel        = 0
    corner(container, UDim.new(0, 6))

    local accentBar = Instance.new("Frame", container)
    accentBar.Size             = UDim2.new(0, 3, 1, -6)
    accentBar.Position         = UDim2.new(0, 3, 0, 3)
    accentBar.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    accentBar.BorderSizePixel  = 0
    corner(accentBar, UDim.new(1, 0))

    local ownerLabel = Instance.new("TextLabel", container)
    ownerLabel.Size                   = UDim2.new(1, -14, 0, 20)
    ownerLabel.Position               = UDim2.new(0, 10, 0, 1)
    ownerLabel.BackgroundTransparency = 1
    ownerLabel.Font                   = Enum.Font.GothamBlack
    ownerLabel.TextSize               = 11
    ownerLabel.TextColor3             = C.textPri
    ownerLabel.TextStrokeTransparency = 0.3
    ownerLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
    ownerLabel.TextXAlignment         = Enum.TextXAlignment.Left
    ownerLabel.TextTruncate           = Enum.TextTruncate.AtEnd
    ownerLabel.Text                   = localPlayer.Name

    local timerLabel = Instance.new("TextLabel", container)
    timerLabel.Size                   = UDim2.new(1, -14, 0, 18)
    timerLabel.Position               = UDim2.new(0, 10, 0, 22)
    timerLabel.BackgroundTransparency = 1
    timerLabel.Font                   = Enum.Font.GothamBold
    timerLabel.TextSize               = 10
    timerLabel.TextStrokeTransparency = 0.4
    timerLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
    timerLabel.TextXAlignment         = Enum.TextXAlignment.Left
    timerLabel.TextTruncate           = Enum.TextTruncate.AtEnd

    espBillboard = bill
    espTimer     = timerLabel
    espAccent    = accentBar
end

local function clearEsp()
    if espBillboard then espBillboard:Destroy() end
    espBillboard = nil; espTimer = nil; espAccent = nil; espSpawnPart = nil
end

-- gui setup
local vonGui = Instance.new("ScreenGui")
vonGui.Name           = "vonHub"
vonGui.ResetOnSpawn   = false
vonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
vonGui.Parent         = localPlayer:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size                   = UDim2.new(0, 240, 0, 170)
mainFrame.Position               = UDim2.new(0.5, cfg.posX, 0.5, cfg.posY)
mainFrame.BackgroundColor3       = C.bg1
mainFrame.BackgroundTransparency = 0.04
mainFrame.Active                 = true
mainFrame.Parent                 = vonGui
corner(mainFrame, UDim.new(0, 10))
stroke(mainFrame, C.accent, 1.2)

-- title bar / drag
local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = C.bg0
titleBar.BorderSizePixel  = 0
titleBar.Active           = true
titleBar.Selectable       = true
titleBar.Parent           = mainFrame
corner(titleBar, UDim.new(0, 10))

local titleLabel = Instance.new("TextLabel")
titleLabel.Size                   = UDim2.new(1, -52, 1, 0)
titleLabel.Position               = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font                   = Enum.Font.GothamBlack
titleLabel.TextSize               = 14
titleLabel.TextColor3             = C.accentSec
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.Text                   = "VON HUB"
titleLabel.Parent                 = titleBar

local accentLine = Instance.new("Frame")
accentLine.Size             = UDim2.new(1, -20, 0, 1)
accentLine.Position         = UDim2.new(0, 10, 1, 0)
accentLine.BackgroundColor3 = C.accent
accentLine.BackgroundTransparency = 0.5
accentLine.BorderSizePixel  = 0
accentLine.Parent           = titleBar

-- minimize button
local minBtn = Instance.new("TextButton")
minBtn.Size                   = UDim2.new(0, 28, 0, 20)
minBtn.AnchorPoint            = Vector2.new(1, 0.5)
minBtn.Position               = UDim2.new(1, -8, 0.5, 0)
minBtn.BackgroundColor3       = C.accentDim
minBtn.BorderSizePixel        = 0
minBtn.Font                   = Enum.Font.GothamBlack
minBtn.TextSize               = 14
minBtn.TextColor3             = C.accentSec
minBtn.Text                   = "–"
minBtn.Parent                 = titleBar
corner(minBtn, UDim.new(0, 5))

-- declared here so applyMinimized closure captures it; assigned below after creation
local contentFrame

local isMinimized = cfg.minimized == true
local FULL_H, MIN_H = 170, 36

local function applyMinimized(instant)
    local targetH = isMinimized and MIN_H or FULL_H
    contentFrame.Visible = not isMinimized
    minBtn.Text          = isMinimized and "+" or "–"
    if instant then
        mainFrame.Size = UDim2.new(0, 240, 0, targetH)
    else
        TweenService:Create(mainFrame, C.tweenMed, { Size = UDim2.new(0, 240, 0, targetH) }):Play()
    end
end

minBtn.MouseEnter:Connect(function()
    TweenService:Create(minBtn, C.tweenFast, { BackgroundColor3 = C.toggleOn }):Play()
end)
minBtn.MouseLeave:Connect(function()
    TweenService:Create(minBtn, C.tweenFast, { BackgroundColor3 = C.accentDim }):Play()
end)

-- drag logic
do
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
           input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging  = true
        dragStart = input.Position
        startPos  = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                -- save final position offset (scale stays 0.5)
                cfg.posX = mainFrame.Position.X.Offset
                cfg.posY = mainFrame.Position.Y.Offset
                saveConfig()
            end
        end)
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and
           input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
end

contentFrame = Instance.new("Frame")
contentFrame.Position         = UDim2.new(0, 0, 0, 36)
contentFrame.Size             = UDim2.new(1, 0, 1, -36)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent           = mainFrame

-- now contentFrame exists, wire up minimize behaviour
applyMinimized(true)
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    cfg.minimized = isMinimized
    applyMinimized(false)
    saveConfig()
end)

local layout = Instance.new("UIListLayout")
layout.Padding            = UDim.new(0, 6)
layout.SortOrder          = Enum.SortOrder.LayoutOrder
layout.FillDirection      = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Top
layout.Parent              = contentFrame

local padding = Instance.new("UIPadding")
padding.PaddingLeft   = UDim.new(0, 10)
padding.PaddingRight  = UDim.new(0, 10)
padding.PaddingTop    = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent        = contentFrame

-- toggle factory
local toggleStates = {}

local function makeToggle(labelText, cfgKey, order)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = C.bg2
    row.LayoutOrder      = order
    row.Parent           = contentFrame
    corner(row, UDim.new(0, 7))
    stroke(row, C.accentDim, 1)

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -60, 1, 0)
    lbl.Position               = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 13
    lbl.TextColor3             = C.textPri
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Text                   = labelText
    lbl.Parent                 = row

    local track = Instance.new("Frame")
    track.AnchorPoint    = Vector2.new(1, 0.5)
    track.Position       = UDim2.new(1, -10, 0.5, 0)
    track.Size           = UDim2.new(0, C.toggleW, 0, C.toggleH)
    track.BackgroundColor3 = cfg[cfgKey] and C.toggleOn or C.toggleOff
    track.Parent         = row
    corner(track, UDim.new(1, 0))

    local knob = Instance.new("Frame")
    knob.Size          = UDim2.new(0, C.knobSz, 0, C.knobSz)
    knob.Position      = cfg[cfgKey]
        and UDim2.new(0, C.toggleW - C.knobSz - 2, 0.5, -C.knobSz / 2)
        or  UDim2.new(0, 2, 0.5, -C.knobSz / 2)
    knob.BackgroundColor3 = C.knob
    knob.Parent        = track
    corner(knob, UDim.new(1, 0))

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.Parent             = row

    local state = { on = cfg[cfgKey] == true }

    local function setOn(on)
        state.on     = on
        cfg[cfgKey]  = on
        TweenService:Create(track, C.tweenFast, { BackgroundColor3 = on and C.toggleOn or C.toggleOff }):Play()
        TweenService:Create(knob,  C.tweenFast, {
            Position = on
                and UDim2.new(0, C.toggleW - C.knobSz - 2, 0.5, -C.knobSz / 2)
                or  UDim2.new(0, 2, 0.5, -C.knobSz / 2)
        }):Play()
        saveConfig()
    end

    -- onClick can be overridden after creation for mutual exclusion
    local clickHandler = { fn = function() setOn(not state.on) end }
    btn.MouseButton1Click:Connect(function() clickHandler.fn() end)

    btn.MouseEnter:Connect(function()
        TweenService:Create(row, C.tweenFast, { BackgroundColor3 = Color3.fromRGB(32, 30, 24) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(row, C.tweenFast, { BackgroundColor3 = C.bg2 }):Play()
    end)

    toggleStates[cfgKey] = { state = state, setOn = setOn }
    return state, setOn, clickHandler
end

makeToggle("Timer ESP", "timerEsp", 1)

local rejoinState, rejoinSetOn, rejoinClick = makeToggle("Rejoin on 2s", "rejoinOnTwo", 2)
local kickState,   kickSetOn,   kickClick   = makeToggle("Kick on 2s",   "kickOnTwo",   3)

-- mutual exclusion: override click handlers so only one can be on at a time
rejoinClick.fn = function()
    local on = not rejoinState.on
    rejoinSetOn(on)
    if on and kickState.on then kickSetOn(false) end
end
kickClick.fn = function()
    local on = not kickState.on
    kickSetOn(on)
    if on and rejoinState.on then rejoinSetOn(false) end
end

-- flags so rejoin/kick only fire once per threshold crossing
local rejoinFired = false
local kickFired   = false

local INTERVAL, lastTick = 0.2, 0

RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - lastTick < INTERVAL then return end
    lastTick = now

    local plot = getMyPlot()

    -- clear esp if no plot or no toggle
    if not plot or not cfg.timerEsp then
        if espBillboard then clearEsp() end
        if not plot then rejoinFired = false; kickFired = false end
        if plot and not cfg.timerEsp and espBillboard then clearEsp() end
        return
    end

    local spawnPart = plot:FindFirstChild("Spawn")
    if not spawnPart or not spawnPart:IsA("BasePart") then
        if espBillboard then clearEsp() end
        return
    end

    -- recreate billboard if needed
    if spawnPart ~= espSpawnPart or not espBillboard or not espBillboard.Parent then
        createEspBillboard(spawnPart)
        espSpawnPart = spawnPart
    end

    local timerText = getPlotTimer(plot)
    local seconds   = parseTimer(timerText)

    if espTimer and espAccent then
        local display = timerText or "OPEN"
        espTimer.Text       = display
        espTimer.TextColor3 = Color3.fromRGB(100, 255, 100)
        espAccent.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    end

    -- reset fire flags when timer is clearly above threshold (give a small buffer)
    if not seconds or seconds > 2 then
        rejoinFired = false
        kickFired   = false
        return
    end

    -- at 2s or below: fire rejoin or kick (whichever is on)
    if cfg.rejoinOnTwo and not rejoinFired then
        rejoinFired = true
        task.spawn(function()
            pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
        end)
    end

    if cfg.kickOnTwo and not kickFired then
        kickFired = true
        task.spawn(function()
            localPlayer:Kick("von: timer hit 2s")
        end)
    end
end)
