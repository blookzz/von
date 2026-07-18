-- This file was protected using Luraph Obfuscator v14.7 [https://lura.ph/]
-- Open Source From @emcev, Full TP To Best Source

if not game:IsLoaded() then game.Loaded:Wait() end

-- =====================================================================
-- UILib Bootstrap
-- =====================================================================
local UILib = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/blookzz/skibidi/refs/heads/main/UILib.lua"
))()

-- =====================================================================
-- Settings persistence (writefile/readfile JSON)
-- =====================================================================
local SETTINGS_FILE = "von_settings.json"

local _defaultSettings = {
    TPVelocity   = 200,
    VonClimb  = 100,
    LandingDelay = 0.1,
    UseGrapple   = true,
    PreferCarpet = "",
    StealMode    = nil,
    CloneMethod  = "firesignal",
    PriorityList = {},
    StartKey     = "T",
    StopKey      = "G",
    AutoRun      = false,
    MinValue     = 0,
    AutoSteal    = false,
    GuiX         = nil,
    GuiY         = nil,
    Minimized    = false,
}

local _guiState = {}

local function saveSettings()
    local data = {
        TPVelocity   = _G.TPVelocity,
        VonClimb  = _G.VonClimb,
        LandingDelay = _G.LandingDelay,
        UseGrapple   = _G.UseGrapple,
        PreferCarpet = _G.PreferCarpet or "",
        StealMode    = _G.VonStealMode or "priority",
        CloneMethod  = _G.VonCloneMethod or "firesignal",
        PriorityList = _G.SHARED_PRIORITY_ITEMS or {},
        StartKey     = (_G._UI_StartKey and _G._UI_StartKey.Name) or "T",
        StopKey      = (_G._UI_StopKey  and _G._UI_StopKey.Name)  or "G",
        AutoRun      = _G.VonAutoRun or false,
        MinValue     = _G.VonMinValue or 0,
        AutoSteal    = _G.VonAutoSteal or false,
        GuiX         = _guiState.GuiX,
        GuiY         = _guiState.GuiY,
        Minimized    = _guiState.Minimized,
    }
    local ok, err = pcall(writefile, SETTINGS_FILE, game:GetService("HttpService"):JSONEncode(data))
    if not ok then warn("[Von] Could not save settings:", err) end
end

local function loadSettings()
    local s = _defaultSettings
    if isfile and isfile(SETTINGS_FILE) then
        local ok, decoded = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(SETTINGS_FILE))
        end)
        if ok and type(decoded) == "table" then s = decoded end
    end
    return s
end

local _saved = loadSettings()

_guiState.GuiX      = tonumber(_saved.GuiX)
_guiState.GuiY      = tonumber(_saved.GuiY)
_guiState.Minimized = _saved.Minimized == true

-- =====================================================================
-- Default configurable values (seeded from saved settings)
-- =====================================================================
_G.TPVelocity     = tonumber(_saved.TPVelocity)   or 200
_G.VonClimb    = tonumber(_saved.VonClimb)  or 100
_G.LandingDelay   = tonumber(_saved.LandingDelay) or 0.1
_G.UseGrapple     = (_saved.UseGrapple ~= false)
_G.PreferCarpet   = _saved.PreferCarpet or ""
_G.VonStealMode  = (_saved.StealMode ~= "priority") and _saved.StealMode or nil
_G.VonCloneMethod = _saved.CloneMethod or "firesignal"
_G.SHARED_PRIORITY_ITEMS = (type(_saved.PriorityList) == "table") and _saved.PriorityList or {}
_G.VonTPCancel = false
_G.VonAutoRun  = (_saved.AutoRun == true)
_G.VonMinValue = tonumber(_saved.MinValue) or 0
_G.VonAutoSteal = (_saved.AutoSteal ~= false)

-- =====================================================================
-- _normName (defined early — used by both UI and scan logic)
-- =====================================================================
local function _normName(s)
    return tostring(s):lower():gsub("[%s%-_'%.]", "")
end

-- =====================================================================
-- Build the UI panel
-- =====================================================================
local panel = UILib.CreatePanel({
    Name       = "VonTPGui",
    Title      = "Von TP",
    Width      = 300,
    Height     = 200,
    Discord    = true
    Tabs       = { "Controls", "Settings", "Priority" },
    DefaultTab = 1,
    Minimized  = _guiState.Minimized,
})

-- Restore saved position
if _guiState.GuiX and _guiState.GuiY then
    panel.Frame.Position = UDim2.new(0, _guiState.GuiX, 0, _guiState.GuiY)
end

-- Save absolute screen position whenever the panel is dragged
panel.Frame:GetPropertyChangedSignal("Position"):Connect(function()
    local abs = panel.Frame.AbsolutePosition
    _guiState.GuiX = abs.X
    _guiState.GuiY = abs.Y
    saveSettings()
end)

-- Save minimized state by detecting the MinBtn (the "–"/"+" button) in the header
local _minBtn = nil
for _, child in ipairs(panel.Header:GetChildren()) do
    if child:IsA("TextButton") and (child.Text == "–" or child.Text == "+") then
        _minBtn = child
        break
    end
end
if _minBtn then
    _minBtn.MouseButton1Click:Connect(function()
        -- IsMinimized reflects the NEW state after the click (UILib toggles before our signal fires)
        task.defer(function()
            _guiState.Minimized = panel.IsMinimized()
            saveSettings()
        end)
    end)
end

local tabControls = panel.GetTab(1)
local tabSettings = panel.GetTab(2)
local tabPriority = panel.GetTab(3)

-- ── Controls Tab ──────────────────────────────────────────────────────

local secRun = UILib.CreateSection(tabControls, { Title = "Run / Stop", Open = true })

local _running = false

UILib.CreateButton(secRun.Content, {
    Text      = "Start",
    Color     = Color3.fromRGB(30, 80, 30),
    TextColor = Color3.fromRGB(140, 230, 140),
    OnClick   = function()
        if _running then return end
        _running = true
        _G.VonTPCancel = false
        UILib.ShowNotification("Von TP", "Running...")
        task.spawn(function()
            local ok, err = pcall(_G.VonStartSideTP or function() end)
            if not ok then warn("[UI] TP error:", err) end
            _running = false
        end)
    end,
})

UILib.CreateButton(secRun.Content, {
    Text      = "Stop",
    Color     = Color3.fromRGB(80, 20, 20),
    TextColor = Color3.fromRGB(230, 120, 120),
    OnClick   = function()
        _G.VonTPCancel = true
        _running = false
        UILib.ShowNotification("Von TP", "Stopped")
    end,
})

local secAutoRun = UILib.CreateSection(tabControls, { Title = "Auto Run", Open = true })

UILib.CreateToggle(secAutoRun.Content, {
    Label     = "Run once on load",
    Default   = _G.VonAutoRun,
    OnChanged = function(state)
        _G.VonAutoRun = state
        saveSettings()
    end,
})

local secKeybinds = UILib.CreateSection(tabControls, { Title = "Keybinds", Open = true })

UILib.CreateKeybind(secKeybinds.Content, {
    Label     = "Start",
    Default   = Enum.KeyCode[_saved.StartKey] or Enum.KeyCode.T,
    OnChanged = function(kc)
        _G._UI_StartKey = kc
        saveSettings()
    end,
})

UILib.CreateKeybind(secKeybinds.Content, {
    Label     = "Stop / Cancel",
    Default   = Enum.KeyCode[_saved.StopKey] or Enum.KeyCode.G,
    OnChanged = function(kc)
        _G._UI_StopKey = kc
        saveSettings()
    end,
})

_G._UI_StartKey = Enum.KeyCode[_saved.StartKey] or Enum.KeyCode.T
_G._UI_StopKey  = Enum.KeyCode[_saved.StopKey]  or Enum.KeyCode.G

-- ── Settings Tab ─────────────────────────────────────────────────────

local secSpeed = UILib.CreateSection(tabSettings, { Title = "Speed Settings", Open = true })

UILib.CreateTextInput(secSpeed.Content, {
    Label       = "Travel Speed",
    Placeholder = "e.g. 200",
    Default     = tostring(_G.TPVelocity),
    NumericOnly = true,
    Width       = 70,
    OnSubmit    = function(v)
        local n = tonumber(v) or 200
        _G.TPVelocity = n
        saveSettings()
    end,
})

UILib.CreateTextInput(secSpeed.Content, {
    Label       = "Climb Cap",
    Placeholder = "e.g. 100",
    Default     = tostring(_G.VonClimb),
    NumericOnly = true,
    Width       = 70,
    OnSubmit    = function(v)
        local n = tonumber(v) or 100
        _G.VonClimb = n
        saveSettings()
    end,
})

UILib.CreateTextInput(secSpeed.Content, {
    Label       = "Clone Delay (s)",
    Placeholder = "e.g. 0.1s",
    Default     = tostring(_G.LandingDelay),
    NumericOnly = false,
    Width       = 70,
    OnSubmit    = function(v)
        local n = tonumber(v) or 0.1
        _G.LandingDelay = n
        saveSettings()
    end,
})

local secMinValue = UILib.CreateSection(tabSettings, { Title = "Value Filter", Open = true })

UILib.CreateTextInput(secMinValue.Content, {
    Label       = "Min Value ($/s)",
    Placeholder = "e.g. 1000",
    Default     = tostring(_G.VonMinValue),
    NumericOnly = true,
    Width       = 70,
    OnSubmit    = function(v)
        _G.VonMinValue = tonumber(v) or 0
        saveSettings()
    end,
})

local secGrapple = UILib.CreateSection(tabSettings, { Title = "Grapple Hook", Open = true })

UILib.CreateToggle(secGrapple.Content, {
    Label     = "Use Grapple Hook",
    Default   = _G.UseGrapple,
    OnChanged = function(state)
        _G.UseGrapple = state
        saveSettings()
    end,
})

local secCarpet = UILib.CreateSection(tabSettings, { Title = "Carpet Tool", Open = true })

UILib.CreateDropdown(secCarpet.Content, {
    Label    = "Preferred Carpet",
    Options  = { "Any (auto)", "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet" },
    Default  = (_G.PreferCarpet ~= "") and _G.PreferCarpet or "Any (auto)",
    OnChanged = function(val)
        _G.PreferCarpet = (val == "Any (auto)") and "" or val
        saveSettings()
    end,
})

local secMode = UILib.CreateSection(tabSettings, { Title = "Target Mode", Open = true })

local _stealModeDefault = 1
if _G.VonStealMode == "highest" then _stealModeDefault = 2 end

UILib.group(secMode.Content, {
    Label     = "Steal Target",
    Options   = { "Priority", "Highest" },
    Default   = _stealModeDefault,
    OnChanged = function(i)
        if     i == 1 then _G.VonStealMode = nil
        elseif i == 2 then _G.VonStealMode = "highest"
        end
        saveSettings()
    end,
})

local secClone = UILib.CreateSection(tabSettings, { Title = "Clone Method", Open = true })

local _cloneMethodDefault = (_G.VonCloneMethod == "remote") and 2 or 1

UILib.group(secClone.Content, {
    Label     = "Clone Method",
    Options   = { "FireSignal", "Remote" },
    Default   = _cloneMethodDefault,
    OnChanged = function(i)
        if     i == 1 then _G.VonCloneMethod = "firesignal"
        elseif i == 2 then _G.VonCloneMethod = "remote"
        end
        saveSettings()
    end,
})

local secAutoSteal = UILib.CreateSection(tabSettings, { Title = "Auto Steal", Open = true })

UILib.CreateToggle(secAutoSteal.Content, {
    Label     = "Steal after teleport",
    Default   = _G.VonAutoSteal,
    OnChanged = function(state)
        _G.VonAutoSteal = state
        saveSettings()
    end,
})

-- ── Priority List Tab ────────────────────────────────────────────────

-- Load all known animal names from the game data
local _knownAnimals = {}
task.spawn(function()
    local ok, Animals = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("Datas"):WaitForChild("Animals"))
    end)
    if ok and type(Animals) == "table" then
        for animalName in pairs(Animals) do
            _knownAnimals[_normName(animalName)] = animalName
        end
        print(string.format("[Von] Loaded %d known animals", #(function() local t={} for _ in pairs(_knownAnimals) do t[#t+1]=_ end return t end)()))
    else
        warn("[Von] Could not load Animals data:", Animals)
    end
end)

-- Parse a raw paste string and extract known animal names in order of appearance
local function parseAnimalList(raw)
    if next(_knownAnimals) == nil then return {} end

    local normRaw = _normName(raw)  -- strip spaces/punctuation same way as keys

    -- Find every animal that appears in the normalised input, record its position
    local hits = {}
    for norm, display in pairs(_knownAnimals) do
        local pos = normRaw:find(norm, 1, true)
        if pos then
            hits[#hits+1] = { pos = pos, display = display }
        end
    end

    -- Sort by position (appearance order = priority order)
    table.sort(hits, function(a, b) return a.pos < b.pos end)

    -- Deduplicate while preserving order
    local found = {}
    local seen  = {}
    for _, h in ipairs(hits) do
        if not seen[h.display] then
            found[#found+1] = h.display
            seen[h.display] = true
        end
    end
    return found
end

local secPriInput = UILib.CreateSection(tabPriority, { Title = "Paste Animal List", Open = true })

UILib.paragraph(secPriInput.Content, {
    Content = "Paste any text containing animal names. Recognised names will be extracted in order (top = highest priority).",
})

-- Multi-line paste box
local _pasteBox = Instance.new("TextBox")
_pasteBox.Size              = UDim2.new(1, 0, 0, 80)
_pasteBox.BackgroundColor3  = game:GetService("TweenService") and UILib.Theme.InputBg or Color3.fromRGB(14,13,10)
_pasteBox.BackgroundColor3  = UILib.Theme.InputBg
_pasteBox.BorderSizePixel   = 0
_pasteBox.Font              = Enum.Font.Gotham
_pasteBox.TextSize          = 12
_pasteBox.TextColor3        = UILib.Theme.TextPrimary
_pasteBox.PlaceholderText   = "Paste here…"
_pasteBox.PlaceholderColor3 = UILib.Theme.TextMuted
_pasteBox.TextXAlignment    = Enum.TextXAlignment.Left
_pasteBox.TextYAlignment    = Enum.TextYAlignment.Top
_pasteBox.TextWrapped       = true
_pasteBox.ClearTextOnFocus  = false
_pasteBox.MultiLine         = true
_pasteBox.Text              = ""
_pasteBox.Parent            = secPriInput.Content
do
    local c = Instance.new("UICorner", _pasteBox); c.CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", _pasteBox)
    s.Color = UILib.Theme.AccentDim; s.Thickness = 1
    local p = Instance.new("UIPadding", _pasteBox)
    p.PaddingLeft = UDim.new(0,6); p.PaddingRight = UDim.new(0,6)
    p.PaddingTop  = UDim.new(0,4); p.PaddingBottom = UDim.new(0,4)
    _pasteBox.Focused:Connect(function()
        game:GetService("TweenService"):Create(s, TweenInfo.new(0.14), { Color = UILib.Theme.Accent }):Play()
    end)
    _pasteBox.FocusLost:Connect(function()
        game:GetService("TweenService"):Create(s, TweenInfo.new(0.14), { Color = UILib.Theme.AccentDim }):Play()
    end)
end

local secPriResult = UILib.CreateSection(tabPriority, { Title = "Priority Order", Open = true })

local _priResultLabel = Instance.new("TextLabel")
_priResultLabel.Size                   = UDim2.new(1, 0, 0, 0)
_priResultLabel.AutomaticSize          = Enum.AutomaticSize.Y
_priResultLabel.BackgroundTransparency = 1
_priResultLabel.Font                   = Enum.Font.Gotham
_priResultLabel.TextSize               = 12
_priResultLabel.TextColor3             = UILib.Theme.TextMuted
_priResultLabel.TextXAlignment         = Enum.TextXAlignment.Left
_priResultLabel.TextWrapped            = true
_priResultLabel.Text                   = "(none)"
_priResultLabel.Parent                 = secPriResult.Content

local function _refreshPriLabel()
    local list = _G.SHARED_PRIORITY_ITEMS
    if not list or #list == 0 then
        _priResultLabel.Text      = "(none)"
        _priResultLabel.TextColor3 = UILib.Theme.TextMuted
    else
        local lines = {}
        for i, name in ipairs(list) do
            lines[#lines+1] = i .. ".  " .. name
        end
        _priResultLabel.Text       = table.concat(lines, "\n")
        _priResultLabel.TextColor3 = UILib.Theme.TextPrimary
    end
end

_refreshPriLabel()

UILib.button(secPriInput.Content, {
    Text    = "Apply List",
    OnClick = function()
        local raw = _pasteBox.Text
        if raw == "" then
            _G.SHARED_PRIORITY_ITEMS = {}
            _refreshPriLabel()
            saveSettings()
            UILib.ShowNotification("Priority List", "0 animal(s) set")
            return
        end
        -- If animals haven't loaded yet, wait up to 5s
        local _t0 = os.clock()
        while next(_knownAnimals) == nil and os.clock() - _t0 < 5 do
            task.wait(0.1)
        end
        if next(_knownAnimals) == nil then
            UILib.ShowNotification("Priority List", "Animals data not loaded yet")
            return
        end
        _G.SHARED_PRIORITY_ITEMS = parseAnimalList(raw)
        _refreshPriLabel()
        saveSettings()
        UILib.ShowNotification("Priority List", #_G.SHARED_PRIORITY_ITEMS .. " animal(s) set")
    end,
})

UILib.button(secPriInput.Content, {
    Text      = "Clear List",
    Color     = Color3.fromRGB(60, 20, 20),
    TextColor = Color3.fromRGB(230, 120, 120),
    OnClick   = function()
        _G.SHARED_PRIORITY_ITEMS = {}
        _pasteBox.Text = ""
        _refreshPriLabel()
        saveSettings()
        UILib.ShowNotification("Priority List", "Cleared")
    end,
})

-- Restore paste box text from saved list on load
if _G.SHARED_PRIORITY_ITEMS and #_G.SHARED_PRIORITY_ITEMS > 0 then
    _pasteBox.Text = table.concat(_G.SHARED_PRIORITY_ITEMS, "\n")
    _refreshPriLabel()
end

-- =====================================================================
-- Keybind listener
-- =====================================================================
local UIS2 = game:GetService("UserInputService")
UIS2.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local sk = _G._UI_StartKey or Enum.KeyCode.T
    local ck = _G._UI_StopKey  or Enum.KeyCode.G
    if input.KeyCode == sk then
        if _running then return end
        _running = true
        _G.VonTPCancel = false
        task.spawn(function()
            local ok, err = pcall(_G.VonStartSideTP or function() end)
            if not ok then warn("[UI] TP error:", err) end
            _running = false
        end)
    elseif input.KeyCode == ck then
        _G.VonTPCancel = true
        _running = false
    end
end)

-- =====================================================================
-- END OF UI SECTION — original script body continues below
-- =====================================================================

-- =====================================================================
-- Services
-- =====================================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local RS                = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local TweenService      = game:GetService("TweenService")

local LP = Players.LocalPlayer

-- =====================================================================
-- Pet-scan blacklist (mirrors the document scanner)
-- =====================================================================
local BLACKLIST_EXACT   = { model = true, part = true }
local BLACKLIST_PARTIAL = {
    "animalpodiums","decorations","invisiblewalls","laser","laserhitbox",
    "purchases","skin","unlock","cash","friendpanel","animaltarget",
    "deliveryhitbox","mainroot","multiplier","plotsign","slope","spawn",
    "stealthitbox","root","hitbox","floor","wall","path","grass","barrier",
}
local function _isBlacklisted(name)
    local ln = name:lower()
    if BLACKLIST_EXACT[ln] then return true end
    for _, bl in ipairs(BLACKLIST_PARTIAL) do
        if ln:find(bl, 1, true) then return true end
    end
    return false
end

-- =====================================================================
-- Money-value reader (workspace GUI / attributes / ValueBase)
-- =====================================================================
local MONEY_KEYWORDS = { "prod","sec","money","cash","coin","income","yield","rate","amount","value","give" }
local SUFFIX_MULT    = { K=1e3, M=1e6, B=1e9, T=1e12 }

local function _parseMoneyText(raw)
    local numStr, suffix = raw:match("%$([%d,%.]+)([KkMmBbTt]?)")
    if not numStr then return nil end
    local n = tonumber((numStr:gsub(",", ""))) or 0
    local m = SUFFIX_MULT[suffix and suffix:upper() or ""]
    return m and n * m or n, raw
end

local function _getMoneyValue(item)
    local primary = (item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)))
                 or (item:IsA("BasePart") and item)
                 or item:FindFirstChildWhichIsA("BasePart", true)

    local bestMatch, fallback
    local closestBest, closestFallback = 10, 10

    local function checkGui(guiRoot, dist)
        for _, tl in ipairs(guiRoot:GetDescendants()) do
            if (tl:IsA("TextLabel") or tl:IsA("TextButton") or tl:IsA("TextBox")) and tl.Text ~= "" then
                local hasDollar = tl.Text:find("%$")
                local hasPerSec = tl.Text:lower():find("/s")
                if hasDollar and hasPerSec then
                    if dist <= closestBest then closestBest = dist; bestMatch = tl.Text end
                elseif hasDollar then
                    if dist <= closestFallback then closestFallback = dist; fallback = tl.Text end
                end
            end
        end
    end

    -- Direct children of the item itself (rare, but keep for completeness)
    checkGui(item, 0)

    -- Walk the cache (built once per scan pass, or fresh for single lookups).
    -- pgui GUIs are included in the cache by _buildWsGuiCache, so no separate
    -- pgui:GetDescendants() call is needed here during a scan pass.
    local guiList = _wsGuiCache
    if not guiList then
        -- Single-item lookup outside a scan pass — build a minimal local list
        guiList = {}
        for _, bb in ipairs(workspace:GetDescendants()) do
            if bb:IsA("BillboardGui") or bb:IsA("SurfaceGui") then
                guiList[#guiList + 1] = bb
            end
        end
        local pgui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if pgui then
            for _, bb in ipairs(pgui:GetDescendants()) do
                if (bb:IsA("BillboardGui") or bb:IsA("SurfaceGui")) and bb.Adornee then
                    guiList[#guiList + 1] = bb
                end
            end
        end
    end

    for _, bb in ipairs(guiList) do
        -- Early exit once we have a perfect match at distance 0
        if bestMatch and closestBest == 0 then break end
        local adornee = bb.Adornee
        if adornee and (adornee == item or adornee:IsDescendantOf(item)) then
            checkGui(bb, 0)
        elseif primary and bb.Parent and bb.Parent:IsA("BasePart") then
            local dist = (bb.Parent.Position - primary.Position).Magnitude
            if dist <= closestBest or dist <= closestFallback then checkGui(bb, dist) end
        end
    end

    local raw = bestMatch or fallback
    if raw then
        local n, r = _parseMoneyText(raw)
        if n then return n, r end
    end

    for attrName, value in pairs(item:GetAttributes()) do
        local ln = attrName:lower()
        for _, k in ipairs(MONEY_KEYWORDS) do
            if ln:find(k, 1, true) then
                return tonumber(tostring(value)) or 0, "$" .. tostring(value) .. "/s"
            end
        end
    end

    for _, val in ipairs(item:GetDescendants()) do
        if val:IsA("ValueBase") then
            local ln = val.Name:lower()
            for _, k in ipairs(MONEY_KEYWORDS) do
                if ln:find(k, 1, true) then
                    return tonumber(tostring(val.Value)) or 0, "$" .. tostring(val.Value) .. "/s"
                end
            end
        end
    end

    return 0, nil
end

-- =====================================================================
-- Missing stubs (referenced by name but never defined in this file)
-- =====================================================================
local function loadModules() end  -- was called at bottom but never defined
local function getPlotChannel(_plotName) return nil end
local function channelGet(_ch, _key) return nil end

local NetModule
local function loadNet()
    if NetModule then return true end
    local ok, mod = pcall(function()
        return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
    end)
    if not ok or type(mod) ~= "table" then return false end
    NetModule = mod
    return true
end

-- =====================================================================
-- Carpet / tool helpers
-- =====================================================================
local CARPET_SPEED  = 280
local SKY_CLONE_WAIT = 0.35
local _ALL_CARPET_NAMES  = { "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet" }
local _ALL_GRAPPLE_NAMES = { "Grapple Hook", "Grappling Hook", "Grapple", "Hook", "Web Slinger", "GrappleHook" }

-- Dynamic lists: UI dropdowns write to _G.PreferCarpet / _G.PreferredGrapple
-- so we resolve them at call-time via these getters.
local function CARPET_NAMES()
    local pref = _G.PreferCarpet
    if pref and pref ~= "" then
        -- Put the preferred carpet first, then the rest as fallback
        local out = { pref }
        for _, n in ipairs(_ALL_CARPET_NAMES) do
            if n ~= pref then out[#out+1] = n end
        end
        return out
    end
    return _ALL_CARPET_NAMES
end

local function GRAPPLE_NAMES()
    local pref = _G.PreferredGrapple
    if pref and pref ~= "" then
        local out = { pref }
        for _, n in ipairs(_ALL_GRAPPLE_NAMES) do
            if n ~= pref then out[#out+1] = n end
        end
        return out
    end
    return _ALL_GRAPPLE_NAMES
end

local function findTool(name)
    local char = LP.Character
    local bp   = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end

local function findGrapple()
    for _, n in ipairs(GRAPPLE_NAMES()) do
        local t = findTool(n)
        if t and t:IsA("Tool") then return t, n end
    end
    return nil
end

local function equipCarpet()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    for _, n in ipairs(CARPET_NAMES()) do
        local t = findTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end

local function carpetEngage()
    if not NetModule then pcall(loadNet) end
    -- Only wait for / equip the grapple tool if the user has it enabled
    if _G.UseGrapple ~= false then
        local preferredGrapple = _G.PreferredGrapple or "Grapple Hook"
        local _t0 = os.clock()
        while not findTool(preferredGrapple) and os.clock() - _t0 < 5 do
            if not NetModule then pcall(loadNet) end
            RunService.Heartbeat:Wait()
        end
        local char = LP.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum then return nil end
        if not char:FindFirstChild(preferredGrapple) then
            local g = findTool(preferredGrapple)
            if g then pcall(function() hum:EquipTool(g) end) end
        end
    end
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    task.wait(0.01)
    -- Find the obfuscated UseItem remote
local function findUseItemRemote()
    local net = game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Net")
    local children = net:GetChildren()
    
    for i, obj in ipairs(children) do
        if obj:IsA("RemoteEvent") and obj.Name ~= "RE/UseItem" then
            -- Check if this remote is paired with RE/UseItem
            local nextIndex = i + 1
            local nextObj = children[nextIndex]
            
            if nextObj and nextObj.Name == "RE/UseItem" then
                print("Found obfuscated UseItem remote:", obj.Name)
                return obj
            end
        end
    end
    
    -- Alternative: Search by pattern (if it follows the pattern)
    for _, obj in ipairs(children) do
        if obj:IsA("RemoteEvent") and obj.Name:match("^RE/[a-f0-9]+$") then
            -- Check if there's a RE/UseItem nearby
            print("Found potential obfuscated remote:", obj.Name)
            return obj
        end
    end
    
    warn("Could not find obfuscated UseItem remote")
    return nil
end

-- Find and fire the remote
local obfuscatedRemote = findUseItemRemote()

if obfuscatedRemote then
    -- Fire with the value 0.24191250801086
    obfuscatedRemote:FireServer(2)
    print("Fired obfuscated remote with value: 2")
else
    warn("Failed to find obfuscated UseItem remote")
end
    task.wait(0.15)
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h then pcall(function() h:UnequipTools() end) end
    task.wait(0.15)
    local cn
    local _tc = os.clock()
    repeat
        cn = equipCarpet()
        local c = LP.Character
        if cn and c and c:FindFirstChild(cn) then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _tc > 1
    _G.TPEngage = "carpet=" .. tostring(cn)
    return cn
end

-- =====================================================================
-- Plot ownership helpers (PlotSign-based, no Synchronizer)
-- =====================================================================

-- Read the PlotSign label text for a plot instance.
local function _getSignText(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return "" end
    local gui   = sign:FindFirstChildWhichIsA("SurfaceGui", true)
    local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
    return label and label.Text or ""
end

-- True when the sign names the local player (skip our own plot).
local function _isMyPlot(plot)
    local txt = _getSignText(plot):lower()
    if txt == "" then return false end
    return txt:find(LP.Name:lower(), 1, true) ~= nil
        or txt:find(LP.DisplayName:lower(), 1, true) ~= nil
end

-- True when the sign names any player currently in the server.
local function _ownerInGame(plot)
    local txt = _getSignText(plot):lower()
    if txt == "" or txt == "unowned" or txt == "empty" then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if txt:find(p.Name:lower(), 1, true)
        or txt:find(p.DisplayName:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Best-position heuristic for a pet model inside a podium.
local function _getPetPos(item)
    for _, desc in ipairs(item:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
            local hasMesh = false
            for _, c in ipairs(desc:GetDescendants()) do
                if c:IsA("MeshPart") then hasMesh = true; break end
            end
            if hasMesh then
                local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                if ok then return cf.Position end
            end
        end
    end
    local primary = item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true))
    return primary and primary.Position
end

-- =====================================================================
-- Pet name / priority helpers + workspace scan
-- =====================================================================

local function _priOf(name)
    local list = _G.SHARED_PRIORITY_ITEMS
    if type(list) ~= "table" or not name then return math.huge end
    local target = _normName(name)
    for i, entry in ipairs(list) do
        if _normName(entry) == target then return i end
    end
    return math.huge
end

-- =====================================================================
-- Workspace GUI cache (built once per scan pass to avoid repeated
-- workspace:GetDescendants() calls inside _getMoneyValue per item)
-- =====================================================================
local _wsGuiCache = nil

local function _buildWsGuiCache()
    _wsGuiCache = {}
    for _, bb in ipairs(workspace:GetDescendants()) do
        if bb:IsA("BillboardGui") or bb:IsA("SurfaceGui") then
            _wsGuiCache[#_wsGuiCache + 1] = bb
        end
    end
    -- Also pull PlayerGui GUIs into the same cache so _getMoneyValue
    -- never calls GetDescendants on pgui per-pet during a scan pass.
    local pgui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if pgui then
        for _, bb in ipairs(pgui:GetDescendants()) do
            if (bb:IsA("BillboardGui") or bb:IsA("SurfaceGui")) and bb.Adornee then
                _wsGuiCache[#_wsGuiCache + 1] = bb
            end
        end
    end
end

-- Recursively scan a container for animal models.
-- Inline money lookup (no task.spawn per pet -- that floods the scheduler).
-- Yields after every matched pet so the frame budget is never blown in one burst.
local function _scanContainer(container, plotName, slotName, out, depth)
    depth = depth or 0
    if depth > 6 then return end
    local children = container:GetChildren()
    for _, item in ipairs(children) do
        if _isBlacklisted(item.Name) then continue end

        if item:IsA("Model") or item:IsA("BasePart") then
            local pos = _getPetPos(item) or (item:IsA("BasePart") and item.Position)
            if pos then
                local value, rawText = _getMoneyValue(item)
                out[#out + 1] = {
                    name     = item.Name,
                    index    = item.Name,
                    mps      = value or 0,
                    rawText  = rawText,
                    mutation = "None",
                    position = pos,
                    plot     = plotName,
                    slot     = slotName or container.Name,
                }
                task.wait()
            end
            -- ✅ FIX: Don't recurse into models anymore
            -- Just skip going inside - we already have what we need
        end
        -- ✅ FIX: Don't scan folders/configs either
        -- The pet models are directly in the plot/podium, not in folders
    end
end

local function scanAllPets()
    local pets  = {}
    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then
        warn("[Von] workspace.Plots not found — scanner returning empty")
        return pets
    end

    -- Build the workspace GUI cache ONCE for the whole scan pass.
    -- This prevents _getMoneyValue from calling workspace:GetDescendants() per item.
    _buildWsGuiCache()

    local plotCount, skippedOwn, skippedNoOwner = 0, 0, 0
    for _, plot in ipairs(Plots:GetChildren()) do
        if not plot:IsA("Instance") then continue end

        if _isMyPlot(plot) then
            skippedOwn = skippedOwn + 1
            continue
        end

        -- _ownerInGame check is kept but non-fatal: if PlotSign text is empty or
        -- unreadable we still scan (avoids silent skip when sign text hasn't loaded yet)
        local ownerPresent = _ownerInGame(plot)
        if not ownerPresent then
            -- Check sign text; if blank the sign may not have loaded — scan anyway
            local signTxt = _getSignText(plot)
            if signTxt ~= "" and signTxt:lower() ~= "unowned" and signTxt:lower() ~= "empty" then
                skippedNoOwner = skippedNoOwner + 1
                continue
            end
            -- sign blank → fall through and scan
        end

        plotCount = plotCount + 1
        _scanContainer(plot, plot.Name, nil, pets, 0)
    end

    _wsGuiCache = nil  -- release cache so stale workspace refs don't linger

    print(string.format("[Von] Scan done: %d plots scanned, %d own, %d no-owner-skipped, %d pets found",
        plotCount, skippedOwn, skippedNoOwner, #pets))

    -- Sort: user priority list first, then highest mps/value
    local _priLk = {}
    local plist  = _G.SHARED_PRIORITY_ITEMS
    if type(plist) == "table" then
        for i = #plist, 1, -1 do _priLk[_normName(plist[i])] = i end
    end
    for _, p in ipairs(pets) do
        p._pri = math.min(_priLk[_normName(p.name)] or math.huge,
                          _priLk[_normName(p.index)] or math.huge)
    end
    table.sort(pets, function(a, b)
        if a._pri ~= b._pri then return a._pri < b._pri end
        return (a.mps or 0) > (b.mps or 0)
    end)
    return pets
end

-- =====================================================================
-- Sky platform coordinate tables + constants
-- =====================================================================
local UPPER = {
    B = {
        {coord=Vector3.new(-487.921448,16.850713,-75.768013), facing="NORTH"},
        {coord=Vector3.new(-332.379730,16.850722,-75.762100), facing="NORTH"},
        {coord=Vector3.new(-487.134918,16.850713,-18.094154), facing="SOUTH"},
        {coord=Vector3.new(-316.300171,16.850713,-17.845898), facing="SOUTH"},
    },
    C = {
        {coord=Vector3.new(-330.765381,16.850713,31.424425), facing="NORTH"},
        {coord=Vector3.new(-502.989349,16.850713,31.172430), facing="NORTH"},
        {coord=Vector3.new(-489.077087,16.850713,89.010147), facing="SOUTH"},
        {coord=Vector3.new(-330.908936,16.850713,88.930145), facing="SOUTH"},
    },
    D = {
        {coord=Vector3.new(-331.264893,16.850713,138.209167), facing="NORTH"},
        {coord=Vector3.new(-487.935181,16.850713,138.026321), facing="NORTH"},
        {coord=Vector3.new(-487.774933,16.850713,195.882538), facing="SOUTH"},
        {coord=Vector3.new(-330.799133,16.850575,196.022354), facing="SOUTH"},
    },
}
local LOWER = {
    B = {
        {coord=Vector3.new(-335.725586,-3.048217,-74.984589), facing="NORTH"},
        {coord=Vector3.new(-503.214233,-3.048217,-75.043137), facing="NORTH"},
        {coord=Vector3.new(-483.619385,-3.718430,-18.844337), facing="SOUTH"},
        {coord=Vector3.new(-316.147095,-3.048218,-18.818844), facing="SOUTH"},
    },
    C = {
        {coord=Vector3.new(-335.985413,-3.048218,32.051426), facing="NORTH"},
        {coord=Vector3.new(-503.277008,-3.048217,31.956175), facing="NORTH"},
        {coord=Vector3.new(-483.749390,-3.048218,88.147003), facing="SOUTH"},
        {coord=Vector3.new(-315.793823,-3.048217,88.163979), facing="SOUTH"},
    },
    D = {
        {coord=Vector3.new(-335.476654,-3.048218,139.001083), facing="NORTH"},
        {coord=Vector3.new(-503.710083,-3.048218,138.989883), facing="NORTH"},
        {coord=Vector3.new(-315.654938,-3.048218,195.302444), facing="SOUTH"},
        {coord=Vector3.new(-483.859253,-3.048218,195.269043), facing="SOUTH"},
    },
}
local UPPER_Y_THRESHOLD = 7
local TALL_PETS   = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
local TALL_OFFSET = 3

local BASES_LOW = {
    [1]=Vector3.new(-476.52,-2,220.94090270996094), [2]=Vector3.new(-476.52,-2,113.77315521240234),
    [3]=Vector3.new(-476.52,-2,6.178487777709961),  [4]=Vector3.new(-476.52,-2,-101.07275390625),
    [5]=Vector3.new(-342.66,-2,221.44737243652344), [6]=Vector3.new(-342.66,-2,113.41409301757812),
    [7]=Vector3.new(-342.66,-2,6.249461650848389),  [8]=Vector3.new(-342.66,-2,-99.73458862304688),
}
local BASES_HIGH = {
    [1]=Vector3.new(-479.51,18,220.94090270996094), [2]=Vector3.new(-479.51,18,113.77315521240234),
    [3]=Vector3.new(-479.51,18,6.178487777709961),  [4]=Vector3.new(-479.51,18,-101.07275390625),
    [5]=Vector3.new(-339.48,18,221.44737243652344), [6]=Vector3.new(-339.48,18,113.41409301757812),
    [7]=Vector3.new(-339.48,18,6.249461650848389),  [8]=Vector3.new(-339.48,18,-99.73458862304688),
}
local FRONT_Y_LOW    = -3.048217
local FRONT_Y_HIGH   = 16.850713
local COLUMN_SPLIT_X = -410
local FRONT_Z_CLAMP  = 18
local SIDE_NEAR_Z    = 45

local function getClosestBaseIdx(pos)
    local closest, dist = 1, math.huge
    for i = 1, 8 do
        local b = BASES_LOW[i]
        local d = (pos.X - b.X)^2 + (pos.Z - b.Z)^2
        if d < dist then dist = d; closest = i end
    end
    return closest
end

local function buildFrontCandidate(idx, isUpper, playerZ)
    local base   = isUpper and BASES_HIGH[idx] or BASES_LOW[idx]
    local frontY = isUpper and FRONT_Y_HIGH or FRONT_Y_LOW
    local frontZ = math.clamp(playerZ - base.Z, -FRONT_Z_CLAMP, FRONT_Z_CLAMP) + base.Z
    local coord  = Vector3.new(base.X, frontY, frontZ)
    local faceDir = (idx <= 4) and Vector3.new(-1, 0, 0) or Vector3.new(1, 0, 0)
    return coord, faceDir
end

local function plotSides(coordTable, idx)
    local base   = BASES_LOW[idx]
    local isWest = idx <= 4
    local out = {}
    for _, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            if ((data.coord.X < COLUMN_SPLIT_X) == isWest)
               and math.abs(data.coord.Z - base.Z) < SIDE_NEAR_Z then
                out[#out + 1] = data
            end
        end
    end
    return out
end

local function _floor1LaserSolid(plotName)
    local solid = false
    pcall(function()
        local Plots = workspace:FindFirstChild("Plots")
        local plot  = Plots and Plots:FindFirstChild(plotName)
        if not plot then return end
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name == "LaserHitbox" or d.Name == "Laser")
               and d.CanCollide and d.Position.Y <= 9 then
                solid = true; break
            end
        end
    end)
    return solid
end

local function isPlotUnlocked(plotName)
    local ok, res = pcall(function()
        local channel = getPlotChannel(plotName)
        if not channel then return false end
        if channelGet(channel, "BlockEndTimeFirstFloor") ~= nil then return false end
        return not _floor1LaserSolid(plotName)
    end)
    return ok and (res == true)
end

local function findClosest(petPos, coordTable)
    local best, bestKey, bestDist = nil, nil, math.huge
    for skyKey, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            local c = data.coord
            local d = math.sqrt((petPos.X - c.X)^2 + (petPos.Z - c.Z)^2)
            if d < bestDist then bestDist = d; best = data; bestKey = skyKey end
        end
    end
    return best, bestKey
end

-- =====================================================================
-- Path viz (thin debug parts)
-- =====================================================================
local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end

-- =====================================================================
-- Raycast / route helpers
-- =====================================================================
local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _STRUCT = { ["structure base home"]=true, ["Wall"]=true, ["Floor"]=true, ["Roof"]=true }
local _SKIP_NAME = {
    DeliveryHitbox=true, StealHitbox=true, LaserHitbox=true,
    AnimalTarget=true,   Multiplier=true,  Laser=true,
    Hitbox=true,         Spawn=true,       MainRoot=true,
    SecondFloor=true,    ThirdFloor=true,  Slope=true,
}

local function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    if s and math.max(s.X*s.Y, s.X*s.Z, s.Y*s.Z) > 150 then return true end
    return false
end
local function _blocksWide(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    if s and math.max(s.X*s.Y, s.X*s.Z, s.Y*s.Z) > 30 then return true end
    return false
end

local function _block(origin, target, blockFn)
    blockFn = blockFn or _blocks
    local rp = RaycastParams.new()
    rp.FilterType   = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater  = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip+1] = pl.Character end
    end
    local o = origin
    for _ = 1, 16 do
        rp.FilterDescendantsInstances = skip
        local d = target - o
        if d.Magnitude < 0.05 then return nil end
        local res = workspace:Raycast(o, d, rp)
        if not res then return nil end
        if blockFn(res.Instance) then return res end
        skip[#skip+1] = res.Instance
        o = res.Position + d.Unit * 0.3
    end
    return nil
end

local function _clear(a, b) return _block(a, b) == nil end
local function _clearDist(origin, dir, maxD)
    local res = _block(origin, origin + dir.Unit * maxD)
    if not res then return maxD end
    return (res.Position - origin).Magnitude
end
local function _len(pts)
    local s, prev = 0, pts[1]
    for k = 2, #pts do s = s + (pts[k]-prev).Magnitude; prev = pts[k] end
    return s
end
local function _pullWide(pts)
    -- (string-pull: skip intermediate points when line of sight is clear)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i, n = 1, #pts
    while i < n do
        local j = n
        while j > i+1 and not _clear(out[#out], pts[j]) do j = j-1 end
        out[#out+1] = pts[j]; i = j
    end
    return out
end

local _CLEARANCE      = 16
local _SWEEP_R        = 4
local _ENDPOINT_SLACK = 6
local _canSphere      = nil

local function _sweepDir(a, b)
    local rp = RaycastParams.new()
    rp.FilterType  = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip+1] = pl.Character end
    end
    local o = a
    for _ = 1, 24 do
        rp.FilterDescendantsInstances = skip
        local d = b - o
        if d.Magnitude < 0.05 then return false end
        local res
        local ok = pcall(function() res = workspace:Spherecast(o, _SWEEP_R, d, rp) end)
        if not ok then _canSphere = false; return nil end
        if not res then return false end
        if _blocks(res.Instance) then return true end
        skip[#skip+1] = res.Instance
        local adv = (res.Distance or 0) - 0.05
        if adv > 0 then o = o + d.Unit * math.min(adv, d.Magnitude) end
    end
    return true
end
local function _sweepBlocked(a, b, slackA, slackB)
    if _canSphere == nil then
        _canSphere = pcall(function()
            workspace:Spherecast(Vector3.new(0,10000,0), 1, Vector3.new(0,-1,0), RaycastParams.new())
        end)
    end
    if not _canSphere then return nil end
    local d   = b - a
    local len = d.Magnitude
    if len < 0.1 then return false end
    local u  = d / len
    local a2 = a + u * math.min(slackA or _ENDPOINT_SLACK, len * 0.4)
    local b2 = b - u * math.min(slackB or _ENDPOINT_SLACK, len * 0.4)
    local fwd = _sweepDir(a2, b2)
    if fwd == nil then return nil end
    if fwd then return true end
    local rev = _sweepDir(b2, a2)
    if rev == nil then return nil end
    return rev
end
local function _clearWide(a, b, slackA, slackB)
    if not _clear(a, b) then return false end
    local sw = _sweepBlocked(a, b, slackA, slackB)
    if sw ~= nil then return not sw end
    local d = Vector3.new(b.X-a.X, 0, b.Z-a.Z)
    if d.Magnitude < 0.1 then
        local ox = Vector3.new(_CLEARANCE,0,0)
        local oz = Vector3.new(0,0,_CLEARANCE)
        return _clear(a+ox, b+ox) and _clear(a-ox, b-ox)
           and _clear(a+oz, b+oz) and _clear(a-oz, b-oz)
    end
    local perp = Vector3.new(-d.Z,0,d.X).Unit * _CLEARANCE
    local up   = Vector3.new(0,_CLEARANCE,0)
    return _clear(a+perp, b+perp) and _clear(a-perp, b-perp)
       and _clear(a+up,   b+up)   and _clear(a-up,   b-up)
end

local function _pushOffWalls(pts)
    if #pts <= 2 then return pts end
    local MARGIN, MAX_PUSH = 8, 12
    local out = { pts[1] }
    for i = 2, #pts-1 do
        local p     = pts[i]
        local shift = Vector3.zero
        for _, dr in ipairs(_DIRS) do
            local res = _block(p, p + dr*MARGIN, _blocks)
            if res then
                local dist = (res.Position - p).Magnitude
                if dist < MARGIN then shift = shift - dr*(MARGIN-dist) end
            end
        end
        local resUp = _block(p, p + Vector3.new(0,MARGIN,0), _blocks)
        if resUp then
            local dist = (resUp.Position - p).Magnitude
            if dist < 4 then shift = shift + Vector3.new(0, -(4-dist), 0) end
        end
        if shift.Magnitude > 0.1 then
            if shift.Magnitude > MAX_PUSH then shift = shift.Unit * MAX_PUSH end
            local moved = p + shift
            if _clear(out[#out], moved) then out[#out+1] = moved else out[#out+1] = p end
        else
            out[#out+1] = p
        end
    end
    out[#out+1] = pts[#pts]
    return out
end

local function computeRoute(fromPos, toPos, facingDir, maxLift)
    maxLift = maxLift or 44
    if _clearWide(fromPos, toPos) then return { toPos } end
    local entry = facingDir and (toPos - facingDir*14) or toPos

    local best, bestLen = nil, math.huge
    local function consider(pts)
        if not pts or #pts < 2 then return end
        local n = #pts
        for i = 1, n-1 do
            local a, b = pts[i], pts[i+1]
            if (a-b).Magnitude > 0.5 then
                local sA = (i==1)   and _ENDPOINT_SLACK or 0
                local sB = (i==n-1) and _ENDPOINT_SLACK or 0
                if not _clearWide(a, b, sA, sB) then return end
            end
        end
        local pulled = _pullWide(pts)
        local L = _len(pulled)
        if L < bestLen then best, bestLen = pulled, L end
    end

    -- Arc routes (diagonal rise)
    do
        local baseY = math.max(fromPos.Y, entry.Y)
        local mid   = (fromPos + entry) * 0.5
        for _, lift in ipairs({ 10, 16, 24, 34, maxLift }) do
            if lift <= maxLift then
                local cy        = baseY + lift
                local apexMid   = Vector3.new(mid.X,   cy, mid.Z)
                local apexEntry = Vector3.new(entry.X,  cy, entry.Z)
                consider({ fromPos, apexMid,   entry })
                consider({ fromPos, apexEntry, entry })
                consider({ fromPos, apexMid,   apexEntry, entry })
            end
        end
    end

    -- Right-angle over-the-top routes
    do
        local baseY = math.max(fromPos.Y, entry.Y)
        for _, lift in ipairs({ 14, 22, 32, maxLift }) do
            if lift <= maxLift then
                local cy = baseY + lift
                consider({ fromPos,
                    Vector3.new(fromPos.X, cy, fromPos.Z),
                    Vector3.new(entry.X,   cy, entry.Z),
                    entry })
            end
        end
    end

    -- Lateral side-step routes
    do
        local dirF = Vector3.new(entry.X-fromPos.X, 0, entry.Z-fromPos.Z)
        if dirF.Magnitude > 0.1 then
            dirF = dirF.Unit
            local perp    = Vector3.new(-dirF.Z, 0, dirF.X)
            local midBase = (fromPos + entry) * 0.5
            for _, off in ipairs({ 14, -14, 24, -24, 38, -38 }) do
                consider({ fromPos, midBase + perp*off, entry })
                consider({ fromPos, fromPos + perp*off, entry + perp*off, entry })
            end
        end
    end

    -- NavMesh fallback
    local navRaw
    do
        local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
        local path     = PathfindingService:CreatePath({
            AgentRadius=16, AgentHeight=5, AgentCanJump=true, AgentJumpHeight=10, AgentMaxSlope=89,
        })
        local FLOAT = 5
        local nav   = { fromPos }
        local ok    = pcall(function()
            path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
        end)
        if ok and path.Status == Enum.PathStatus.Success then
            local last = fromPos
            for _, wp in ipairs(path:GetWaypoints()) do
                if (wp.Position - last).Magnitude >= 8 then
                    nav[#nav+1] = wp.Position + Vector3.new(0, FLOAT, 0)
                    last = wp.Position
                end
            end
        end
        nav[#nav+1] = entry + Vector3.new(0, FLOAT, 0)
        nav = _pushOffWalls(nav)
        navRaw = nav
        consider(nav)
    end

    local route = best
    if not route and _clear(fromPos, toPos) then route = { toPos } end
    if not route then route = _pullWide(navRaw) end
    if (route[#route] - toPos).Magnitude > 0.5 then route[#route+1] = toPos end
    return route
end

-- =====================================================================
-- LinearVelocity driver
-- =====================================================================
local SPEED  = 125
local ARRIVE = 3
local _tpLVAtt, _tpLV

local function lvDrive(hrp, v)
    if not hrp or not hrp.Parent then return end
    if not (_tpLV and _tpLV.Parent and _tpLVAtt and _tpLVAtt.Parent == hrp) then
        if _tpLV then pcall(function() _tpLV:Destroy() end) end
        if _tpLVAtt then pcall(function() _tpLVAtt:Destroy() end) end
        _tpLVAtt = Instance.new("Attachment")
        _tpLVAtt.Name = "VonTPAtt"
        _tpLVAtt.Parent = hrp
        _tpLV = Instance.new("LinearVelocity")
        _tpLV.Name = "VonTPLV"
        _tpLV.Attachment0 = _tpLVAtt
        _tpLV.RelativeTo = Enum.ActuatorRelativeTo.World
        pcall(function() _tpLV.ForceLimitsEnabled = false end)
        _tpLV.MaxForce = math.huge
        _tpLV.VectorVelocity = Vector3.zero
        _tpLV.Parent = hrp
    end
    _tpLV.VectorVelocity = v
end
local function lvStop(hrp)
    if _tpLV then pcall(function() _tpLV:Destroy() end); _tpLV = nil end
    if _tpLVAtt then pcall(function() _tpLVAtt:Destroy() end); _tpLVAtt = nil end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end
local function vZero(hrp) lvStop(hrp) end

local function _climbCap()
    return tonumber(_G.VonClimb) or 200
end

-- =====================================================================
-- Velocity mover (gradual flight along waypoints)
-- =====================================================================
local function velMoveThrough(hrp, waypoints, speedOverride, allowJump, quickStart)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    local _runSpeed = speedOverride or tonumber(_G.TPVelocity) or CARPET_SPEED
    local wpIdx = 1
    local done  = false
    local conn

    local function finish()
        if done then return end; done = true
        if hrp and hrp.Parent then
            lvStop(hrp)
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
    end
    local function cancelStop()
        if done then return end; done = true
        if hrp and hrp.Parent then lvStop(hrp) end
        if conn then conn:Disconnect() end
    end

    local lastDist, stall = math.huge, 0

    -- pre-jump if any waypoint is higher than start
    do
        local peak = hrp.Position.Y
        for _, wp in ipairs(waypoints) do if wp.Y > peak then peak = wp.Y end end
        if peak > hrp.Position.Y + 3 then
            local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                pcall(function() hum.Jump = true end)
            end
        end
    end

    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end; return
        end
        if _G.VonTPCancel then cancelStop(); return end
        equipCarpet()

        local target = waypoints[wpIdx]
        local diff   = target - hrp.Position
        local mag    = diff.Magnitude
        local _spd   = _runSpeed

        if wpIdx < #waypoints and mag < 26 then
            local nxt = waypoints[wpIdx+1]
            local b   = nxt - target
            if mag > 0.1 and b.Magnitude > 0.1 and diff.Unit:Dot(b.Unit) < 0.9 then
                _spd = math.min(_spd, 240)
            end
        end

        local _arr = math.max(ARRIVE, _spd/60 * 1.25)
        if mag < _arr then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish(); return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff   = target - hrp.Position
            mag    = diff.Magnitude
        end

        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish(); return end

        if mag >= 0.1 then
            local dir = diff.Unit
            if (allowJump or diff.Y > 10) and diff.Y > 5 and wpIdx < #waypoints then
                local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
                if hum then
                    local st = hum:GetState()
                    if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                        pcall(function() hum.Jump = true end)
                    end
                end
            end
            local _sp  = _spd
            local _mc  = _climbCap()
            if dir.Y > 0 and dir.Y * _sp > _mc then _sp = _mc / dir.Y end
            lvDrive(hrp, Vector3.new(dir.X*_sp, dir.Y*_sp, dir.Z*_sp))
        end
    end)

    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do
        totalDist = totalDist + (prev - wp).Magnitude; prev = wp
    end
    local timeout = totalDist / math.min(SPEED, _runSpeed) + 2
    local elapsed = 0
    while not done and elapsed < timeout do
        task.wait(0.05); elapsed = elapsed + 0.05
        if _G.VonTPCancel then break end
    end
    if _G.VonTPCancel then cancelStop() else finish() end
    vZero(hrp)
end

-- =====================================================================
-- Instant CFrame hop along a route (teleport mode)
-- =====================================================================
local function teleportThrough(hrp, route)
    if not hrp or not hrp.Parent or not route or #route == 0 then return end
    local _last = hrp.Position
    for _, wp in ipairs(route) do
        if not hrp or not hrp.Parent then break end
        if _G.VonTPCancel then break end
        local _face = wp - _last
        if _face.Magnitude < 0.1 then _face = Vector3.new(0,0,1) end
        hrp.CFrame = CFrame.new(wp, wp + _face)
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        local stable = 0
        for _ = 1, 12 do
            if not hrp or not hrp.Parent then break end
            if _G.VonTPCancel then break end
            local flat = (Vector3.new(hrp.Position.X,0,hrp.Position.Z) - Vector3.new(wp.X,0,wp.Z)).Magnitude
            if flat <= 2.5 and math.abs(hrp.Position.Y - wp.Y) <= 3 then
                stable = stable + 1
                if stable >= 3 then break end
            else
                stable = 0
                pcall(function() hrp.CFrame = CFrame.new(wp, wp + _face) end)
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
        _last = wp
    end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

-- =====================================================================
-- Clone swap (Quantum Cloner)
-- =====================================================================
local function findQuantumClonerRemote()
    local net = game:GetService("ReplicatedStorage")
        :WaitForChild("Packages")
        :WaitForChild("Net")
    local children = net:GetChildren()
    for i, obj in ipairs(children) do
        if obj:IsA("RemoteEvent")
        and obj.Name ~= "RE/QuantumCloner/OnTeleport"
        and children[i + 1]
        and children[i + 1].Name == "RE/QuantumCloner/OnTeleport" then
            print("Found obfuscated QuantumCloner remote:", obj.Name)
            return obj
        end
    end
    for _, obj in ipairs(children) do
        if obj:IsA("RemoteEvent") and obj.Name:match("^RE/%x+$") then
            print("Found potential obfuscated remote:", obj.Name)
            return obj
        end
    end
    warn("Could not find obfuscated QuantumCloner remote")
end

local function doClone()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then
        warn("[Von] doClone: no character/humanoid")
        return false
    end

    local cloner = (LP:FindFirstChild("Backpack") and LP.Backpack:FindFirstChild("Quantum Cloner"))
                or char:FindFirstChild("Quantum Cloner")
    if not cloner then
        warn("[Von] doClone: Quantum Cloner not found in Backpack or Character")
        return false
    end

    -- Equip, wait 1 frame, activate, wait 0.05, then fire
    pcall(function() hum:EquipTool(cloner) end)
    RunService.Heartbeat:Wait()

    local root = char:WaitForChild("HumanoidRootPart")
    root.CFrame = root.CFrame + (root.CFrame.LookVector * 3)
    pcall(function() cloner:Activate() end)
    task.wait(0.05)

    local method = _G.VonCloneMethod or "firesignal"

    if method == "remote" then
        local remote = findQuantumClonerRemote()
        if not remote then
            warn("[Von] doClone: could not find QuantumCloner remote")
            return false
        end
        pcall(function() remote:FireServer() end)
    else
        local ok, err = pcall(function()
            local button = LP.PlayerGui.ToolsFrames.QuantumCloner.TeleportToClone
            firesignal(button.MouseButton1Down)
            firesignal(button.MouseButton1Up)
        end)
        if not ok then
            warn("[Von] doClone: firesignal failed —", err)
            return false
        end
    end

    task.wait(0.3)
    return true
end

-- =====================================================================
-- goToBrainrot: move onto the pet after the clone (reference script implementation)
-- =====================================================================
local function goToTarget(petPos)
    if not petPos then return end
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    pcall(function() hrp.Anchored = false end)
    equipCarpet()

    local h = petPos.Y
    local targetY = hrp.Position.Y
    if h > 23.15 then targetY = 21
    elseif h >= 11 and h <= 23.15 then targetY = 14.5
    elseif h >= -6.9 and h <= 8.9 then targetY = -4 end

    local _to = Vector3.new(petPos.X, targetY, petPos.Z)

    -- Temp platform so we don't fall off
    local plat = Instance.new("Part")
    plat.Name = "VonTempPlatform"
    plat.Size = Vector3.new(8, 1, 8)
    plat.Position = Vector3.new(petPos.X, _to.Y - 4, petPos.Z)
    plat.Anchored = true; plat.CanCollide = false
    pcall(makeOneWay, plat)
    plat.Transparency = 1
    plat.Parent = workspace
    task.spawn(function()
        local s = tick()
        while tick() - s < 20 do
            if LP:GetAttribute("Stealing") then break end
            task.wait(0.1)
        end
        if plat and plat.Parent then plat:Destroy() end
    end)

    local _route = computeRoute(hrp.Position, _to, nil, 12)
    if not _route or #_route == 0 then _route = { _to } end
    teleportThrough(hrp, _route)

    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

-- =====================================================================
-- Main entry: doVelocityTP
-- =====================================================================
-- =====================================================================
-- Auto Steal engine (ported from reference script)
-- =====================================================================
local StealCache     = {}
local STEAL_HOLD_MIN = 1.3

local SXE_StealStatus = {
    active = false, target = nil, start = 0,
    duration = STEAL_HOLD_MIN, phase = "idle",
    lastResult = "", lastResultTime = 0,
}

local function findStealPrompt(pet)
    -- First try: navigate AnimalPodiums by slot name (works if slot is a numeric podium key)
    if pet.plot and pet.slot then
        local plots  = workspace:FindFirstChild("Plots")
        local plot   = plots and plots:FindFirstChild(pet.plot)
        local pods   = plot and plot:FindFirstChild("AnimalPodiums")
        local podium = pods and pods:FindFirstChild(tostring(pet.slot))
        if podium then
            local base   = podium:FindFirstChild("Base")
            local spwn   = base and base:FindFirstChild("Spawn")
            local attach = spwn and spwn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") then return p end
                end
            end
            for _, d in ipairs(podium:GetDescendants()) do
                if d:IsA("ProximityPrompt") then return d end
            end
        end

        -- Second try: scan all podiums in this plot for the nearest one to pet.position
        if pods and pet.position then
            local best, bestDist = nil, math.huge
            for _, pod in ipairs(pods:GetChildren()) do
                local ok, cf = pcall(function() return pod:GetPivot() end)
                if ok and cf then
                    local dist = (cf.Position - pet.position).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        best = pod
                    end
                end
            end
            if best then
                for _, d in ipairs(best:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then return d end
                end
            end
        end
    end

    -- Last resort: nearest ProximityPrompt in workspace to pet.position
    if pet.position then
        local best, bestDist = nil, math.huge
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                local part = obj.Parent
                if part and part:IsA("BasePart") then
                    local dist = (part.Position - pet.position).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        best = obj
                    end
                end
            end
        end
        return best
    end

    return nil
end

local function firePromptConnections(prompt, signalName)
    local ok, conns = pcall(getconnections, prompt[signalName])
    if ok and type(conns) == "table" then
        for _, conn in ipairs(conns) do
            if type(conn.Function) == "function" then
                task.spawn(conn.Function)
            end
        end
    end
end

local function executeSteal(prompt)
    if not prompt or not prompt.Parent then return false end
    if SXE_StealStatus.active then return false end
    SXE_StealStatus.active = true
    SXE_StealStatus.start  = tick()
    SXE_StealStatus.duration = STEAL_HOLD_MIN
    SXE_StealStatus.phase  = "holding"
    print("[Von] executeSteal: hold start")
    task.spawn(function()
        firePromptConnections(prompt, "PromptButtonHoldBegan")
        task.wait(STEAL_HOLD_MIN)
        print("[Von] executeSteal: triggering")
        firePromptConnections(prompt, "Triggered")
        firePromptConnections(prompt, "PromptButtonHoldEnded")
        SXE_StealStatus.active = false
        SXE_StealStatus.phase  = "idle"
        SXE_StealStatus.lastResult = "Stolen!"
        SXE_StealStatus.lastResultTime = tick()
    end)
    return true
end

-- Heartbeat: fire steal once when within 130 studs of target
local _lastStealTick = 0
local _lastStealTarget = nil
RunService.Heartbeat:Connect(function()
    if LP:GetAttribute("Stealing") then return end
    local now = tick()
    if now - _lastStealTick < 0.067 then return end
    _lastStealTick = now

    if not _G.VonAutoSteal then return end
    if SXE_StealStatus.active then return end

    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local pet = SXE_StealStatus.target
    if not pet then return end

    -- Only fire once per target
    if _lastStealTarget == pet then return end

    if not pet.position then return end
    local dist = (hrp.Position - pet.position).Magnitude
    if dist > 10 then return end

    local prompt = findStealPrompt(pet)
    if not prompt or not prompt.Parent then return end

    print(string.format("[Von] Heartbeat: within %.1f studs of '%s', starting steal", dist, tostring(pet.name)))
    print(string.format("[Von] Heartbeat: prompt ActionText='%s' ObjectText='%s' Parent='%s'",
        prompt.ActionText or "", prompt.ObjectText or "",
        prompt.Parent and prompt.Parent.Name or "nil"))

    _lastStealTarget = pet  -- mark as fired so we don't repeat

    local oldMax
    pcall(function() oldMax = prompt.MaxActivationDistance end)
    pcall(function() prompt.MaxActivationDistance = math.huge end)
    executeSteal(prompt)
    pcall(function() if oldMax then prompt.MaxActivationDistance = oldMax end end)
end)

-- Called post-teleport: just sets the target — heartbeat loop handles the rest
local function doAutoSteal(pet)
    if not _G.VonAutoSteal then return end
    if not pet then return end
    SXE_StealStatus.target = pet
end

local isTeleporting = false

local function doVelocityTP()
    if isTeleporting then return end
    isTeleporting = true
    _G.VonTPCancel = false
    if not _G.VonTPStartedAt then _G.VonTPStartedAt = os.clock() end
    clearViz()
    if not NetModule then pcall(loadNet) end

    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then isTeleporting = false; return end

    -- Scan + wait for pets
    local allPets = scanAllPets()
    if #allPets == 0 then
        local _t0 = os.clock()
        while #allPets == 0 and os.clock() - _t0 < 4 do
            if _G.VonTPCancel then isTeleporting = false; return end
            task.wait(0.15)
            allPets = scanAllPets()
        end
    end
    if #allPets == 0 then
        warn("[Von] No pets found after scan — nothing to teleport to")
        isTeleporting = false; return
    end
    if _G.VonTPCancel then isTeleporting = false; return end

    -- Target selection
    local pet = allPets[1]
    do
        local overrideUID = _G.VonStealTargetUID
        local overridePet = nil
        if overrideUID then
            for _, p in ipairs(allPets) do
                if (tostring(p.plot) .. "|" .. tostring(p.slot)) == overrideUID then
                    overridePet = p; break
                end
            end
            if not overridePet then _G.VonStealTargetUID = nil end
        end
        local mode = _G.VonStealMode
        if overridePet then
            pet = overridePet
        elseif mode == "highest" then
            local best = allPets[1]
            for _, p in ipairs(allPets) do
                if (p.mps or 0) > (best.mps or 0) then best = p end
            end
            pet = best
        else
            -- Priority mode: pick the top-ranked pet from the priority list.
            -- allPets is already sorted by _pri then mps, so allPets[1] is
            -- the best priority match. If nothing matched the list (_pri == math.huge)
            -- fall back to highest mps instead.
            local best = allPets[1]
            if best._pri == math.huge then
                -- No priority list match — fall back to highest value
                for _, p in ipairs(allPets) do
                    if (p.mps or 0) > (best.mps or 0) then best = p end
                end
            end
            pet = best
        end
    end

    local petPos  = pet.position
    local petName = pet.name
    _G._VonSelectedPet = { slot = pet.slot, name = pet.name, plot = pet.plot }

    -- Set steal target now so heartbeat starts holding as soon as we're within 130 studs during approach
    SXE_StealStatus.target = pet
    _lastStealTarget = nil  -- allow heartbeat to fire for this new target

    -- Min value filter
    local _minVal = tonumber(_G.VonMinValue) or 0
    if _minVal > 0 and (pet.mps or 0) < _minVal then
        warn(string.format("[Von] Best pet '%s' value ($%.0f/s) is below minimum ($%.0f/s) — skipping", petName, pet.mps or 0, _minVal))
        UILib.ShowNotification("Von TP", string.format("Skipped — value $%.0f/s below min", pet.mps or 0))
        isTeleporting = false; return
    end

    local adjY = petPos.Y
    if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
    local coordTable = adjY > UPPER_Y_THRESHOLD and UPPER or LOWER

    -- ── Floor-1 open-base path ──────────────────────────────────────────
    if petPos.Y <= 8.9 and isPlotUnlocked(pet.plot) then
        local maxHP   = hum.MaxHealth
        hum.Health    = maxHP
        local healConn = RunService.Heartbeat:Connect(function()
            if hum and hum.Parent then hum.Health = maxHP end
        end)
        carpetEngage()
        vZero(hrp)
        local _to    = Vector3.new(petPos.X, -4, petPos.Z)
        local route  = computeRoute(hrp.Position, _to, nil)
        if not route or #route == 0 then route = { _to } end
        teleportThrough(hrp, route)
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect()
        isTeleporting = false
        if _G.VonTPCancel then return end
        pcall(function()
            local vim = Instance.new("VirtualInputManager")
            vim:SendKeyEvent(true,  Enum.KeyCode.C, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.C, false, game)
        end)
        return
    end

    -- ── Sky platform path ───────────────────────────────────────────────
    local closestData, skyKey = findClosest(petPos, coordTable)
    if not closestData or not skyKey then isTeleporting = false; return end

    local destPos   = closestData.coord
    local maxHP     = hum.MaxHealth
    hum.Health      = maxHP
    local healConn  = RunService.Heartbeat:Connect(function()
        if hum and hum.Parent then hum.Health = maxHP end
    end)

    local _carpet   = carpetEngage()
    vZero(hrp)

    local facingDir = closestData.facing == "NORTH" and Vector3.new(0,0,-1) or Vector3.new(0,0,1)

    do
        local isUpper                   = (coordTable == UPPER)
        local idx                       = getClosestBaseIdx(petPos)
        local frontCoord, frontFace     = buildFrontCandidate(idx, isUpper, hrp.Position.Z)
        local bestCoord, bestFace       = frontCoord, frontFace
        local bestDist                  = (hrp.Position - frontCoord).Magnitude
        for _, d in ipairs(plotSides(coordTable, idx)) do
            local dd = (hrp.Position - d.coord).Magnitude
            if dd < bestDist then
                bestDist  = dd
                bestCoord = d.coord
                bestFace  = d.facing == "NORTH" and Vector3.new(0,0,-1) or Vector3.new(0,0,1)
            end
        end
        destPos   = bestCoord
        facingDir = bestFace
    end

    local _route = computeRoute(hrp.Position, destPos, facingDir)

    -- Sub-divide steep ascents
    local ASCEND_STEP = 10
    local _stepped = {}
    do
        local prev = hrp.Position
        for _, wp in ipairs(_route) do
            local dy = wp.Y - prev.Y
            if dy > ASCEND_STEP * 1.5 then
                local n = math.ceil(dy / ASCEND_STEP)
                for s = 1, n-1 do
                    local t = s / n
                    _stepped[#_stepped+1] = Vector3.new(
                        prev.X + (wp.X - prev.X) * t,
                        prev.Y + dy * t,
                        prev.Z + (wp.Z - prev.Z) * t
                    )
                end
            end
            _stepped[#_stepped+1] = wp
            prev = wp
        end
    end

    -- Pick travel speed from route length
    local _routeLen = 0
    do
        local prev = hrp.Position
        for _, wp in ipairs(_route) do
            _routeLen = _routeLen + (wp - prev).Magnitude; prev = wp
        end
    end
    local _mainSpeed = (_routeLen < 100) and 200 or (tonumber(_G.TPVelocity) or 400)
    velMoveThrough(hrp, _stepped, _mainSpeed, true, true)

    if _G.VonTPCancel then
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect(); isTeleporting = false; return
    end

    -- Nudge-to-exact-spot loop
    do
        local _t0 = os.clock()
        while os.clock() - _t0 < 4 do
            if not hrp or not hrp.Parent then break end
            if LP:GetAttribute("Stealing") then break end
            if _G.VonTPCancel then break end
            equipCarpet()
            local diff = destPos - hrp.Position
            local mag  = diff.Magnitude
            if mag <= 3 then break end
            lvDrive(hrp, diff.Unit * math.min(400, mag*8))
            hrp.AssemblyAngularVelocity = Vector3.zero
            RunService.Heartbeat:Wait()
        end
        lvStop(hrp)
    end

    if _G.VonTPCancel then
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        healConn:Disconnect(); isTeleporting = false; return
    end

    if hrp and hrp.Parent then
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + facingDir)
    end
    vZero(hrp)

    -- Lock facing for a few frames
    local syncFrames = 5
    local syncConn
    syncConn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
        syncFrames = syncFrames - 1
        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if syncFrames <= 0 then syncConn:Disconnect() end
    end)

    for _ = 1, 20 do
        task.wait(0.05)
        if hum.FloorMaterial ~= Enum.Material.Air then break end
        if _G.VonTPCancel then break end
    end

    healConn:Disconnect()
    isTeleporting = false
    if _G.VonTPCancel then return end

    -- Stability hold
    do
        local stable = 0
        for _ = 1, 50 do
            if _G.VonTPCancel then break end
            local _hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not _hrp or not _hrp.Parent then break end
            local flat = (Vector3.new(_hrp.Position.X,0,_hrp.Position.Z) - Vector3.new(destPos.X,0,destPos.Z)).Magnitude
            if flat <= 3.5 and math.abs(_hrp.Position.Y - destPos.Y) <= 4 then
                stable = stable + 1
                if stable >= 4 then break end
            else
                stable = 0
                pcall(function() _hrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                _hrp.AssemblyLinearVelocity  = Vector3.zero
                _hrp.AssemblyAngularVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end
    end
    if _G.VonTPCancel then return end

    -- Clone platform + clone
    local _ahrp      = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local _clonePos  = (_ahrp and _ahrp.Parent and _ahrp.Position) or destPos
    local _clonePlat = Instance.new("Part")
    _clonePlat.Name  = "VonClonePlatform"
    _clonePlat.Size  = Vector3.new(12,1,12)
    _clonePlat.Position  = Vector3.new(_clonePos.X, _clonePos.Y-3, _clonePos.Z)
    _clonePlat.Anchored  = true; _clonePlat.CanCollide = true
    _clonePlat.Transparency = 1
    _clonePlat.Material = Enum.Material.SmoothPlastic
    _clonePlat.Parent   = workspace

    if _ahrp and _ahrp.Parent then
        _ahrp.AssemblyLinearVelocity  = Vector3.zero
        _ahrp.AssemblyAngularVelocity = Vector3.zero
    end

    local _preCloneChar = LP.Character
    local _preClonePos  = ((_preCloneChar and _preCloneChar:FindFirstChild("HumanoidRootPart"))
                           and _preCloneChar.HumanoidRootPart.Position) or destPos

    local _charAdded = false
    local _caConn = LP.CharacterAdded:Connect(function() _charAdded = true end)

    task.wait(tonumber(_G.TPCloneDelay) or tonumber(_G.LandingDelay) or SKY_CLONE_WAIT)

    doClone()
    if _clonePlat then pcall(function() _clonePlat:Destroy() end); _clonePlat = nil end

    do
        local _t0 = os.clock()
        repeat
            if _G.VonTPCancel then break end
            if _charAdded then break end
            if LP.Character ~= _preCloneChar then break end
            local _h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if _h then
                local _dx = _h.Position.X - _preClonePos.X
                local _dz = _h.Position.Z - _preClonePos.Z
                if (_dx*_dx + _dz*_dz) > 4 then break end
            end
            RunService.Heartbeat:Wait()
        until os.clock() - _t0 > 3
    end
    if _caConn then _caConn:Disconnect() end
    if _G.VonTPCancel then return end

    goToTarget(petPos)
    pcall(function()
        local vim = Instance.new("VirtualInputManager")
        vim:SendKeyEvent(true,  Enum.KeyCode.C, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.C, false, game)
    end)

end

-- =====================================================================
-- Expose + clamp defaults (UI may have already set these)
-- =====================================================================
_G.VonStartSideTP = doVelocityTP
_G.TPVelocity        = tonumber(_G.TPVelocity)   or 400
_G.VonClimb       = tonumber(_G.VonClimb)  or 200
_G.LandingDelay      = tonumber(_G.LandingDelay) or 0.4

-- Pre-load modules in background
task.spawn(function() pcall(loadModules); pcall(loadNet) end)

print("[Von] Loaded. Use the Von TP panel or keybinds to control.")

-- =====================================================================
-- Auto Run (one-shot on load)
-- =====================================================================
if _G.VonAutoRun then
    task.spawn(function()
        _running = true
        _G.VonTPCancel = false
        UILib.ShowNotification("Von TP", "Auto Run...")
        local ok, err = pcall(_G.VonStartSideTP or function() end)
        if not ok then warn("[Von] Auto Run error:", err) end
        _running = false
    end)
end

