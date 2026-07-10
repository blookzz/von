--[[
  von hub gag2
  open source
  discord.gg/rNvAU6cjVB
]]

local function LoadLibrary(name, url)
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if not ok then
        error("[VonHub] Could not load " .. name .. " — check your internet connection / executor's HttpGet support. Underlying error: " .. tostring(result))
    end
    if result == nil then
        error("[VonHub] " .. name .. " loaded as nil — the URL may be down or blocked.")
    end
    return result
end

local Fluent          = LoadLibrary("Fluent", "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
local SaveManager      = LoadLibrary("SaveManager", "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua")
local InterfaceManager = LoadLibrary("InterfaceManager", "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua")

--------------------------------------------------
-- SERVICES
--------------------------------------------------

local Players        = game:GetService("Players")
local CoreGui        = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer    = Players.LocalPlayer
local Character      = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid       = Character:WaitForChild("Humanoid")
local HRP            = Character:WaitForChild("HumanoidRootPart")


--------------------------------------------------
-- SHARED REMOTE + ASSET HELPERS
--------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedModules     = ReplicatedStorage:WaitForChild("SharedModules")
local Packet            = SharedModules:WaitForChild("Packet")
local RemoteEvent       = Packet:WaitForChild("RemoteEvent")

--------------------------------------------------
-- OPCODE RESOLVER
-- Scans RemoteEvent attributes at startup to build a name→id lookup table.
-- Use Op("Name") anywhere instead of a hardcoded number.
--------------------------------------------------

local OpcodeMap = {}
do
    local list = {}
    for name, id in pairs(RemoteEvent:GetAttributes()) do
        OpcodeMap[name] = id
        table.insert(list, {id = id, name = name})
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, v in ipairs(list) do
    end
end

local function Op(name)
    local id = OpcodeMap[name]
    if not id then
        warn("[VonHub] Op(): unknown opcode name '" .. tostring(name) .. "' — remote attributes may not have loaded yet.")
    end
    return id
end

-- Fires the shared remote safely and logs errors.
local function FireRemote(...)
    local args = { ... }
    local ok, err = pcall(function() RemoteEvent:FireServer(table.unpack(args)) end)
    if not ok then warn("[VonHub] FireRemote error:", err) end
end

-- Returns a list of child names from an Instance path (pcall-safe).
local function GetChildNames(instance)
    local names = {}
    local ok, children = pcall(function() return instance:GetChildren() end)
    if ok then
        for _, child in ipairs(children) do
            table.insert(names, child.Name)
        end
    end
    return names
end

-- Safe shop list builder: filters out any name over 50 chars (garbage data).
local function SafeNames(getChildren)
    local ok, items = pcall(getChildren)
    if not ok then return {} end
    local names = {}
    for _, item in ipairs(items) do
        local name = item.Name
        if type(name) == "string" and #name > 0 and #name <= 50 then
            table.insert(names, name)
        end
    end
    return names
end

local function GetSeedShopList()
    return SafeNames(function() return ReplicatedStorage.StockValues.SeedShop.Items:GetChildren() end)
end

local function GetGearShopList()
    return SafeNames(function() return ReplicatedStorage.StockValues.GearShop.Items:GetChildren() end)
end

local function GetCrateShopList()
    return SafeNames(function() return ReplicatedStorage.StockValues.CrateShop.Items:GetChildren() end)
end

local function GetPetAssetList()
    return SafeNames(function() return ReplicatedStorage.Assets.Pets:GetChildren() end)
end

-- Returns all WildPet instances currently in workspace.Map.WildPetRef.
local function GetWildPets()
    local ok, ref = pcall(function()
        return workspace.Map.WildPetRef:GetChildren()
    end)
    if not ok then return {} end
    return ref
end

-- Returns the size attribute of a WildPet model (number or 0).
local function GetWildPetSize(petModel)
    local ok, sz = pcall(function() return petModel:GetAttribute("Size") end)
    if ok and type(sz) == "number" then return sz end
    -- Fallback: check the primary part's Size magnitude.
    local ok2, pp = pcall(function() return petModel.PrimaryPart end)
    if ok2 and pp then return pp.Size.Magnitude end
    return 0
end

-- Classifies a WildPet size number into a label.
local function ClassifyPetSize(sz)
    if sz <= 0 then return "Unknown" end
    if sz < 2   then return "Tiny"    end
    if sz < 3   then return "Small"   end
    if sz < 4   then return "Medium"  end
    if sz < 5   then return "Large"   end   -- >3 and <=5 → big
    if sz < 8   then return "Huge"    end   -- >5 → huge
    return "Titanic"
end

-- Finds my plot inside workspace.Gardens by matching DisplayName label.
local function FindMyPlot()
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    local myName = string.lower(LocalPlayer.DisplayName)
    for _, plot in ipairs(gardens:GetChildren()) do
        if plot:IsA("Model") or plot:IsA("Folder") then
            for _, desc in ipairs(plot:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local t = string.lower(desc.Text or "")
                    if string.find(t, "'s garden") and string.find(t, myName, 1, true) then
                        return plot
                    end
                end
            end
        end
    end
    return nil
end

-- Finds the PlotSizeReferenceVisual part in a plot.
local function GetPlotVisual(plot)
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc.Name == "PlotSizeReferenceVisual" then
            return desc
        end
    end
    return nil
end

-- Returns the center (X, Z) of the plot at the player's current Y.
local function GetPlotCenterAtPlayerY(plot)
    local visual = GetPlotVisual(plot)
    if not visual then return nil end
    local center = visual.CFrame.Position
    local playerY = HRP and HRP.Position.Y or center.Y
    return Vector3.new(center.X, playerY, center.Z)
end

-- Returns a random X/Z inside the plot at the bottom face Y of PlotSizeReferenceVisual.
local function GetRandomPlotPosition(plot)
    local visual = GetPlotVisual(plot)
    if not visual then return nil end
    local cf  = visual.CFrame
    local sz  = visual.Size
    local rx  = (math.random() - 0.5) * sz.X
    local rz  = (math.random() - 0.5) * sz.Z
    local bottomY = -sz.Y / 2  -- bottom face in local space
    return cf:PointToWorldSpace(Vector3.new(rx, bottomY, rz))
end

-- Returns all seed instances in the player's Backpack for a given seed name.
local function GetBackpackSeeds(seedName)
    local seeds = {}
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return seeds end
    for _, item in ipairs(bp:GetChildren()) do
        if item.Name == seedName then
            table.insert(seeds, item)
        end
    end
    return seeds
end



--------------------------------------------------
-- INVENTORY FULL DETECTION
-- Shared between Collect and Sell tabs.
-- Triggers on new "Your inventory is full" notifications only.
-- Clears when an item with "]" in the name is removed from the backpack.
--------------------------------------------------

local InventoryFull = false

local function CountInventoryItems()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return 0 end
    local count = 0
    for _, item in ipairs(bp:GetChildren()) do
        if string.find(item.Name, "%]$") then
            count = count + 1
        end
    end
    return count
end

local function IsInventoryFull()
    return InventoryFull
end

task.spawn(function()
    local lastCount = CountInventoryItems()
    while true do
        task.wait(0.1)
        local ok, text = pcall(function()
            return LocalPlayer.PlayerGui.TopNotification.Frame.Notification_UI:GetAttribute("OG")
        end)
        local notifFull = ok and text ~= nil and string.find(string.lower(tostring(text)), "your inventory is full") ~= nil
        if notifFull and not InventoryFull then
            InventoryFull = true
        end
        if InventoryFull then
            local currentCount = CountInventoryItems()
            if currentCount < lastCount then
                InventoryFull = false
            end
            lastCount = currentCount
        else
            lastCount = CountInventoryItems()
        end
    end
end)

--------------------------------------------------
-- WINDOW
--------------------------------------------------

local Window = Fluent:CreateWindow({
    Title      = "Von Hub",
    SubTitle   = ".gg/rNvAU6cjVB",
    TabWidth   = 160,
    Size       = UDim2.fromOffset(620, 480),
    Acrylic    = true,
    Theme      = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})


local Tabs = {
    Home        = Window:AddTab({ Title = "Home",           Icon = "home"         }),
    PlantSeeds  = Window:AddTab({ Title = "Plant Seeds",    Icon = "sprout"       }),
    Collect     = Window:AddTab({ Title = "Collect Crops",  Icon = "shopping-bag" }),
    Sell        = Window:AddTab({ Title = "Sell Crops",     Icon = "dollar-sign"  }),
    Buy         = Window:AddTab({ Title = "Buy Items",      Icon = "shopping-cart"}),
    Events      = Window:AddTab({ Title = "Special Events", Icon = "star"         }),
    ESP         = Window:AddTab({ Title = "ESP",            Icon = "eye"          }),
    Movement    = Window:AddTab({ Title = "Movement",       Icon = "move"         }),
    Performance = Window:AddTab({ Title = "Performance",    Icon = "gauge"        }),
    Settings    = Window:AddTab({ Title = "Settings",       Icon = "settings"     }),
}

for name, tab in pairs(Tabs) do
end

local Options = Fluent.Options

--------------------------------------------------
-- WAIT FOR ROOT SAFELY
--------------------------------------------------

local function GetRoot()
    local waited = 0
    while not Window.Root do
        task.wait()
        waited = waited + 1
        if waited % 60 == 0 then
        end
    end
    return Window.Root
end

local Root = GetRoot()

--------------------------------------------------
-- MOBILE BUTTON SYSTEM
--------------------------------------------------

local ICON_ID  = "rbxassetid://10734897956"
local MobileGui, Button

local function HideMobileButton()
    if MobileGui then
        MobileGui:Destroy()
        MobileGui = nil
        Button    = nil
    end
end

local function ShowMobileButton()
    if MobileGui then return end

    MobileGui = Instance.new("ScreenGui")
    MobileGui.Name           = "VonHubMobileButton"
    MobileGui.ResetOnSpawn   = false
    MobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local ok = pcall(function() MobileGui.Parent = CoreGui end)
    if not ok then MobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    Button = Instance.new("ImageButton")
    Button.Parent               = MobileGui
    Button.Size                 = UDim2.fromOffset(55, 55)
    Button.Position             = UDim2.fromOffset(15, 15)
    Button.BackgroundColor3     = Color3.fromRGB(30, 30, 30)
    Button.BackgroundTransparency = 0.2
    Button.Image                = ""
    Button.AutoButtonColor      = true

    local Corner  = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 12)
    Corner.Parent = Button

    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 1
    Stroke.Color     = Color3.fromRGB(80, 80, 80)
    Stroke.Parent    = Button

    local Icon = Instance.new("ImageLabel")
    Icon.Parent               = Button
    Icon.BackgroundTransparency = 1
    Icon.Image                = ICON_ID
    Icon.Size                 = UDim2.fromOffset(28, 28)
    Icon.Position             = UDim2.new(0.5, -14, 0.5, -14)
    Icon.ZIndex               = 2

    Button.MouseButton1Click:Connect(function()
        HideMobileButton()
        task.wait(0.05)
        Root.Visible = true
    end)
end

Root:GetPropertyChangedSignal("Visible"):Connect(function()
    if Root.Visible then HideMobileButton() else ShowMobileButton() end
end)

local function SetUI(state)
    if Root then Root.Visible = state end
end

task.spawn(function()
    task.wait(0.5)
    SetUI(true)
end)

--------------------------------------------------
-- STATE
--------------------------------------------------

local SavedPosition = nil

local State = {
    -- Home
    WalkSpeed        = 16,
    WalkSpeedEnabled = false,
    NoclipEnabled    = false,
    InfJumpEnabled   = false,

    -- Plant Seeds
    PlantDisableTp   = false,
    PlantInterval    = 1,
    AutoPlant        = false,
    AutoPlantAll     = false,

    -- Collect
    CollectDisableTp    = false,
    StopIfFull          = false,
    CollectInterval     = 1,
    AutoCollect         = false,
    AutoCollectAll      = false,

    -- Sell
    OnlySellIfFull      = false,
    AutoSell            = false,

    -- Events
    NightMinValue       = 0,
    AutoFarmCrops       = false,
    AutoFarmHighest     = false,
    AutoGoldSeed        = false,
    AutoRainbowSeed     = false,
    AutoMegaSeed        = false,
    ActiveSeedFarm      = nil,   -- "Gold Seed" | "Rainbow Seed" | "Mega Seed" | nil

    -- ESP
    EspCropsEnabled     = false,
    EspCropMinValue     = 0,
    EspPetsEnabled      = false,

    -- Buy
    AutoBuySeeds        = false,
    AutoBuyGear         = false,
    AutoBuyCrates       = false,
    AutoBuyPets         = false,
}

--------------------------------------------------
-- MOVEMENT SYSTEM
-- Central tween / teleport dispatcher used by every auto-feature.
-- Priority queue: higher number = goes first (teleport/tween sooner).
-- If TweenMode is on, every move becomes a tween. Only one tween at a time.
--
-- TeleportFunctions that participate in the priority system:
--   1 = Plant (Auto Plant)
--   2 = Collect (Auto Collect)
--   3 = BuyPets (Auto Buy Pets)
--   4 = NightSteal (Night Event steal)
--   5 = ReturnHome (Night Event return to own plot)
--
-- Each feature calls: MovementSystem.RequestMove(featureKey, targetCFrame, callback)
-- The system resolves priority ordering and queues accordingly.
--------------------------------------------------

local MovementSystem = {
    TweenMode   = false,
    TweenSpeed  = 50,   -- studs per second

    -- Priority: 1 (lowest) to 5 (highest). Higher = executes first.
    Priority = {
        Plant       = 3,
        Collect     = 3,
        BuyPets     = 3,
        NightSteal  = 3,
        SeedFarm    = 3,
    },

    -- Internal state
    _tweenActive      = false,
    _queue            = {},   -- { featureKey, targetCF, callback, priority }
    _queueRunning     = false,
    -- When true, NightSteal is mid-cycle (steal + return home). Other features
    -- will queue behind it and wait until the full cycle finishes.
    _nightStealLocked = false,
}

-- Execute one tween from current HRP position to targetCF at TweenSpeed studs/sec.
-- Calls onDone() when complete or on abort.
local function ExecuteTween(targetCF, onDone)
    if not HRP then
        if onDone then onDone() end
        return
    end
    MovementSystem._tweenActive = true
    local startCF   = HRP.CFrame
    local startPos  = startCF.Position
    local endPos    = targetCF.Position
    local dist      = (endPos - startPos).Magnitude
    local speed     = math.max(1, MovementSystem.TweenSpeed)
    local duration  = dist / speed

    if duration < 0.01 then
        -- Already there
        HRP.CFrame = targetCF
        MovementSystem._tweenActive = false
        if onDone then onDone() end
        return
    end

    local elapsed = 0
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not HRP then
            conn:Disconnect()
            MovementSystem._tweenActive = false
            if onDone then onDone() end
            return
        end
        elapsed = elapsed + dt
        local t = math.clamp(elapsed / duration, 0, 1)
        HRP.CFrame = startCF:Lerp(targetCF, t)
        if t >= 1 then
            conn:Disconnect()
            MovementSystem._tweenActive = false
            if onDone then onDone() end
        end
    end)
end

-- Flush the priority queue: sort by priority (highest first), execute in order.
local function FlushMoveQueue()
    if MovementSystem._queueRunning then return end
    MovementSystem._queueRunning = true

    task.spawn(function()
        while #MovementSystem._queue > 0 do
            -- Sort descending by priority so highest goes first
            table.sort(MovementSystem._queue, function(a, b) return a.priority > b.priority end)
            local entry = table.remove(MovementSystem._queue, 1)
            local targetCF = entry.targetCF
            local cb       = entry.callback

            if MovementSystem.TweenMode then
                -- Block until tween finishes
                local done = false
                ExecuteTween(targetCF, function() done = true end)
                while not done do task.wait() end
            else
                -- Instant teleport
                if HRP then
                    HRP.CFrame = targetCF
                    task.wait(0.05)
                end
                if cb then cb() end
            end

            -- Small gap between moves to avoid server spam
            task.wait(0.02)
        end
        MovementSystem._queueRunning = false
    end)
end

-- Public API: queue a move request from a feature.
-- featureKey: string key matching MovementSystem.Priority
-- targetCF: CFrame to move to
-- callback: optional function called after the move completes (teleport mode only; tween calls it via ExecuteTween)
function MovementSystem.RequestMove(featureKey, targetCF, callback)
    -- If a night steal cycle is in progress, non-night features must wait.
    -- NightSteal itself is exempt (it drives the lock).
    if featureKey ~= "NightSteal" and MovementSystem._nightStealLocked then
        task.spawn(function()
            while MovementSystem._nightStealLocked do task.wait(0.1) end
            MovementSystem.RequestMove(featureKey, targetCF, callback)
        end)
        return
    end

    if MovementSystem.TweenMode and MovementSystem._tweenActive then
        -- Tween in progress; queue it (will be sorted by priority on flush)
        table.insert(MovementSystem._queue, {
            featureKey = featureKey,
            targetCF   = targetCF,
            callback   = callback,
            priority   = MovementSystem.Priority[featureKey] or 1,
        })
        FlushMoveQueue()
        return
    end

    if MovementSystem.TweenMode then
        -- No tween running; go immediately via the queue so callbacks are consistent
        table.insert(MovementSystem._queue, {
            featureKey = featureKey,
            targetCF   = targetCF,
            callback   = callback,
            priority   = MovementSystem.Priority[featureKey] or 1,
        })
        FlushMoveQueue()
    else
        -- Teleport mode: instant, no queue needed
        if HRP then
            HRP.CFrame = targetCF
            task.wait(0.05)
        end
        if callback then callback() end
    end
end

--------------------------------------------------
-- APPLY FUNCTIONS REGISTRY
-- SetValue() (used by LoadConfig) updates the UI/Option.Value but does NOT
-- fire OnChanged. Every toggle with a real effect registers its handler here
-- so LoadConfig can call it manually after restoring a saved value.
--------------------------------------------------

local ApplyFunctions = {}

--------------------------------------------------
-- CHARACTER REFRESH ON RESPAWN
-- Character/Humanoid/HRP were only captured once, when the script started.
-- If the character ever dies/resets, those become stale references pointing
-- at destroyed instances, and every toggle silently stops doing anything.
-- This re-grabs them on every respawn and re-applies whatever is enabled.
--------------------------------------------------

local function RefreshCharacterRefs(newCharacter)
    Character = newCharacter or LocalPlayer.Character
    if not Character then
        return
    end
    Humanoid = Character:WaitForChild("Humanoid", 5)
    HRP      = Character:WaitForChild("HumanoidRootPart", 5)

    for key, fn in pairs(ApplyFunctions) do
        local ok, err = pcall(fn)
        if not ok then
        end
    end
end

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    RefreshCharacterRefs(newCharacter)
end)

--------------------------------------------------
-- TAB 1: HOME
--------------------------------------------------

do
    -- Community section
    Tabs.Home:AddParagraph({
        Title   = "Von Hub",
        Content = "Welcome! Join our Discord community for updates, support, and more."
    })

    Tabs.Home:AddButton({
        Title   = "Copy Discord Link",
        Desc    = "Copies the Discord invite to your clipboard",
        Callback = function()
            setclipboard("https://discord.gg/rNvAU6cjVB")
            Fluent:Notify({ Title = "Copied!", Content = "Discord link copied to clipboard.", Duration = 3 })
        end
    })

    -- Local Player section
    Tabs.Home:AddParagraph({
        Title   = "Local Player",
        Content = "Modify your character's movement properties."
    })

    local SpeedInput = Tabs.Home:AddInput("WalkSpeedInput", {
        Title       = "Set Walk Speed",
        Default     = "16",
        Placeholder = "Enter speed (default 16)...",
        Numeric     = true,
        Callback    = function(Value)
            local num = tonumber(Value)
            if num then
                State.WalkSpeed = num
                if State.WalkSpeedEnabled and Humanoid then
                    Humanoid.WalkSpeed = num
                end
            end
        end
    })

    local WalkSpeedToggle = Tabs.Home:AddToggle("WalkSpeedToggle", {
        Title   = "Enable Walk Speed",
        Default = false
    })
    -- Teleport-based walk speed: every Heartbeat we read the humanoid's MoveDirection
    -- (XZ only) and nudge HRP forward by (speed - 16) extra studs, keeping Y intact
    -- so gravity and jumping are unaffected. Humanoid.WalkSpeed stays at 16 so the
    -- server sees normal movement — the extra distance comes from position offsetting.
    local WalkSpeedConnection = nil

    local function EnableTpWalkSpeed()
        -- Disconnect any stale connection first (e.g. after character respawn)
        if WalkSpeedConnection then
            WalkSpeedConnection:Disconnect()
            WalkSpeedConnection = nil
        end
        WalkSpeedConnection = RunService.Heartbeat:Connect(function(dt)
            if not HRP or not Humanoid then return end
            local move = Humanoid.MoveDirection
            if move.Magnitude < 0.1 then return end  -- standing still, skip
            local extra = (State.WalkSpeed - 16) * dt
            if extra <= 0 then return end
            -- Apply only on XZ; Y stays as-is so physics handles gravity/jumps
            local offset = Vector3.new(move.X, 0, move.Z).Unit * extra
            HRP.CFrame = HRP.CFrame + offset
        end)
    end

    local function DisableTpWalkSpeed()
        if WalkSpeedConnection then
            WalkSpeedConnection:Disconnect()
            WalkSpeedConnection = nil
        end
        -- Restore Humanoid.WalkSpeed to default in case it was changed elsewhere
        if Humanoid then Humanoid.WalkSpeed = 16 end
    end

    local function ApplyWalkSpeed()
        State.WalkSpeedEnabled = Options.WalkSpeedToggle.Value
        if State.WalkSpeedEnabled then
            EnableTpWalkSpeed()
        else
            DisableTpWalkSpeed()
        end
    end
    WalkSpeedToggle:OnChanged(ApplyWalkSpeed)
    ApplyFunctions.WalkSpeedToggle = ApplyWalkSpeed

    local NoclipToggle = Tabs.Home:AddToggle("NoclipToggle", {
        Title   = "No Clip",
        Default = false
    })
    -- Removes collision only from the player's own character parts.
    -- No Heartbeat loop — just set once on enable and restore on disable.
    -- This lets the player walk through walls while world collision still works normally.
    local NoclipOriginal = {}   -- BasePart → original CanCollide value

    local function EnableNoclip()
        if not Character then return end
        NoclipOriginal = {}
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") then
                NoclipOriginal[part] = part.CanCollide
                part.CanCollide = false
            end
        end
    end

    local function DisableNoclip()
        for part, original in pairs(NoclipOriginal) do
            if part and part.Parent then
                part.CanCollide = original
            end
        end
        NoclipOriginal = {}
    end

    local function ApplyNoclip()
        State.NoclipEnabled = Options.NoclipToggle.Value
        if State.NoclipEnabled then
            EnableNoclip()
        else
            DisableNoclip()
        end
    end
    NoclipToggle:OnChanged(ApplyNoclip)
    ApplyFunctions.NoclipToggle = ApplyNoclip

    local InfJumpToggle = Tabs.Home:AddToggle("InfJumpToggle", {
        Title   = "Infinite Jump",
        Default = false
    })
    local function ApplyInfJump()
        State.InfJumpEnabled = Options.InfJumpToggle.Value
    end
    InfJumpToggle:OnChanged(ApplyInfJump)
    ApplyFunctions.InfJumpToggle = ApplyInfJump

    UserInputService.JumpRequest:Connect(function()
        if State.InfJumpEnabled and Humanoid then
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

--------------------------------------------------
-- TAB 2: PLANT SEEDS
--------------------------------------------------

do
    -- Teleport section
    Tabs.PlantSeeds:AddParagraph({ Title = "Teleport", Content = "Control teleportation behaviour while planting." })

    local PlantDisableTpToggle = Tabs.PlantSeeds:AddToggle("PlantDisableTp", {
        Title   = "Disable Teleport",
        Default = false
    })
    PlantDisableTpToggle:OnChanged(function()
        State.PlantDisableTp = Options.PlantDisableTp.Value
    end)

    -- Seed selection section
    Tabs.PlantSeeds:AddParagraph({ Title = "Select", Content = "Choose which seeds to plant." })

    local SeedDropdown = Tabs.PlantSeeds:AddDropdown("SeedSelect", {
        Title  = "Select Seeds",
        Values = { "Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn", "Daffodil", "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut", "Cacao", "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper", "Cactus", "Beanstalk" },
        Multi  = true,
        Default = {}
    })

    -- Position section
    Tabs.PlantSeeds:AddParagraph({ Title = "Position", Content = "Set where seeds will be planted." })

    local PositionDropdown = Tabs.PlantSeeds:AddDropdown("PlantPosition", {
        Title   = "Select Position",
        Values  = { "Saved Position", "Random", "Player Position" },
        Multi   = false,
        Default = 3
    })

    Tabs.PlantSeeds:AddButton({
        Title   = "Save Position",
        Desc    = "Saves your current HumanoidRootPart position",
        Callback = function()
            if HRP then
                SavedPosition = HRP.CFrame
                Fluent:Notify({ Title = "Position Saved", Content = tostring(HRP.Position), Duration = 3 })
            end
        end
    })

    -- Planting section
    Tabs.PlantSeeds:AddParagraph({ Title = "Planting", Content = "Configure and start auto planting." })

    local PlantIntervalInput = Tabs.PlantSeeds:AddInput("PlantInterval", {
        Title       = "Planting Interval (seconds)",
        Default     = "1",
        Placeholder = "Enter interval...",
        Numeric     = true,
        Callback    = function(Value)
            State.PlantInterval = tonumber(Value) or 1
        end
    })

    local AutoPlantToggle = Tabs.PlantSeeds:AddToggle("AutoPlant", {
        Title   = "Auto Plant Seed",
        Default = false
    })
    AutoPlantToggle:OnChanged(function()
        State.AutoPlant = Options.AutoPlant.Value
    end)

    local AutoPlantAllToggle = Tabs.PlantSeeds:AddToggle("AutoPlantAll", {
        Title   = "Auto Plant All",
        Default = false
    })
    AutoPlantAllToggle:OnChanged(function()
        State.AutoPlantAll = Options.AutoPlantAll.Value
    end)

    -- Auto Plant loop
    task.spawn(function()
        while true do
            task.wait(math.max(0.1, State.PlantInterval))
            if not (State.AutoPlant or State.AutoPlantAll) then continue end

            local myPlot = FindMyPlot()
            if not myPlot then
                continue
            end

            -- Determine which seeds to plant
            local selectedSeeds = {}
            local seedOpts = Options.SeedSelect and Options.SeedSelect.Value or {}
            if State.AutoPlantAll then
                -- Plant everything in backpack
                local bp = LocalPlayer:FindFirstChild("Backpack")
                if bp then
                    for _, item in ipairs(bp:GetChildren()) do
                        -- Seeds in Assets.Seeds
                        local ok = pcall(function()
                            local _ = ReplicatedStorage.Assets.Seeds[item.Name]
                        end)
                        if ok then
                            selectedSeeds[item.Name] = true
                        end
                    end
                end
            else
                for name, _ in pairs(seedOpts) do
                    selectedSeeds[name] = true
                end
            end

            for seedName, _ in pairs(selectedSeeds) do
                local seeds = GetBackpackSeeds(seedName)
                if #seeds == 0 then continue end

                -- Determine plant position
                local plantPos
                local posMode = Options.PlantPosition and Options.PlantPosition.Value or "Player Position"
                if posMode == "Saved Position" and SavedPosition then
                    plantPos = SavedPosition.Position
                elseif posMode == "Random" then
                    plantPos = GetRandomPlotPosition(myPlot)
                else
                    plantPos = HRP and HRP.Position or nil
                end

                if not plantPos then continue end

                -- Teleport to plot center at player's current Y, not directly on the plant position
                if not State.PlantDisableTp and HRP then
                    local centerPos = GetPlotCenterAtPlayerY(myPlot)
                    if centerPos then
                        MovementSystem.RequestMove("Plant", CFrame.new(centerPos))
                    end
                end

                -- Fire plant event: opcode 5
                FireRemote(Op("PlantSeed"), plantPos, seedName, seeds[1])
            end
        end
    end)
end

--------------------------------------------------
-- TAB 3: COLLECT CROPS
--------------------------------------------------

do
    -- Teleport section
    Tabs.Collect:AddParagraph({ Title = "Teleport", Content = "Control teleportation behaviour while collecting." })

    local CollectDisableTpToggle = Tabs.Collect:AddToggle("CollectDisableTp", {
        Title   = "Disable Teleport",
        Default = false
    })
    CollectDisableTpToggle:OnChanged(function()
        State.CollectDisableTp = Options.CollectDisableTp.Value
    end)

    -- Backpack section
    Tabs.Collect:AddParagraph({ Title = "Backpack", Content = "Configure backpack-related behaviour." })

    local StopIfFullToggle = Tabs.Collect:AddToggle("StopIfFull", {
        Title   = "Stop if Backpack Full",
        Default = false
    })
    StopIfFullToggle:OnChanged(function()
        State.StopIfFull = Options.StopIfFull.Value
    end)

    -- Timing section
    Tabs.Collect:AddParagraph({ Title = "Timing", Content = "Set how often crops are collected." })

    local CollectIntervalInput = Tabs.Collect:AddInput("CollectInterval", {
        Title       = "Collect Interval (seconds)",
        Default     = "1",
        Placeholder = "Enter interval...",
        Numeric     = true,
        Callback    = function(Value)
            State.CollectInterval = tonumber(Value) or 1
        end
    })

    -- Select section
    Tabs.Collect:AddParagraph({ Title = "Select", Content = "Filter which crops, rarities are collected." })

    local CollectCropDropdown = Tabs.Collect:AddDropdown("CollectCrops", {
        Title  = "Select Crops",
        Values = { "All", "Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn", "Daffodil", "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut", "Cacao", "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper", "Cactus", "Beanstalk" },
        Multi  = true,
        Default = { "All" }
    })

    local CollectRarityDropdown = Tabs.Collect:AddDropdown("CollectRarity", {
        Title  = "Select Rarity",
        Values = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine" },
        Multi  = true,
        Default = { "All" }
    })

    -- Auto Collect section
    Tabs.Collect:AddParagraph({ Title = "Auto Collect", Content = "Enable automatic crop collection." })

    local AutoCollectToggle = Tabs.Collect:AddToggle("AutoCollect", {
        Title   = "Auto Collect Crops",
        Default = false
    })
    AutoCollectToggle:OnChanged(function()
        State.AutoCollect = Options.AutoCollect.Value
    end)

    local AutoCollectAllToggle = Tabs.Collect:AddToggle("AutoCollectAll", {
        Title   = "Auto Collect All Crops",
        Default = false
    })
    AutoCollectAllToggle:OnChanged(function()
        State.AutoCollectAll = Options.AutoCollectAll.Value
    end)

    -- Strips the "USERID_" prefix from plant/fruit instance names to get the bare UUID.
    -- e.g. "27120137_001fbc0e-101d-4cea-9342-ccdaa76a1000" -> "001fbc0e-101d-4cea-9342-ccdaa76a1000"
    local function StripPrefix(name)
        return name:match(".*_(.+)$") or name
    end



    -- Returns all fruits from own plot only.
    local function GetOwnPlotFruits()
        local fruits = {}
        local myPlot = FindMyPlot()
        if not myPlot then return fruits end
        local plantsFolder = myPlot:FindFirstChild("Plants")
        if not plantsFolder then return fruits end
        for _, plant in ipairs(plantsFolder:GetChildren()) do
            local fruitsFolder = plant:FindFirstChild("Fruits")
            if fruitsFolder then
                for _, fruit in ipairs(fruitsFolder:GetChildren()) do
                    table.insert(fruits, { plant = plant, fruit = fruit })
                end
            end
        end
        return fruits
    end

    -- Auto Collect loop.
    -- AutoCollect = own plot + filters applied.
    -- AutoCollectAll = own plot + no filters (collect everything).
    task.spawn(function()
        while true do
            task.wait(math.max(0.1, State.CollectInterval))

            -- Read directly from Options (always live) so toggles respond instantly
            local doCollect    = Options.AutoCollect    and Options.AutoCollect.Value
            local doCollectAll = Options.AutoCollectAll and Options.AutoCollectAll.Value
            local stopIfFull   = Options.StopIfFull     and Options.StopIfFull.Value
            local disableTp    = Options.CollectDisableTp and Options.CollectDisableTp.Value

            if not (doCollect or doCollectAll) then continue end

            if stopIfFull and IsInventoryFull() then
                -- Wait until an item is removed from inventory before continuing
                while IsInventoryFull() do
                    task.wait(0.1)
                    -- Still bail out if toggle was turned off while waiting
                    local stillActive = (Options.AutoCollect and Options.AutoCollect.Value)
                        or (Options.AutoCollectAll and Options.AutoCollectAll.Value)
                    if not stillActive then break end
                end
                continue
            end

            local fruitList = GetOwnPlotFruits()

            local useFilters = doCollect and not doCollectAll
            local rawCrops   = useFilters and Options.CollectCrops  and Options.CollectCrops.Value  or {}
            local rawRarity  = useFilters and Options.CollectRarity and Options.CollectRarity.Value or {}
            local allCrops   = not useFilters or rawCrops["All"]  or next(rawCrops)  == nil
            local allRarity  = not useFilters or rawRarity["All"] or next(rawRarity) == nil

            for _, entry in ipairs(fruitList) do
                -- Re-check toggle on every fruit so turning off is instant
                local stillActive = (Options.AutoCollect and Options.AutoCollect.Value)
                    or (Options.AutoCollectAll and Options.AutoCollectAll.Value)
                if not stillActive then break end

                -- Re-check inventory full inside the loop too
                if stopIfFull and IsInventoryFull() then break end

                local plant = entry.plant
                local fruit = entry.fruit
                local attrs = fruit:GetAttributes()

                local fruitName = attrs.CorePartName or fruit.Name
                local rarity    = attrs.Rarity or "Common"

                if not allCrops  and not rawCrops[fruitName]  then continue end
                if not allRarity and not rawRarity[rarity]    then continue end

                if not disableTp and HRP then
                    local myPlotForTp = FindMyPlot()
                    local centerPos = myPlotForTp and GetPlotCenterAtPlayerY(myPlotForTp)
                    if centerPos then
                        MovementSystem.RequestMove("Collect", CFrame.new(centerPos))
                    end
                end

                local plantId = StripPrefix(plant.Name)
                local fruitId = StripPrefix(fruit.Name)
                FireRemote(Op("CollectFruit"), plantId, fruitId)
                task.wait(0.05)
            end
        end
    end)
end

--------------------------------------------------
-- TAB 4: SELL CROPS
--------------------------------------------------

do
    -- Conditions section
    Tabs.Sell:AddParagraph({ Title = "Conditions", Content = "Set conditions for when crops are sold." })

    local OnlySellIfFullToggle = Tabs.Sell:AddToggle("OnlySellIfFull", {
        Title   = "Only Sell if Backpack Full",
        Default = false
    })
    OnlySellIfFullToggle:OnChanged(function()
        State.OnlySellIfFull = Options.OnlySellIfFull.Value
    end)

    -- Auto Sell section
    Tabs.Sell:AddParagraph({ Title = "Auto Sell", Content = "Enable automatic selling." })

    local AutoSellToggle = Tabs.Sell:AddToggle("AutoSell", {
        Title   = "Auto Sell",
        Default = false
    })
    AutoSellToggle:OnChanged(function()
        State.AutoSell = Options.AutoSell.Value
    end)

    -- Sell helper: fires opcode 169.
    -- "Only Sell if Backpack Full" uses the same InventoryFull flag from the collect tab.
    -- When OnlySellIfFull is enabled, a 10-second cooldown applies after each sell:
    --   sell once → wait 10 s → wait for next full notification → sell again → repeat.
    local SellCooldownUntil = 0  -- tick() timestamp after which selling is allowed again

    local function DoSellAll()
        if Options.OnlySellIfFull and Options.OnlySellIfFull.Value then
            if not InventoryFull then return end
            if tick() < SellCooldownUntil then return end
            -- Sell, reset the full flag, and arm the cooldown
            InventoryFull = false
            FireRemote(Op("SellAll"), 59)
            Fluent:Notify({ Title = "Sell", Content = "Sold all crops.", Duration = 2 })
            SellCooldownUntil = tick() + 10
        else
            FireRemote(Op("SellAll"), 59)
            Fluent:Notify({ Title = "Sell", Content = "Sold all crops.", Duration = 2 })
        end
    end

    Tabs.Sell:AddButton({
        Title    = "Sell Once",
        Desc     = "Immediately sells all eligible crops once",
        Callback = function()
            DoSellAll()
        end
    })

    -- Auto Sell loop
    task.spawn(function()
        while true do
            task.wait(0.5)
            if not (Options.AutoSell and Options.AutoSell.Value) then continue end
            DoSellAll()
        end
    end)
end

--------------------------------------------------
-- TAB 5: BUY ITEMS
--------------------------------------------------

do
    -- ------------------------------------------------
    -- Seed Shop
    -- ------------------------------------------------
    Tabs.Buy:AddParagraph({ Title = "Seed Shop", Content = "Automatically purchase seeds from the shop." })

    -- Populate dropdown with live StockValues list; fall back to hardcoded list if not yet loaded.
    local seedShopList = GetSeedShopList()
    if #seedShopList == 0 then
        seedShopList = { "Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn",
                         "Daffodil", "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut",
                         "Cacao", "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper",
                         "Cactus", "Beanstalk" }
    end
    table.insert(seedShopList, 1, "All")

    local BuySeedDropdown = Tabs.Buy:AddDropdown("BuySeeds", {
        Title   = "Select Seeds",
        Values  = seedShopList,
        Multi   = true,
        Default = { "All" }
    })

    local AutoBuySeedsToggle = Tabs.Buy:AddToggle("AutoBuySeeds", {
        Title   = "Auto Buy Seeds",
        Default = false
    })
    AutoBuySeedsToggle:OnChanged(function()
        State.AutoBuySeeds = Options.AutoBuySeeds.Value
    end)

    -- Auto Buy Seeds loop: opcode 106, seed name
    task.spawn(function()
        while true do
            task.wait(1)
            if not State.AutoBuySeeds then continue end

            local selected = Options.BuySeeds and Options.BuySeeds.Value or {}
            local toBuy = {}

            if selected["All"] then
                -- buy every seed in StockValues
                local live = GetSeedShopList()
                for _, name in ipairs(live) do table.insert(toBuy, name) end
            else
                for name, _ in pairs(selected) do table.insert(toBuy, name) end
            end

            for _, seedName in ipairs(toBuy) do
                FireRemote(Op("PurchaseSeed"), seedName)
                task.wait(0.15)
            end
        end
    end)

    -- ------------------------------------------------
    -- Gear Shop
    -- ------------------------------------------------
    Tabs.Buy:AddParagraph({ Title = "Gear Shop", Content = "Automatically purchase gear from the shop." })

    local gearShopList = GetGearShopList()
    if #gearShopList == 0 then
        gearShopList = { "Watering Can", "Trowel", "Advanced Sprinkler", "Master Sprinkler",
                         "Recall Wrench", "Favorite Tool", "Basic Pot", "Supersize Mushroom" }
    end
    table.insert(gearShopList, 1, "All")

    local BuyGearDropdown = Tabs.Buy:AddDropdown("BuyGear", {
        Title   = "Select Gear",
        Values  = gearShopList,
        Multi   = true,
        Default = { "All" }
    })

    local AutoBuyGearToggle = Tabs.Buy:AddToggle("AutoBuyGear", {
        Title   = "Auto Buy Gear",
        Default = false
    })
    AutoBuyGearToggle:OnChanged(function()
        State.AutoBuyGear = Options.AutoBuyGear.Value
    end)

    -- Auto Buy Gear loop: opcode 110, gear name
    task.spawn(function()
        while true do
            task.wait(1)
            if not State.AutoBuyGear then continue end

            local selected = Options.BuyGear and Options.BuyGear.Value or {}
            local toBuy = {}

            if selected["All"] then
                local live = GetGearShopList()
                for _, name in ipairs(live) do table.insert(toBuy, name) end
            else
                for name, _ in pairs(selected) do table.insert(toBuy, name) end
            end

            for _, gearName in ipairs(toBuy) do
                FireRemote(Op("PurchaseGear"), gearName)
                task.wait(0.15)
            end
        end
    end)

    -- ------------------------------------------------
    -- Crate Shop
    -- ------------------------------------------------
    Tabs.Buy:AddParagraph({ Title = "Crate Shop", Content = "Automatically purchase crates from the shop." })

    local crateShopList = GetCrateShopList()
    if #crateShopList == 0 then
        crateShopList = { "Basic Crate", "Rare Crate", "Epic Crate", "Legendary Crate",
                          "Ladder Crate", "Arch Crate" }
    end
    table.insert(crateShopList, 1, "All")

    local BuyCrateDropdown = Tabs.Buy:AddDropdown("BuyCrates", {
        Title   = "Select Crates",
        Values  = crateShopList,
        Multi   = true,
        Default = { "All" }
    })

    local AutoBuyCratesToggle = Tabs.Buy:AddToggle("AutoBuyCrates", {
        Title   = "Auto Buy Crates",
        Default = false
    })
    AutoBuyCratesToggle:OnChanged(function()
        State.AutoBuyCrates = Options.AutoBuyCrates.Value
    end)

    -- Auto Buy Crates loop: opcode 108, crate name
    task.spawn(function()
        while true do
            task.wait(1)
            if not State.AutoBuyCrates then continue end

            local selected = Options.BuyCrates and Options.BuyCrates.Value or {}
            local toBuy = {}

            if selected["All"] then
                local live = GetCrateShopList()
                for _, name in ipairs(live) do table.insert(toBuy, name) end
            else
                for name, _ in pairs(selected) do table.insert(toBuy, name) end
            end

            for _, crateName in ipairs(toBuy) do
                FireRemote(Op("PurchaseCrate"), crateName)
                task.wait(0.15)
            end
        end
    end)

    -- ------------------------------------------------
    -- Wild Pets
    -- ------------------------------------------------
    Tabs.Buy:AddParagraph({ Title = "Wild Pets", Content = "Automatically purchase pets from the wild pets area." })

    local petAssetList = GetPetAssetList()
    if #petAssetList == 0 then
        petAssetList = { "Bee", "Butterfly", "Ladybug", "Caterpillar", "Snail", "Dragonfly" }
    end
    table.insert(petAssetList, 1, "All")

    local BuyPetDropdown = Tabs.Buy:AddDropdown("BuyPets", {
        Title   = "Select Pets",
        Values  = petAssetList,
        Multi   = true,
        Default = { "All" }
    })

    local AutoBuyPetsToggle = Tabs.Buy:AddToggle("AutoBuyPets", {
        Title   = "Auto Buy Pets",
        Default = false
    })
    AutoBuyPetsToggle:OnChanged(function()
        State.AutoBuyPets = Options.AutoBuyPets.Value
    end)

    -- Returns the world position of a WildPet model using the same
    -- pcall-safe adornee logic as the Pet ESP.
    local function GetPetPosition(petModel)
        local ok, pp = pcall(function() return petModel.PrimaryPart end)
        if ok and pp then return pp.Position end
        for _, child in ipairs(petModel:GetChildren()) do
            if child:IsA("BasePart") then return child.Position end
        end
        if petModel:IsA("BasePart") then return petModel.Position end
        return nil
    end

    -- Auto Buy Pets loop
    -- Scans WildPetRef, picks one pet at a time, tracks its live position until
    -- close enough (or tween finishes), fires the tame remote, then waits 5 seconds
    -- before moving to the next pet. In tween mode we re-sample the pet's position
    -- every heartbeat so we always aim at where it actually is, not a stale snapshot.
    local PET_CLOSE_ENOUGH = 2   -- studs — within this distance we fire the remote
    local PET_WAIT         = 3   -- seconds between pet attempts

    task.spawn(function()
        while true do
            task.wait(0.2)
            if not State.AutoBuyPets then continue end

            local selectedPets = Options.BuyPets and Options.BuyPets.Value or { All = true }

            local wildPets = GetWildPets()
            local target = nil

            -- Pick the first eligible pet
            for _, petModel in ipairs(wildPets) do
                local speciesAttr = petModel:GetAttribute("PetType")
                    or petModel:GetAttribute("PetName")
                    or petModel:GetAttribute("Name")
                    or ""
                if speciesAttr == "" then
                    for _, child in ipairs(petModel:GetChildren()) do
                        local ok = pcall(function()
                            local _ = ReplicatedStorage.Assets.Pets[child.Name]
                        end)
                        if ok then speciesAttr = child.Name break end
                    end
                end
                if not selectedPets["All"] and not selectedPets[speciesAttr] then continue end
                target = petModel
                break
            end

            if not target or not HRP then continue end

            if MovementSystem.TweenMode then
                -- Tween mode: track the pet live until we're close enough, then fire.
                -- Re-aim every heartbeat so the tween always points at the current position.
                local arrived = false
                local conn
                conn = RunService.Heartbeat:Connect(function()
                    if not State.AutoBuyPets or not target or not target.Parent or not HRP then
                        conn:Disconnect()
                        arrived = true
                        return
                    end
                    local petPos = GetPetPosition(target)
                    if not petPos then
                        conn:Disconnect()
                        arrived = true
                        return
                    end
                    local dist = (HRP.Position - petPos).Magnitude
                    if dist <= PET_CLOSE_ENOUGH then
                        conn:Disconnect()
                        arrived = true
                        return
                    end
                    -- Re-aim the tween at live position (clears old queue entry, starts fresh)
                    -- We call directly into ExecuteTween to avoid stacking queue entries.
                    if not MovementSystem._tweenActive then
                        MovementSystem._tweenActive = true
                        local startCF = HRP.CFrame
                        local endCF   = CFrame.new(petPos)
                        local dist2   = (endCF.Position - startCF.Position).Magnitude
                        local speed   = math.max(1, MovementSystem.TweenSpeed)
                        local dur     = dist2 / speed
                        local elapsed = 0
                        local inner
                        inner = RunService.Heartbeat:Connect(function(dt)
                            if not HRP then
                                inner:Disconnect()
                                MovementSystem._tweenActive = false
                                return
                            end
                            -- Re-check closeness during the tween itself
                            local livePos = GetPetPosition(target)
                            if livePos and (HRP.Position - livePos).Magnitude <= PET_CLOSE_ENOUGH then
                                inner:Disconnect()
                                MovementSystem._tweenActive = false
                                return
                            end
                            elapsed = elapsed + dt
                            local t = math.clamp(elapsed / math.max(dur, 0.001), 0, 1)
                            HRP.CFrame = startCF:Lerp(endCF, t)
                            if t >= 1 then
                                inner:Disconnect()
                                MovementSystem._tweenActive = false
                            end
                        end)
                    end
                end)

                -- Wait until arrived or pet disappears (max 10 seconds)
                local waited = 0
                while not arrived and waited < 10 do
                    task.wait(0.1)
                    waited = waited + 0.1
                    if not target.Parent then break end
                end
                conn:Disconnect()
                -- Clean up any running tween
                MovementSystem._tweenActive = false

            else
                -- Teleport mode: snap directly onto the pet
                local petPos = GetPetPosition(target)
                if petPos and HRP then
                    HRP.CFrame = CFrame.new(petPos)
                    task.wait(0.05)
                end
            end

            -- Fire tame remote
            if target and target.Parent then
                FireRemote(Op("WildPetTame"), target)
            end

            -- Wait 5 seconds before attempting the next pet
            task.wait(PET_WAIT)
        end
    end)
end

--------------------------------------------------
-- TAB 6: SPECIAL EVENTS
--------------------------------------------------

do
    -- Night Event
    Tabs.Events:AddParagraph({ Title = "Night Event", Content = "Auto farm crops from other players' plots during the night event." })

    local NightMinValueInput = Tabs.Events:AddInput("NightMinValue", {
        Title       = "Minimum Value",
        Default     = "0",
        Placeholder = "Enter minimum crop value...",
        Numeric     = true,
        Callback    = function(Value)
            State.NightMinValue = tonumber(Value) or 0
        end
    })

    local NightCropDropdown = Tabs.Events:AddDropdown("NightCrops", {
        Title  = "Select Crops",
        Values = { "All", "Moonflower", "Nightshade", "Eclipse Fruit", "Starfruit", "Dusk Berry" },
        Multi  = true,
        Default = { "All" }
    })

    local AutoFarmCropsToggle = Tabs.Events:AddToggle("AutoFarmCrops", {
        Title   = "Auto Farm Crops",
        Default = false
    })
    AutoFarmCropsToggle:OnChanged(function()
        State.AutoFarmCrops = Options.AutoFarmCrops.Value
    end)

    local AutoFarmHighestToggle = Tabs.Events:AddToggle("AutoFarmHighest", {
        Title   = "Auto Farm Highest Value Crops",
        Default = false
    })
    AutoFarmHighestToggle:OnChanged(function()
        State.AutoFarmHighest = Options.AutoFarmHighest.Value
    end)

    --------------------------------------------------
    -- NIGHT EVENT HELPERS
    --------------------------------------------------

    local Lighting = game:GetService("Lighting")

    local function IsNight()
        local t = Lighting.ClockTime
        return t < 6 or t >= 18
    end

    -- Plots blacklisted for this night because the owner was detected in their garden.
    -- Cleared when a new night begins (ClockTime crosses the 18:00 threshold).
    local NightBlacklist = {}       -- plot instance → true
    local LastNightState = IsNight()

    -- Called by the steal loop to clear the blacklist at the start of each new night.
    local function RefreshNightBlacklist()
        local currently = IsNight()
        if currently and not LastNightState then
            -- Transitioned from day → night: fresh night, clear blacklist
            NightBlacklist = {}
        end
        LastNightState = currently
    end

    -- Extract the owner UserId from a fruit's raw instance name.
    -- Format: "USERID_PLANTUUID_FRUITUUID" → returns "USERID" as a number.
    local function GetPlotOwnerIdFromFruit(fruit)
        local raw = fruit.Name
        local userId = raw:match("^(%d+)_")
        return userId and tonumber(userId) or nil
    end

    -- Strip the leading USERID_ prefix from a plant or fruit name for the remote call.
    -- Fruit format: USERID_PLANTUUID_FRUITUUID  → we want just the last UUID (fruitId)
    -- Plant format: USERID_PLANTUUID             → we want just PLANTUUID
    -- Mirrors StripPrefix() used in Collect Crops but handles the double-UUID fruit case.
    local function NightStripPlant(name)
        -- plant names: USERID_UUID  → return UUID
        return name:match("^%d+_(.+)$") or name
    end

    local function NightStripFruit(name)
        -- fruit names: USERID_PLANTUUID_FRUITUUID  → return FRUITUUID (last segment)
        return name:match("_([^_]+)$") or name
    end

    -- Returns the world position of a fruit's parent part for teleporting.
    local function GetFruitPosition(fruit)
        local ok, pp = pcall(function() return fruit.PrimaryPart end)
        if ok and pp then return pp.Position end
        for _, child in ipairs(fruit:GetChildren()) do
            if child:IsA("BasePart") then return child.Position end
        end
        if fruit:IsA("BasePart") then return fruit.Position end
        -- Fallback: use the plant's position
        local plant = fruit.Parent and fruit.Parent.Parent
        if plant and plant:IsA("BasePart") then return plant.Position end
        return nil
    end

    -- Spatial garden presence check.
    -- Returns true if the owner of `plot` is physically inside the plot's
    -- PlotSizeReferenceVisual bounding box (excludes LocalPlayer).
    local function IsPlotOwnerInsidePlot(plot)
        local visual = GetPlotVisual(plot)
        if not visual then return false end

        -- Build an axis-aligned bounding box from the visual's CFrame + Size.
        -- We only care about XZ containment (Y is ignored — players stand on ground).
        local cf   = visual.CFrame
        local sz   = visual.Size
        local halfX = sz.X / 2
        local halfZ = sz.Z / 2

        -- Determine which player owns this plot by matching the garden label.
        local ownerName = nil
        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("TextLabel") then
                local t = string.lower(desc.Text or "")
                local match = t:match("^(.+)'s garden$")
                if match then
                    ownerName = match
                    break
                end
            end
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end  -- exclude self

            -- Only check the plot owner (if we know who it is)
            if ownerName then
                if string.lower(player.DisplayName) ~= ownerName then continue end
            end

            local char = player.Character
            if not char then continue end
            local rootPart = char:FindFirstChild("HumanoidRootPart")
            if not rootPart then continue end

            -- Transform player position into the visual's local space, then check XZ extents.
            local localPos = cf:PointToObjectSpace(rootPart.Position)
            if math.abs(localPos.X) <= halfX and math.abs(localPos.Z) <= halfZ then
                return true
            end
        end
        return false
    end

    -- Gather all eligible other-player fruits for the night event.
    -- Returns a flat list sorted by value descending (for AutoFarmHighest)
    -- or filtered by crop name + min value (for AutoFarmCrops).
    -- Excludes: own plot, blacklisted plots, plots whose owner is currently inside.
    local function GatherNightCrops(highestOnly)
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return {} end
        local myPlot = FindMyPlot()

        local minVal     = State.NightMinValue or 0
        local cropFilter = Options.NightCrops and Options.NightCrops.Value or { All = true }
        local allCrops   = cropFilter["All"] or next(cropFilter) == nil

        local results = {}

        for _, plot in ipairs(gardens:GetChildren()) do
            if not (plot:IsA("Model") or plot:IsA("Folder")) then continue end
            if plot == myPlot then continue end                  -- skip own plot
            if NightBlacklist[plot] then continue end            -- skip blacklisted plots
            if IsPlotOwnerInsidePlot(plot) then continue end     -- skip occupied plots

            local plantsFolder = plot:FindFirstChild("Plants")
            if not plantsFolder then continue end

            for _, plant in ipairs(plantsFolder:GetChildren()) do
                local fruitsFolder = plant:FindFirstChild("Fruits")
                if not fruitsFolder then continue end

                for _, fruit in ipairs(fruitsFolder:GetChildren()) do
                    local attrs     = fruit:GetAttributes()
                    local fruitName = attrs.CorePartName or fruit.Name

                    -- Crop name filter (only for AutoFarmCrops mode)
                    if not highestOnly then
                        if not allCrops and not cropFilter[fruitName] then continue end
                    end

                    -- Compute estimated value from fruit attributes.
                    local sizeMulti = attrs.SizeMulti or attrs.SizeMultiplier or 1
                    local attrVal   = attrs.Value or attrs.SellPrice or attrs.Price or 0
                    local estVal    = (attrVal > 0) and (attrVal * sizeMulti) or sizeMulti

                    -- Minimum value filter
                    if estVal < minVal then continue end

                    table.insert(results, {
                        plot      = plot,
                        plant     = plant,
                        fruit     = fruit,
                        value     = estVal,
                        fruitName = fruitName,
                    })
                end
            end
        end

        -- Sort highest value first
        table.sort(results, function(a, b) return a.value > b.value end)
        return results
    end

    -- Return to local player's plot center (bottom-Y of PlotSizeReferenceVisual, XZ center).
    -- Called while _nightStealLocked is true, so bypasses RequestMove entirely.
    local function ReturnToOwnPlot()
        local myPlot = FindMyPlot()
        if not myPlot or not HRP then return end
        local visual = GetPlotVisual(myPlot)
        if not visual then return end
        local cf   = visual.CFrame
        local sz   = visual.Size
        local dest = Vector3.new(cf.Position.X, cf.Position.Y - sz.Y / 2, cf.Position.Z)
        if MovementSystem.TweenMode then
            local done = false
            ExecuteTween(CFrame.new(dest), function() done = true end)
            while not done do task.wait() end
        else
            HRP.CFrame = CFrame.new(dest)
            task.wait(0.05)
        end
    end

    -- Tween/teleport to the center (XZ) / bottom-Y of a target plot's PlotSizeReferenceVisual.
    -- Aborts immediately (stopping any in-progress tween) if night ends mid-travel.
    local function TweenToPlotCenter(plot)
        if not HRP then return end
        if not IsNight() then return end
        local visual = GetPlotVisual(plot)
        if not visual then return end
        local cf   = visual.CFrame
        local sz   = visual.Size
        local dest = Vector3.new(cf.Position.X, cf.Position.Y - sz.Y / 2, cf.Position.Z)
        if MovementSystem.TweenMode then
            local done = false
            ExecuteTween(CFrame.new(dest), function() done = true end)
            while not done do
                if not IsNight() then
                    MovementSystem._tweenActive = false
                    return
                end
                task.wait()
            end
        else
            if not IsNight() then return end
            HRP.CFrame = CFrame.new(dest)
            task.wait(0.05)
        end
    end

    -- Collect all crops in a specific plot that match the current filters,
    -- sorted by value descending.
    local function GetPlotCrops(plot, highestOnly)
        local minVal     = State.NightMinValue or 0
        local cropFilter = Options.NightCrops and Options.NightCrops.Value or { All = true }
        local allCrops   = cropFilter["All"] or next(cropFilter) == nil

        local results = {}
        local plantsFolder = plot:FindFirstChild("Plants")
        if not plantsFolder then return results end

        for _, plant in ipairs(plantsFolder:GetChildren()) do
            local fruitsFolder = plant:FindFirstChild("Fruits")
            if not fruitsFolder then continue end
            for _, fruit in ipairs(fruitsFolder:GetChildren()) do
                local attrs     = fruit:GetAttributes()
                local fruitName = attrs.CorePartName or fruit.Name

                if not highestOnly then
                    if not allCrops and not cropFilter[fruitName] then continue end
                end

                local sizeMulti = attrs.SizeMulti or attrs.SizeMultiplier or 1
                local attrVal   = attrs.Value or attrs.SellPrice or attrs.Price or 0
                local estVal    = (attrVal > 0) and (attrVal * sizeMulti) or sizeMulti

                if estVal < minVal then continue end

                table.insert(results, {
                    plot      = plot,
                    plant     = plant,
                    fruit     = fruit,
                    value     = estVal,
                    fruitName = fruitName,
                })
            end
        end

        table.sort(results, function(a, b) return a.value > b.value end)
        return results
    end

    -- Main night event loop
    task.spawn(function()
        while true do
            task.wait(0.5)

            local doFarm    = Options.AutoFarmCrops   and Options.AutoFarmCrops.Value
            local doHighest = Options.AutoFarmHighest and Options.AutoFarmHighest.Value
            if not (doFarm or doHighest) then continue end

            RefreshNightBlacklist()

            if not IsNight() then continue end

            local highestOnly = doHighest

            -- ── Step 1: Find the highest-value fruit across all eligible plots ──
            -- Eligible: not own plot, not blacklisted, owner not inside their plot.
            local allCrops = GatherNightCrops(highestOnly)
            if #allCrops == 0 then
                task.wait(1)
                continue
            end

            -- The list is already sorted highest-first. Pick the top entry's plot.
            local bestEntry = allCrops[1]
            local targetPlot = bestEntry.plot

            -- ── Step 2: Double-check the owner isn't inside (real-time) ──
            if IsPlotOwnerInsidePlot(targetPlot) then
                NightBlacklist[targetPlot] = true
                task.wait(0.2)
                continue
            end

            -- ── Step 3: Lock and tween to the plot center ──
            MovementSystem._nightStealLocked = true

            TweenToPlotCenter(targetPlot)

            -- If night ended during the tween, abort immediately
            if not IsNight() then
                MovementSystem._nightStealLocked = false
                continue
            end

            -- ── Step 4: Gather all crops in that plot matching filters ──
            local plotCrops = GetPlotCrops(targetPlot, highestOnly)

            -- ── Step 5 & 6: Steal top crops (up to 20 attempts) ──
            local stealCount = 0
            local nightEndedEarly = false
            for _, entry in ipairs(plotCrops) do
                if stealCount >= 20 then break end

                -- Re-check toggles and night state each iteration
                local still = (Options.AutoFarmCrops and Options.AutoFarmCrops.Value)
                           or (Options.AutoFarmHighest and Options.AutoFarmHighest.Value)
                if not still then break end
                if not IsNight() then
                    nightEndedEarly = true
                    break
                end

                -- Re-check spatially — abort if owner has entered during steals
                if IsPlotOwnerInsidePlot(targetPlot) then
                    NightBlacklist[targetPlot] = true
                    break
                end

                -- Validate fruit still exists
                if not entry.fruit or not entry.fruit.Parent then continue end

                local ownerId = GetPlotOwnerIdFromFruit(entry.fruit)
                local plantId = NightStripPlant(entry.plant.Name)
                local fruitId = NightStripFruit(entry.fruit.Name)

                -- Fire Start Steal then immediately Finish Steal (0s delay between them)
                FireRemote(Op("BeginSteal"), ownerId, plantId, fruitId)
                FireRemote(Op("CompleteSteal"))

                stealCount = stealCount + 1

                -- 0.1s between each crop
                task.wait(0.1)
            end

            -- ── Step 7: Return to own plot (skip entirely if night ended) ──
            if not nightEndedEarly and IsNight() then
                ReturnToOwnPlot()
                task.wait(0.2)
            end
            MovementSystem._nightStealLocked = false

            -- ── Step 8: Loop repeats from the top ──
        end
    end)

    -- Seed Event
    -- Only one seed farm event can run at a time (seeds are exclusive spawns).
    -- A dropdown selects which seed to chase; the three toggles below control
    -- Gold / Rainbow / Mega individually. Enabling any one disables the others.
    Tabs.Events:AddParagraph({
        Title   = "Collect Special Seeds",
        Content = "Auto-collect rare seeds that spawn on the map. Only one seed type can be farmed at a time since events are exclusive. Uses tween tracking (like Auto Buy Pets) so the player follows moving seeds when Tween mode is on."
    })

    -- ── Seed prompt cache (shared across all three seed types) ──────────────
    local _seedPromptCache     = {}
    local _seedPromptCacheConns = {}

    local function _invalidateSeedCache(seedName)
        if _seedPromptCache[seedName] then
            local conns = _seedPromptCacheConns[seedName]
            if conns then
                for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            end
            _seedPromptCache[seedName] = nil
            _seedPromptCacheConns[seedName] = nil
        end
    end

    -- Scans workspace for the nearest enabled ProximityPrompt whose ObjectText
    -- or ActionText contains seedName (case-insensitive). Caches the result and
    -- watches for removal so the next call rescans automatically.
    local function findSeedPrompt(seedName)
        local cached = _seedPromptCache[seedName]
        if cached and cached.prompt and cached.prompt.Parent and cached.prompt.Enabled then
            return cached.prompt, cached.part
        else
            _invalidateSeedCache(seedName)
        end

        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local lowerTarget = string.lower(seedName)
        local nearest, nearestPart, minDist = nil, nil, math.huge

        local function scanRoot(inst)
            for _, desc in ipairs(inst:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled then
                    local obj = string.lower(desc.ObjectText or "")
                    local act = string.lower(desc.ActionText or "")
                    if string.find(obj, lowerTarget, 1, true) or string.find(act, lowerTarget, 1, true) then
                        local part = desc.Parent
                        if part and part:IsA("BasePart") then
                            local dist = root and (root.Position - part.Position).Magnitude or 0
                            if dist < minDist then
                                minDist = dist
                                nearest = desc
                                nearestPart = part
                            end
                        end
                    end
                end
            end
        end

        local mapNode = workspace:FindFirstChild("Map")
        if mapNode then scanRoot(mapNode) end
        if not nearest then scanRoot(workspace) end

        if nearest then
            _seedPromptCache[seedName] = { prompt = nearest, part = nearestPart }
            local conns = {}
            table.insert(conns, nearest.AncestryChanged:Connect(function()
                if not nearest.Parent then _invalidateSeedCache(seedName) end
            end))
            table.insert(conns, nearest:GetPropertyChangedSignal("Enabled"):Connect(function()
                if not nearest.Enabled then _invalidateSeedCache(seedName) end
            end))
            _seedPromptCacheConns[seedName] = conns
        end

        return nearest, nearestPart
    end

    -- Returns the world position of a seed prompt's parent part.
    local function getSeedPosition(seedName)
        local prompt, part = findSeedPrompt(seedName)
        if not prompt or not part then return nil end
        return part.Position, prompt, part
    end

    -- ── Core grab function — mirrors pet tween logic ─────────────────────────
    -- In tween mode: tracks the seed's live position every Heartbeat (seeds can
    -- be carried/move). Fires fireproximityprompt once close enough or arrives.
    -- In teleport mode: snaps directly to the seed and fires.
    local SEED_CLOSE_ENOUGH = 3   -- studs

    local function grabSeedWithMovement(seedName)
        local char = LocalPlayer.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        local prompt, part = findSeedPrompt(seedName)
        if not prompt or not prompt.Enabled or not part then return false end

        if MovementSystem.TweenMode then
            -- Track the seed live (same pattern as Auto Buy Pets)
            local arrived = false
            local fired   = false
            local conn
            conn = RunService.Heartbeat:Connect(function()
                -- Bail if toggle turned off or seed vanished
                if not State.ActiveSeedFarm or not prompt or not prompt.Parent or not prompt.Enabled then
                    conn:Disconnect()
                    arrived = true
                    return
                end
                if not hrp then
                    conn:Disconnect()
                    arrived = true
                    return
                end

                local seedPos = part and part.Parent and part.Position
                if not seedPos then
                    conn:Disconnect()
                    arrived = true
                    return
                end

                local dist = (hrp.Position - seedPos).Magnitude
                if dist <= SEED_CLOSE_ENOUGH then
                    conn:Disconnect()
                    arrived = true
                    return
                end

                -- Re-aim tween at live seed position (matches pet logic)
                if not MovementSystem._tweenActive then
                    MovementSystem._tweenActive = true
                    local startCF = hrp.CFrame
                    local endCF   = CFrame.new(seedPos + Vector3.new(0, 2, 0))
                    local dist2   = (endCF.Position - startCF.Position).Magnitude
                    local speed   = math.max(1, MovementSystem.TweenSpeed)
                    local dur     = dist2 / speed
                    local elapsed = 0
                    local inner
                    inner = RunService.Heartbeat:Connect(function(dt)
                        if not hrp then
                            inner:Disconnect()
                            MovementSystem._tweenActive = false
                            return
                        end
                        local livePos = part and part.Parent and part.Position
                        if livePos and (hrp.Position - livePos).Magnitude <= SEED_CLOSE_ENOUGH then
                            inner:Disconnect()
                            MovementSystem._tweenActive = false
                            return
                        end
                        elapsed = elapsed + dt
                        local t = math.clamp(elapsed / math.max(dur, 0.001), 0, 1)
                        hrp.CFrame = startCF:Lerp(endCF, t)
                        if t >= 1 then
                            inner:Disconnect()
                            MovementSystem._tweenActive = false
                        end
                    end)
                end
            end)

            -- Wait until arrived or seed disappears (max 15 seconds)
            local waited = 0
            while not arrived and waited < 15 do
                task.wait(0.1)
                waited = waited + 0.1
                if not part.Parent then break end
            end
            conn:Disconnect()
            MovementSystem._tweenActive = false

        else
            -- Teleport mode: snap to seed
            hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
            task.wait(0.1)
            -- Re-fetch after teleport in case cache changed
            prompt, part = findSeedPrompt(seedName)
            if not prompt or not prompt.Enabled then return false end
        end

        -- Fire the prompt (hold until it completes or times out)
        prompt, part = findSeedPrompt(seedName)
        if not prompt or not prompt.Enabled then return false end

        fireproximityprompt(prompt)

        local holdTime = prompt.HoldDuration or 1
        local elapsed  = 0
        local maxWait  = holdTime + 2
        while elapsed < maxWait do
            task.wait(0.05)
            elapsed = elapsed + 0.05
            if hrp and part and part.Parent then
                hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
            end
            if not prompt.Parent or not prompt.Enabled then
                return true
            end
        end

        return false
    end

    -- ── Mutual-exclusion helper ──────────────────────────────────────────────
    -- Turning on any one of the three seed toggles disables the other two.
    local function setActiveSeed(seedKey, seedName, optGold, optRainbow, optMega)
        if seedKey then
            -- Disable the other two toggles in UI + state
            if optGold    and seedKey ~= "AutoGoldSeed"    then
                Options.AutoGoldSeed.Value    = false
                State.AutoGoldSeed    = false
            end
            if optRainbow and seedKey ~= "AutoRainbowSeed" then
                Options.AutoRainbowSeed.Value = false
                State.AutoRainbowSeed = false
            end
            if optMega    and seedKey ~= "AutoMegaSeed"    then
                Options.AutoMegaSeed.Value    = false
                State.AutoMegaSeed    = false
            end
            State.ActiveSeedFarm = seedName
        else
            State.ActiveSeedFarm = nil
        end
    end

    -- ── UI ───────────────────────────────────────────────────────────────────
    local AutoGoldSeedToggle = Tabs.Events:AddToggle("AutoGoldSeed", {
        Title   = "Auto Collect Gold Seed",
        Desc    = "Teleports to and collects Gold Seeds when they spawn",
        Default = false
    })

    local AutoRainbowSeedToggle = Tabs.Events:AddToggle("AutoRainbowSeed", {
        Title   = "Auto Collect Rainbow Seed",
        Desc    = "Teleports to and collects Rainbow Seeds when they spawn",
        Default = false
    })

    local AutoMegaSeedToggle = Tabs.Events:AddToggle("AutoMegaSeed", {
        Title   = "Auto Collect Mega Seed",
        Desc    = "Teleports to and collects Mega Seeds when they spawn",
        Default = false
    })

    AutoGoldSeedToggle:OnChanged(function()
        State.AutoGoldSeed = Options.AutoGoldSeed.Value
        setActiveSeed(
            State.AutoGoldSeed and "AutoGoldSeed" or nil,
            State.AutoGoldSeed and "Gold Seed"    or nil,
            Options.AutoGoldSeed, Options.AutoRainbowSeed, Options.AutoMegaSeed
        )
    end)

    AutoRainbowSeedToggle:OnChanged(function()
        State.AutoRainbowSeed = Options.AutoRainbowSeed.Value
        setActiveSeed(
            State.AutoRainbowSeed and "AutoRainbowSeed" or nil,
            State.AutoRainbowSeed and "Rainbow Seed"    or nil,
            Options.AutoGoldSeed, Options.AutoRainbowSeed, Options.AutoMegaSeed
        )
    end)

    AutoMegaSeedToggle:OnChanged(function()
        State.AutoMegaSeed = Options.AutoMegaSeed.Value
        setActiveSeed(
            State.AutoMegaSeed and "AutoMegaSeed" or nil,
            State.AutoMegaSeed and "Mega Seed"    or nil,
            Options.AutoGoldSeed, Options.AutoRainbowSeed, Options.AutoMegaSeed
        )
    end)

    -- ── Main seed farm loop ──────────────────────────────────────────────────
    task.spawn(function()
        while true do
            task.wait(0.2)

            local activeSeed = State.ActiveSeedFarm
            if not activeSeed then continue end

            local grabbed = grabSeedWithMovement(activeSeed)
            if grabbed then
                task.wait(0.5)
            else
                -- No seed visible; back off before rescanning to reduce lag
                task.wait(2)
            end
        end
    end)
end

--------------------------------------------------
-- TAB 7: ESP
--------------------------------------------------

do
    ----------------------------------------------------
    -- SHARED: BASE PRICE + MUTATION LOOKUP
    -- Used by both the scanner and Crop ESP label values.
    ----------------------------------------------------

    local basePriceCache = nil
    local function getBasePriceTable()
        if basePriceCache then return basePriceCache end
        local candidateNames = { "fruit", "price", "value", "data", "config", "crop", "plant", "item", "shop", "sell" }
        local checkNames     = { "Strawberry", "Carrot", "Tomato", "Apple", "Blueberry" }

        local function scan(root, depth)
            if depth > 6 then return nil end
            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ModuleScript") then
                    local lowerName = string.lower(child.Name)
                    for _, kw in ipairs(candidateNames) do
                        if string.find(lowerName, kw) then
                            local ok, data = pcall(require, child)
                            if ok and type(data) == "table" then
                                for _, name in ipairs(checkNames) do
                                    if data[name] ~= nil then return data end
                                end
                            end
                            break
                        end
                    end
                end
                local result = scan(child, depth + 1)
                if result then return result end
            end
            return nil
        end

        local tbl = scan(ReplicatedStorage, 0)
        basePriceCache = tbl or {}
        return basePriceCache
    end

    local function getBasePrice(fruitName)
        local priceTable = getBasePriceTable()
        local data = priceTable[fruitName]
        if not data then return 0 end
        if type(data) == "number" then return data end
        if type(data) == "table" then
            return data.Price or data.Value or data.BasePrice or data.SellPrice or 0
        end
        return 0
    end

    local mutationModuleCache = {}
    local function findMutationModule(name)
        for _, obj in ipairs(SharedModules:GetDescendants()) do
            if obj:IsA("ModuleScript") and obj.Name:lower():find(name:lower(), 1, true) then
                return obj
            end
        end
        return nil
    end

    local function safeRequireMutation(name)
        if mutationModuleCache[name] ~= nil then return mutationModuleCache[name] end
        local module = findMutationModule(name)
        if not module then
            mutationModuleCache[name] = false
            return nil
        end
        local ok, result = pcall(require, module)
        if not ok then
            mutationModuleCache[name] = false
            return nil
        end
        mutationModuleCache[name] = result
        return result
    end

    local function getMutationMultiplier(mutationName)
        local data = safeRequireMutation(mutationName)
        if not data then return 1 end
        return data.PriceMultiplier or 1
    end

    local function getMutationList(attrs)
        local mutation = attrs.Mutation or attrs.MutationType or attrs.Mutations
        if type(mutation) == "table" then return mutation end
        if type(mutation) == "string" and mutation ~= "" then
            local list = {}
            for piece in string.gmatch(mutation, "[^,]+") do
                table.insert(list, piece)
            end
            return list
        end
        return {}
    end

    local function getCombinedMutationMultiplier(mutationList)
        local combined = 1
        for _, name in ipairs(mutationList) do
            combined = combined * getMutationMultiplier(name)
        end
        return combined
    end

    -- Compute the final value of a fruit from its attributes
    local function getFruitValue(attrs, fruitName)
        local sizeMulti = attrs.SizeMulti or attrs.SizeMultiplier or 1
        local mutationList = getMutationList(attrs)
        local mutMult = getCombinedMutationMultiplier(mutationList)
        local base = getBasePrice(fruitName)
        return sizeMulti * base * mutMult, sizeMulti, mutationList, base
    end

    ----------------------------------------------------
    -- SHARED: ALL-PLOTS FRUIT ITERATOR
    -- Yields { plot, plant, fruit, isOwn } for every fruit
    -- across every plot. isOwn = true if the plot belongs
    -- to the local player.
    ----------------------------------------------------

    local function getAllPlotFruits()
        local results = {}
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return results end
        local myPlot = FindMyPlot()
        for _, plot in ipairs(gardens:GetChildren()) do
            if not (plot:IsA("Model") or plot:IsA("Folder")) then continue end
            local isOwn = (plot == myPlot)
            local plantsFolder = plot:FindFirstChild("Plants")
            if not plantsFolder then continue end
            for _, plant in ipairs(plantsFolder:GetChildren()) do
                local fruitsFolder = plant:FindFirstChild("Fruits")
                if fruitsFolder then
                    for _, fruit in ipairs(fruitsFolder:GetChildren()) do
                        table.insert(results, {
                            plot  = plot,
                            plant = plant,
                            fruit = fruit,
                            isOwn = isOwn,
                        })
                    end
                end
            end
        end
        return results
    end

    ----------------------------------------------------
    -- PLOT SCANNER (prints to console)
    ----------------------------------------------------

    local function runPlotScanner(ownOnly)
        local allFruits = getAllPlotFruits()
        local myPlot    = FindMyPlot()

        if ownOnly then
        else
        end

        local grandTotal = 0
        local grandCount = 0
        local currentPlot = nil
        local plotTotal   = 0
        local plotCount   = 0

        for _, entry in ipairs(allFruits) do
            if ownOnly and not entry.isOwn then continue end
            if not ownOnly and entry.isOwn  then continue end

            -- Print plot header when plot changes (other-plots scan)
            if not ownOnly and entry.plot ~= currentPlot then
                if currentPlot then
                end
                currentPlot = entry.plot
                plotTotal   = 0
                plotCount   = 0
                -- Find owner label
                local labelText = "Unknown Garden"
                for _, desc in ipairs(entry.plot:GetDescendants()) do
                    if desc:IsA("TextLabel") then
                        local t = desc.Text or ""
                        if string.find(string.lower(t), "'s garden") then
                            labelText = t
                            break
                        end
                    end
                end
            end

            local attrs     = entry.fruit:GetAttributes()
            local fruitName = attrs.CorePartName or entry.fruit.Name
            local finalVal, sizeMulti, mutList, base = getFruitValue(attrs, fruitName)
            local mutText   = (#mutList > 0) and table.concat(mutList, ", ") or "None"

            grandTotal = grandTotal + finalVal
            grandCount = grandCount + 1
            plotTotal  = plotTotal  + finalVal
            plotCount  = plotCount  + 1

            local prefix = ownOnly and "" or "  "
        end

        -- Close last plot block for other-plots scan
        if not ownOnly and currentPlot then
        end

    end

    ----------------------------------------------------
    -- SCANNER UI
    ----------------------------------------------------

    ----------------------------------------------------
    -- CROP ESP
    -- BillboardGui above each fruit showing name, value,
    -- and mutations. Filtered by plot scope and min value.
    -- Labels refresh every 2 s so values stay current.
    ----------------------------------------------------

    local cropEspLabels = {} -- fruit instance → BillboardGui

    local function destroyCropEsp()
        for fruit, gui in pairs(cropEspLabels) do
            if gui and gui.Parent then gui:Destroy() end
        end
        cropEspLabels = {}
    end

    local function makeCropLabel(fruit, text)
        local gui = Instance.new("BillboardGui")
        gui.Name            = "VonHubCropESP"
        gui.Adornee         = fruit
        gui.Size            = UDim2.fromOffset(200, 50)
        gui.StudsOffset     = Vector3.new(0, 0, 0)
        gui.AlwaysOnTop     = true
        gui.ResetOnSpawn    = false
        gui.Parent          = fruit

        local label = Instance.new("TextLabel")
        label.Size                  = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3            = Color3.fromRGB(255, 255, 100)
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
        label.Font                  = Enum.Font.GothamBold
        label.TextSize              = 13
        label.TextWrapped           = true
        label.Text                  = text
        label.Parent                = gui

        return gui
    end

    local function updateCropEsp()
        -- Collect the current set of fruits that should be labelled
        local allFruits = getAllPlotFruits()

        local plotScope  = Options.EspCropPlot    and Options.EspCropPlot.Value    or "All Plots"
        local selectedCrops = Options.EspCrops    and Options.EspCrops.Value       or {}
        local minValue   = State.EspCropMinValue or 0
        local allCrops   = selectedCrops["All"] or next(selectedCrops) == nil

        local wanted = {} -- fruit → label text

        for _, entry in ipairs(allFruits) do
            -- Plot scope filter
            if plotScope == "Own Plot"    and not entry.isOwn then continue end
            if plotScope == "Other Plots" and entry.isOwn     then continue end

            local attrs     = entry.fruit:GetAttributes()
            local fruitName = attrs.CorePartName or entry.fruit.Name

            -- Crop name filter
            if not allCrops and not selectedCrops[fruitName] then continue end

            local finalVal, sizeMulti, mutList, base = getFruitValue(attrs, fruitName)

            -- Min value filter
            if finalVal < minValue then continue end

            local mutText = (#mutList > 0) and table.concat(mutList, ", ") or "None"
            local labelText = string.format("%s\n~%d | x%.2f\n%s", fruitName, finalVal, sizeMulti, mutText)

            wanted[entry.fruit] = labelText
        end

        -- Remove labels for fruits no longer wanted
        for fruit, gui in pairs(cropEspLabels) do
            if not wanted[fruit] or not fruit.Parent then
                if gui and gui.Parent then gui:Destroy() end
                cropEspLabels[fruit] = nil
            end
        end

        -- Add/update labels for wanted fruits
        for fruit, text in pairs(wanted) do
            if not cropEspLabels[fruit] or not cropEspLabels[fruit].Parent then
                cropEspLabels[fruit] = makeCropLabel(fruit, text)
            else
                -- Update text in place
                local lbl = cropEspLabels[fruit]:FindFirstChildOfClass("TextLabel")
                if lbl then lbl.Text = text end
            end
        end
    end

    -- Crop ESP UI
    Tabs.ESP:AddParagraph({ Title = "Crop ESP", Content = "Show labels above crops across plots." })

    local EspCropDropdown = Tabs.ESP:AddDropdown("EspCrops", {
        Title   = "Select Crops",
        Values  = { "All", "Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn", "Daffodil", "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut", "Cacao", "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper", "Cactus", "Beanstalk" },
        Multi   = true,
        Default = { "All" }
    })

    local EspCropPlotDropdown = Tabs.ESP:AddDropdown("EspCropPlot", {
        Title   = "Plot Scope",
        Values  = { "Own Plot", "Other Plots", "All Plots" },
        Multi   = false,
        Default = 3
    })

    local EspCropMinValueInput = Tabs.ESP:AddInput("EspCropMinValue", {
        Title       = "Minimum Value",
        Default     = "0",
        Placeholder = "Enter minimum crop value...",
        Numeric     = true,
        Callback    = function(Value)
            State.EspCropMinValue = tonumber(Value) or 0
        end
    })

    local EspCropsToggle = Tabs.ESP:AddToggle("EspCropsEnabled", {
        Title   = "ESP Crops",
        Default = false
    })
    EspCropsToggle:OnChanged(function()
        State.EspCropsEnabled = Options.EspCropsEnabled.Value
        if not State.EspCropsEnabled then destroyCropEsp() end
    end)

    -- Crop ESP loop: refreshes labels every 2 seconds
    task.spawn(function()
        while true do
            task.wait(2)
            if State.EspCropsEnabled then
                local ok, err = pcall(updateCropEsp)
                if not ok then warn("[VonHub] Crop ESP error:", err) end
            end
        end
    end)

    ----------------------------------------------------
    -- PET ESP
    -- BillboardGui above each WildPet showing species name.
    -- Uses the same species-detection logic as Auto Buy Pets.
    -- Filtered by the selected pet dropdown.
    -- No size filter — there is no size dropdown here.
    ----------------------------------------------------

    local petEspLabels = {} -- petModel → BillboardGui

    local function destroyPetEsp()
        for model, gui in pairs(petEspLabels) do
            if gui and gui.Parent then gui:Destroy() end
        end
        petEspLabels = {}
    end

    local function makePetLabel(petModel, species)
        -- Attach to PrimaryPart or the model itself (pcall-safe: PrimaryPart errors on plain Parts)
        local adornee
        local ok, pp = pcall(function() return petModel.PrimaryPart end)
        adornee = (ok and pp) or petModel
        local gui = Instance.new("BillboardGui")
        gui.Name            = "VonHubPetESP"
        gui.Adornee         = adornee
        gui.Size            = UDim2.fromOffset(160, 36)
        gui.StudsOffset     = Vector3.new(0, 4, 0)
        gui.AlwaysOnTop     = true
        gui.ResetOnSpawn    = false
        gui.Parent          = petModel

        local label = Instance.new("TextLabel")
        label.Size                   = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3             = Color3.fromRGB(100, 220, 255)
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
        label.Font                   = Enum.Font.GothamBold
        label.TextSize               = 14
        label.Text                   = species ~= "" and species or "Pet"
        label.Parent                 = gui

        return gui
    end

    -- Resolve species name from a WildPet model (same logic as Auto Buy Pets)
    local function getPetSpecies(petModel)
        local species = petModel:GetAttribute("PetType")
            or petModel:GetAttribute("PetName")
            or petModel:GetAttribute("Name")
            or ""
        if species == "" then
            for _, child in ipairs(petModel:GetChildren()) do
                local ok = pcall(function()
                    local _ = ReplicatedStorage.Assets.Pets[child.Name]
                end)
                if ok then species = child.Name break end
            end
        end
        return species
    end

    local function updatePetEsp()
        local selectedPets = Options.EspPets and Options.EspPets.Value or {}
        local allPets      = selectedPets["All"] or next(selectedPets) == nil

        local wildPets = GetWildPets()
        local liveModels = {}
        for _, petModel in ipairs(wildPets) do
            liveModels[petModel] = true
        end

        -- Remove labels for pets that are gone
        for model, gui in pairs(petEspLabels) do
            if not liveModels[model] or not model.Parent then
                if gui and gui.Parent then gui:Destroy() end
                petEspLabels[model] = nil
            end
        end

        -- Add labels for new pets
        for _, petModel in ipairs(wildPets) do
            local species = getPetSpecies(petModel)

            -- Species filter
            if not allPets and not selectedPets[species] then
                -- Remove if previously labelled
                if petEspLabels[petModel] then
                    petEspLabels[petModel]:Destroy()
                    petEspLabels[petModel] = nil
                end
                continue
            end

            if not petEspLabels[petModel] or not petEspLabels[petModel].Parent then
                petEspLabels[petModel] = makePetLabel(petModel, species)
            end
        end
    end

    -- Pet ESP UI
    Tabs.ESP:AddParagraph({ Title = "Pet ESP", Content = "Show labels above wild pets on the map." })

    local EspPetDropdown = Tabs.ESP:AddDropdown("EspPets", {
        Title   = "Select Pets",
        Values  = { "All", "Bee", "Butterfly", "Ladybug", "Caterpillar", "Snail", "Dragonfly" },
        Multi   = true,
        Default = { "All" }
    })

    local EspPetsToggle = Tabs.ESP:AddToggle("EspPetsEnabled", {
        Title   = "ESP Pets",
        Default = false
    })
    EspPetsToggle:OnChanged(function()
        State.EspPetsEnabled = Options.EspPetsEnabled.Value
        if not State.EspPetsEnabled then destroyPetEsp() end
    end)

    -- Pet ESP loop: refreshes every 2 seconds
    task.spawn(function()
        while true do
            task.wait(2)
            if State.EspPetsEnabled then
                local ok, err = pcall(updatePetEsp)
                if not ok then warn("[VonHub] Pet ESP error:", err) end
            end
        end
    end)
end

--------------------------------------------------
-- TAB 8: MOVEMENT
--------------------------------------------------

do
    -- Mode section
    Tabs.Movement:AddParagraph({
        Title   = "Movement Mode",
        Content = "Choose between instant teleport or smooth tween movement for all auto-features. Only one tween can run at a time."
    })

    local MoveModeDropdown = Tabs.Movement:AddDropdown("MovementMode", {
        Title   = "Movement Mode",
        Values  = { "Teleport", "Tween" },
        Multi   = false,
        Default = 1
    })
    MoveModeDropdown:OnChanged(function()
        local val = Options.MovementMode and Options.MovementMode.Value or "Teleport"
        MovementSystem.TweenMode = (val == "Tween")
    end)

    local TweenSpeedInput = Tabs.Movement:AddInput("TweenSpeed", {
        Title       = "Tween Speed (studs/sec)",
        Default     = "50",
        Placeholder = "Enter speed (default 50)...",
        Numeric     = true,
        Callback    = function(Value)
            local num = tonumber(Value)
            if num and num > 0 then
                MovementSystem.TweenSpeed = num
            end
        end
    })

    -- Priority section
    -- There are 5 teleport-using functions. Assign each a priority from 1–5.
    -- Higher priority = moves first when multiple are queued.
    Tabs.Movement:AddParagraph({
        Title   = "Priority Order",
        Content = "Set the execution priority for each movement function. Higher number = moves first. Useful in Tween mode where moves are queued and only one can happen at a time."
    })

    local priorityNums = { "1", "2", "3", "4", "5" }

    local PlantPriorityDropdown = Tabs.Movement:AddDropdown("PriorityPlant", {
        Title   = "Plant Priority",
        Desc    = "Priority for Auto Plant teleport/tween to plot center",
        Values  = priorityNums,
        Multi   = false,
        Default = 3
    })
    PlantPriorityDropdown:OnChanged(function()
        local v = tonumber(Options.PriorityPlant and Options.PriorityPlant.Value or "3") or 3
        MovementSystem.Priority.Plant = v
    end)

    local CollectPriorityDropdown = Tabs.Movement:AddDropdown("PriorityCollect", {
        Title   = "Collect Priority",
        Desc    = "Priority for Auto Collect teleport/tween to plot center",
        Values  = priorityNums,
        Multi   = false,
        Default = 3
    })
    CollectPriorityDropdown:OnChanged(function()
        local v = tonumber(Options.PriorityCollect and Options.PriorityCollect.Value or "3") or 3
        MovementSystem.Priority.Collect = v
    end)

    local BuyPetsPriorityDropdown = Tabs.Movement:AddDropdown("PriorityBuyPets", {
        Title   = "Buy Pets Priority",
        Desc    = "Priority for Auto Buy Pets teleport/tween onto each pet",
        Values  = priorityNums,
        Multi   = false,
        Default = 3
    })
    BuyPetsPriorityDropdown:OnChanged(function()
        local v = tonumber(Options.PriorityBuyPets and Options.PriorityBuyPets.Value or "3") or 3
        MovementSystem.Priority.BuyPets = v
    end)

    local NightStealPriorityDropdown = Tabs.Movement:AddDropdown("PriorityNightSteal", {
        Title   = "Night Steal Priority",
        Desc    = "Priority for Night Event teleport/tween onto target fruit. Return Home is automatic at the end of each steal cycle.",
        Values  = priorityNums,
        Multi   = false,
        Default = 3
    })
    NightStealPriorityDropdown:OnChanged(function()
        local v = tonumber(Options.PriorityNightSteal and Options.PriorityNightSteal.Value or "3") or 3
        MovementSystem.Priority.NightSteal = v
    end)

    local SeedFarmPriorityDropdown = Tabs.Movement:AddDropdown("PrioritySeedFarm", {
        Title   = "Seed Farm Priority",
        Desc    = "Priority for Collect Special Seeds tween tracking. Seeds can move, so tween re-aims each Heartbeat just like Auto Buy Pets.",
        Values  = priorityNums,
        Multi   = false,
        Default = 3
    })
    SeedFarmPriorityDropdown:OnChanged(function()
        local v = tonumber(Options.PrioritySeedFarm and Options.PrioritySeedFarm.Value or "3") or 3
        MovementSystem.Priority.SeedFarm = v
    end)
end

--------------------------------------------------
-- TAB 9: PERFORMANCE
--------------------------------------------------

do
    -- -----------------------------------------------
    -- LOW GRAPHICS
    -- Combines: Remove Textures, Remove Shadows,
    --           Disable Particles & Effects,
    --           Hide Decals & Surface Textures
    -- -----------------------------------------------

    local LowGfx_TextureOriginals  = {}
    local LowGfx_ParticleOriginals = {}
    local LowGfx_DecalOriginals    = {}

    local function EnableLowGraphics()
        local lighting = game:GetService("Lighting")
        lighting.GlobalShadows = false

        LowGfx_TextureOriginals  = {}
        LowGfx_ParticleOriginals = {}
        LowGfx_DecalOriginals    = {}

        for _, v in ipairs(workspace:GetDescendants()) do
            -- Textures: set all BasePart materials to SmoothPlastic
            if v:IsA("BasePart") then
                if not (Character and v:IsDescendantOf(Character)) then
                    LowGfx_TextureOriginals[v] = v.Material
                    v.Material = Enum.Material.SmoothPlastic
                end

            -- Particles & Effects
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                LowGfx_ParticleOriginals[v] = { enabled = v.Enabled }
                pcall(function() v.Enabled = false end)
            elseif v:IsA("Beam") then
                LowGfx_ParticleOriginals[v] = { brightness = v.Brightness }
                pcall(function() v.Brightness = 0 end)

            -- Decals & Surface Textures
            elseif v:IsA("Decal") or v:IsA("Texture") then
                LowGfx_DecalOriginals[v] = v.Transparency
                pcall(function() v.Transparency = 1 end)
            end
        end
    end

    local function DisableLowGraphics()
        local lighting = game:GetService("Lighting")
        lighting.GlobalShadows = true

        for part, mat in pairs(LowGfx_TextureOriginals) do
            if part and part.Parent then part.Material = mat end
        end
        LowGfx_TextureOriginals = {}

        for obj, orig in pairs(LowGfx_ParticleOriginals) do
            if obj and obj.Parent then
                if orig.enabled ~= nil then
                    pcall(function() obj.Enabled = orig.enabled end)
                elseif orig.brightness ~= nil then
                    pcall(function() obj.Brightness = orig.brightness end)
                end
            end
        end
        LowGfx_ParticleOriginals = {}

        for obj, t in pairs(LowGfx_DecalOriginals) do
            if obj and obj.Parent then
                pcall(function() obj.Transparency = t end)
            end
        end
        LowGfx_DecalOriginals = {}
    end

    local LowGraphicsToggle = Tabs.Performance:AddToggle("LowGraphics", {
        Title   = "Low Graphics Mode",
        Desc    = "Removes textures, shadows, particles, decals, and surface effects to maximise FPS. Restores everything on disable.",
        Default = false
    })
    local function ApplyLowGraphics()
        if Options.LowGraphics.Value then
            EnableLowGraphics()
        else
            DisableLowGraphics()
        end
    end
    LowGraphicsToggle:OnChanged(ApplyLowGraphics)
    ApplyFunctions.LowGraphics = ApplyLowGraphics

    -- Screen Overlay: covers the entire 3D world without touching Fluent's layer.
    -- We find the Fluent ScreenGui's DisplayOrder at runtime and sit one below it.
    local StarterGui = game:GetService("StarterGui")
    local OverlayGui = nil

    local function GetFluentOrder()
        -- Fluent parents its root ScreenGui to CoreGui; find it by scanning
        for _, sg in ipairs(CoreGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "VonHubOverlay" then
                -- Take the highest DisplayOrder we find that isn't ours
                return sg.DisplayOrder
            end
        end
        return 10  -- safe fallback
    end

    local function EnableOverlay()
        if OverlayGui then return end

        -- Only hide the topbar, NOT the backpack or other core GUI elements
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.TopbarEnabled, false)
        end)

        local fluentOrder = GetFluentOrder()

        OverlayGui = Instance.new("ScreenGui")
        OverlayGui.Name           = "VonHubOverlay"
        OverlayGui.ResetOnSpawn   = false
        OverlayGui.DisplayOrder   = fluentOrder - 1
        OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        OverlayGui.IgnoreGuiInset = true

        local ok = pcall(function() OverlayGui.Parent = CoreGui end)
        if not ok then OverlayGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local Frame = Instance.new("Frame")
        Frame.Size                   = UDim2.fromScale(1, 1)
        Frame.Position               = UDim2.fromScale(0, 0)
        Frame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
        Frame.BackgroundTransparency = 0
        Frame.BorderSizePixel        = 0
        Frame.ZIndex                 = 1
        Frame.Parent                 = OverlayGui
    end

    local function DisableOverlay()
        if OverlayGui then
            OverlayGui:Destroy()
            OverlayGui = nil
        end
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.TopbarEnabled, true)
        end)
    end

    local ScreenOverlayToggle = Tabs.Performance:AddToggle("ScreenOverlay", {
        Title   = "Screen Overlay",
        Desc    = "Covers the 3D world with a black screen. UI elements above it remain visible.",
        Default = false
    })
    local function ApplyScreenOverlay()
        if Options.ScreenOverlay.Value then
            EnableOverlay()
        else
            DisableOverlay()
        end
    end
    ScreenOverlayToggle:OnChanged(ApplyScreenOverlay)
    ApplyFunctions.ScreenOverlay = ApplyScreenOverlay

    -- Delete Other Players Plots
    -- Locally destroys every garden plot that does not belong to the local player.
    -- Client-side only (lag reduction). Turning the toggle off is a no-op;
    -- the plots are gone until the server replicates them back or the player rejoins.
    -- Tracks BaseParts hidden by the delete-plots feature so they can be restored.
    -- We never call :Destroy() on plot instances — that breaks PlotsController which
    -- holds live references to them and errors with "attempt to index nil with Parent"
    -- when the instance is gone. Instead we just make every BasePart invisible and
    -- non-collidable so the plot still exists in the DataModel but renders nothing.
    local HiddenPlotParts = {}   -- BasePart → { Transparency, CanCollide, CastShadow }

    local function HideOtherPlots()
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return end
        local myPlot = FindMyPlot()
        local plotCount = 0
        for _, plot in ipairs(gardens:GetChildren()) do
            if not (plot:IsA("Model") or plot:IsA("Folder")) then continue end
            if plot == myPlot then continue end
            plotCount = plotCount + 1
            for _, desc in ipairs(plot:GetDescendants()) do
                if desc:IsA("BasePart") and not HiddenPlotParts[desc] then
                    HiddenPlotParts[desc] = {
                        Transparency = desc.Transparency,
                        CanCollide   = desc.CanCollide,
                        CastShadow   = desc.CastShadow,
                    }
                    desc.Transparency = 1
                    desc.CanCollide   = false
                    desc.CastShadow   = false
                end
            end
        end
        Fluent:Notify({
            Title   = "Other Plots Hidden",
            Content = string.format("Hid %d other plot(s) client-side. Toggle off to restore.", plotCount),
            Duration = 4
        })
    end

    local function RestoreOtherPlots()
        for part, original in pairs(HiddenPlotParts) do
            if part and part.Parent then
                part.Transparency = original.Transparency
                part.CanCollide   = original.CanCollide
                part.CastShadow   = original.CastShadow
            end
        end
        HiddenPlotParts = {}
        Fluent:Notify({
            Title   = "Other Plots Restored",
            Content = "Restored visibility of all hidden plots.",
            Duration = 3
        })
    end

    local DeletePlotsToggle = Tabs.Performance:AddToggle("DeleteOtherPlots", {
        Title   = "Hide Other Players Plots",
        Desc    = "Makes all other players garden plots invisible and non-collidable client-side to reduce lag. Toggle off to restore them. Does not break game scripts.",
        Default = false
    })
    local function ApplyDeleteOtherPlots()
        if Options.DeleteOtherPlots.Value then
            HideOtherPlots()
        else
            RestoreOtherPlots()
        end
    end
    DeletePlotsToggle:OnChanged(ApplyDeleteOtherPlots)
    ApplyFunctions.DeleteOtherPlots = ApplyDeleteOtherPlots

    -- -----------------------------------------------
    -- SOUNDS
    -- -----------------------------------------------

    local SoundOriginals = {}   -- Sound → original Volume

    local function EnableDisableSounds()
        SoundOriginals = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Sound") then
                SoundOriginals[obj] = obj.Volume
                pcall(function() obj.Volume = 0 end)
            end
        end
    end

    local function DisableDisableSounds()
        for obj, vol in pairs(SoundOriginals) do
            if obj and obj.Parent then
                pcall(function() obj.Volume = vol end)
            end
        end
        SoundOriginals = {}
    end

    local DisableSoundsToggle = Tabs.Performance:AddToggle("DisableSounds", {
        Title   = "Mute In-World Sounds",
        Desc    = "Sets volume to 0 on all Sounds in workspace. Restores on disable.",
        Default = false
    })
    local function ApplyDisableSounds()
        if Options.DisableSounds.Value then
            EnableDisableSounds()
        else
            DisableDisableSounds()
        end
    end
    DisableSoundsToggle:OnChanged(ApplyDisableSounds)
    ApplyFunctions.DisableSounds = ApplyDisableSounds

    -- -----------------------------------------------
    -- RENDER DISTANCE (LOD)
    -- -----------------------------------------------

    local function SetRenderDistance(value)
        local ok = pcall(function()
            settings().Rendering.QualityLevel = value
        end)
        if not ok then
            -- Fallback: adjust via UserGameSettings if available
            pcall(function()
                UserSettings():GetService("UserGameSettings").SavedQualityLevel = value
            end)
        end
    end

    local RenderQualityDropdown = Tabs.Performance:AddDropdown("RenderQuality", {
        Title   = "Render Quality",
        Desc    = "Overrides Roblox graphics quality. Lower values improve FPS significantly.",
        Values  = { "Auto", "1 (Lowest)", "2", "3", "4", "5", "6 (Medium)", "7", "8", "9", "10 (Highest)" },
        Multi   = false,
        Default = 1
    })
    RenderQualityDropdown:OnChanged(function()
        local val = Options.RenderQuality and Options.RenderQuality.Value or "Auto"
        if val == "Auto" then
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
        else
            local num = tonumber(val:match("^(%d+)"))
            if num then SetRenderDistance(num) end
        end
    end)
end

--------------------------------------------------
-- TAB 10: SETTINGS
--------------------------------------------------

--------------------------------------------------
-- CONFIG SYSTEM (autosave + autoload only)
--
-- THE REAL BUG: every option's :OnChanged(fn) call REPLACES that
-- option's existing change-handler — it does NOT add a second listener.
-- Almost every toggle/input in this script already calls :OnChanged()
-- once to register its real effect (ApplyWalkSpeed, ApplyNoclip, etc).
-- The previous autosave code then looped over every option and called
-- :OnChanged() AGAIN to attach the save call — which silently threw away
-- every real handler and replaced it with "just save", so none of the
-- toggles/buttons actually did anything anymore.
--
-- Fix: never call :OnChanged() (or touch .Callback) on an existing
-- option here. Just poll the option values on a short timer and write
-- out a config only when something actually changed. This can't clobber
-- anything because it never registers a handler on the elements at all.
--------------------------------------------------

local AUTOSAVE_CONFIG = "growagardentwo"

SaveManager:SetLibrary(Fluent)
SaveManager:SetFolder("VonHub")
SaveManager:IgnoreThemeSettings() -- InterfaceManager already persists theme/acrylic/transparency/menu keybind on its own

local function SnapshotOptions()
    local snap = {}
    for idx, option in pairs(Options) do
        local ok, value = pcall(function() return option.Value end)
        if ok then snap[idx] = value end
    end
    return snap
end

local function SnapshotsMatch(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then return false end
    end
    return true
end

-- Autosave + Autoload, run sequentially in one coroutine.
--
-- THE RACE CONDITION: load and autosave used to be two separate
-- task.spawn()'d coroutines that both did task.wait(1) and then ran.
-- Lua doesn't guarantee which one resumes first. If the autosave loop's
-- very first poll ran before the load finished, LastSnapshot was still
-- nil, so it treated the UI's still-default values as "a change" and
-- immediately saved over the real config with defaults — which is
-- exactly why everything looked reset after re-executing.
--
-- Fix: load first, wait for the restore to actually land, snapshot,
-- and only then start polling — all in the same coroutine, so the
-- autosave loop physically cannot run before the load completes.
local LastSnapshot = nil
task.spawn(function()
    task.wait(1) -- let every tab finish registering its options first

    local ok, err = SaveManager:Load(AUTOSAVE_CONFIG)
    if ok then
    else
    end

    -- SaveManager:Load() restores each option via task.spawn() internally,
    -- so the values aren't applied the instant Load() returns. Give them
    -- a moment to land before taking the baseline snapshot.
    task.wait(0.25)
    LastSnapshot = SnapshotOptions()

    while true do
        task.wait(1)
        local snap = SnapshotOptions()
        if not SnapshotsMatch(snap, LastSnapshot) then
            local saveOk, saveErr = SaveManager:Save(AUTOSAVE_CONFIG)
            if saveOk then
                LastSnapshot = snap
            else
            end
        end
    end
end)

-- Settings tab: theme + server
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("VonHub")

do
    -- Theme section
    InterfaceManager:BuildInterfaceSection(Tabs.Settings)

    Tabs.Settings:AddParagraph({
        Title   = "Resize Tip",
        Content = "Dragging the bottom-right corner of the window will resize the UI."
    })

    -- Server section
    Tabs.Settings:AddParagraph({ Title = "Server", Content = "Server management and hopping tools." })

    local JobIdInput = Tabs.Settings:AddInput("JobIdInput", {
        Title       = "Job ID",
        Default     = "",
        Placeholder = "Enter server Job ID...",
        Callback    = function() end
    })

    Tabs.Settings:AddButton({
        Title   = "Join Job ID",
        Desc    = "Teleports you to the server with the entered Job ID",
        Callback = function()
            local jobId = Options.JobIdInput and Options.JobIdInput.Value or ""
            if jobId == "" then
                Fluent:Notify({ Title = "Error", Content = "Please enter a valid Job ID.", Duration = 3 })
                return
            end
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
            end)
            if not ok then
                Fluent:Notify({ Title = "Teleport Failed", Content = tostring(err), Duration = 5 })
            end
        end
    })

    Tabs.Settings:AddButton({
        Title   = "Server Hop",
        Desc    = "Teleports you to a new server",
        Callback = function()
            local ok, err = pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
            if not ok then
                Fluent:Notify({ Title = "Server Hop Failed", Content = tostring(err), Duration = 5 })
            end
        end
    })

end

--------------------------------------------------
-- FINISH
--------------------------------------------------

Window:SelectTab(1)

Fluent:Notify({
    Title   = "Von Hub Loaded",
    Content = "Welcome! Join us at .gg/rNvAU6cjVB",
    Duration = 6
})
