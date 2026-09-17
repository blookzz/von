-- VON VISUALS
-- made open source at discord.gg/vonhub
-- UILib: https://raw.githubusercontent.com/blookzz/skibidi/refs/heads/main/UILib.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer       = Players.LocalPlayer

-------------------------------------------------
-- 0. LOAD UILIB
-------------------------------------------------

local UILib = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/blookzz/skibidi/refs/heads/main/UILib.lua", true
))()

-------------------------------------------------
-- 1. BRAINROTCARD 1OF1 HOOKS
-------------------------------------------------

local forcedOneOfOne = {}

local BrainrotCard = ReplicatedStorage:FindFirstChild("Shared")
	and ReplicatedStorage.Shared:FindFirstChild("BrainrotCard")
	and require(ReplicatedStorage.Shared.BrainrotCard)

if BrainrotCard then
	local oldIsOneOfOne
	oldIsOneOfOne = hookfunction(BrainrotCard.IsOneOfOne, function(record)
		if forcedOneOfOne[record.Index] then return true end
		return oldIsOneOfOne(record)
	end)
	local oldObserve
	oldObserve = hookfunction(BrainrotCard.ObserveOneOfOne, function(record, callback)
		return oldObserve(record, function(value)
			if forcedOneOfOne[record.Index] then callback(true) else callback(value) end
		end)
	end)
else
	warn("[AnimalPodiumScanner] BrainrotCard not found – card hooks skipped.")
end

-------------------------------------------------
-- 2. PANEL
-------------------------------------------------

local panel = UILib.CreatePanel({
	Name       = "AnimalPodiumGui",
	Title      = "VON VISUALS",
	Width      = 300,
	Height     = 250,
	Tabs       = { "ONE OF ONE", "SIGNATURE", "OTHER" },
	DefaultTab = 1,
	Discord    = true,
})

local tab1of1      = panel.GetTab(1)
local tabSignature = panel.GetTab(2)
local tabOther     = panel.GetTab(3)

-------------------------------------------------
-- 3. SHARED: findPodiums + matchDebris
--    Both tabs use the same plot/debris scan logic.
-------------------------------------------------

local function findPodiums()
	local Plots = workspace:FindFirstChild("Plots")
	if not Plots then return nil end
	for _, plot in pairs(Plots:GetChildren()) do
		local lbl = plot:FindFirstChild("PlotSign")
			and plot.PlotSign:FindFirstChild("SurfaceGui")
			and plot.PlotSign.SurfaceGui:FindFirstChild("Frame")
			and plot.PlotSign.SurfaceGui.Frame:FindFirstChild("TextLabel")
		if lbl and lbl.Text == localPlayer.DisplayName .. "'s Base" then
			return plot:FindFirstChild("AnimalPodiums")
		end
	end
	return nil
end

-- Returns an array of matched entries sorted by podium number:
--   { podiumName, name, gen, overhead, occupied }
local function matchPodiums(animalPodiums)
	local sorted = animalPodiums:GetChildren()
	table.sort(sorted, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)

	local debrisItems = {}
	for _, item in ipairs(workspace.Debris:GetChildren()) do
		local overhead = item:FindFirstChild("AnimalOverhead")
		if overhead then
			local dName = overhead:FindFirstChild("DisplayName")
			local gen   = overhead:FindFirstChild("Generation")
			local motor = item:FindFirstChildWhichIsA("Motor6D")
			if dName and gen and motor and motor.Part1 then
				table.insert(debrisItems, {
					position = motor.Part1.Position,
					name     = dName.Text,
					gen      = gen.Text,
					overhead = overhead,
				})
			end
		end
	end

	local matched   = {}
	local usedItems = {}

	for _, podium in ipairs(sorted) do
		local base  = podium:FindFirstChild("Base")
		local spawn = base and base:FindFirstChild("Spawn")
		if not (spawn and spawn:FindFirstChild("Attachment")) then continue end

		local attachPos = spawn.Position
		local nearest, nearestDist, nearestIdx = nil, math.huge, nil

		for i, item in ipairs(debrisItems) do
			if not usedItems[i] then
				local d = (item.position - attachPos).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearest     = item
					nearestIdx  = i
				end
			end
		end

		if nearest then
			usedItems[nearestIdx] = true
			table.insert(matched, {
				podiumName = podium.Name,
				name       = nearest.name,
				gen        = nearest.gen,
				overhead   = nearest.overhead,
				occupied   = true,
			})
		else
			table.insert(matched, { podiumName = podium.Name, occupied = false })
		end
	end

	return matched
end

-------------------------------------------------
-- 4. TAB 1 — 1OF1
-------------------------------------------------

local status1of1   = UILib.CreateParagraph(tab1of1, { Content = "Waiting for your plot…" })
local toggles1of1  = {}

-- Section that holds the per-animal toggles
local animalsSection1of1 = UILib.CreateSection(tab1of1, { Title = "Animals", Open = true })

local function clearToggles1of1()
	for _, t in ipairs(toggles1of1) do t.Frame:Destroy() end
	table.clear(toggles1of1)
end

local function scan1of1()
	clearToggles1of1()
	status1of1.Frame.Visible = false

	local animalPodiums = findPodiums()
	if not animalPodiums then
		status1of1.SetText("Waiting for your plot…")
		status1of1.Frame.Visible = true
		return
	end

	local matched = matchPodiums(animalPodiums)
	if #matched == 0 then
		status1of1.SetText("No brainrots found in your plot.")
		status1of1.Frame.Visible = true
		return
	end

	for _, m in ipairs(matched) do
		local label        = m.occupied
			and string.format("%s  |  %s", m.name, m.gen)
			or  string.format("[%s] Empty", m.podiumName)
		local initialState = m.occupied and forcedOneOfOne[m.name] == true or false
		local animalName   = m.occupied and m.name     or nil
		local overhead     = m.occupied and m.overhead or nil

		local toggle = UILib.CreateToggle(animalsSection1of1.Content, {
			Label   = label,
			Default = initialState,
			OnChanged = function(on)
				if not animalName then return end
				local banner = overhead and overhead.Parent
					and overhead:FindFirstChild("1OF1Banner")
				if on then
					forcedOneOfOne[animalName] = true
					if banner then banner.Visible = true end
				else
					forcedOneOfOne[animalName] = nil
					if banner then banner.Visible = false end
				end
			end,
		})

		if not m.occupied then
			toggle.Frame.BackgroundTransparency = 0.6
		end

		table.insert(toggles1of1, toggle)
	end
end

-------------------------------------------------
-- 5. TAB 2 — SIGNATURE
-------------------------------------------------

-- The text used for all active signature clones.
-- Editing the textbox updates this and patches existing clones live.
local signatureText  = "signature by lebron james"
local signatureColor = Color3.fromRGB(255, 0, 0)

-- animalName → clone TextLabel (one clone per toggled animal)
local signatureClones = {}

-- Find the real DisplayName TextLabel inside AnimalOverhead/FastOverheadTemplate
-- for a given overhead Instance.
local function findDisplayLabel(overhead)
	for _, obj in ipairs(game:GetDescendants()) do
		if obj.Name == "DisplayName"
			and obj:IsA("TextLabel")
			and obj.Parent
			and obj.Parent.Name == "AnimalOverhead"
			and obj.Parent == overhead
			and obj.Parent.Parent
			and obj.Parent.Parent.Name == "FastOverheadTemplate"
			and obj.Parent.Parent.Parent
			and obj.Parent.Parent.Parent.Name == "Debris"
			and obj.Parent.Parent.Parent.Parent == workspace
		then
			return obj
		end
	end
	return nil
end

local function applySignature(animalName, overhead)
	-- Remove any existing clone first (avoid duplicates)
	if signatureClones[animalName] then
		signatureClones[animalName]:Destroy()
		signatureClones[animalName] = nil
	end

	local obj = findDisplayLabel(overhead)
	if not obj then return end

	local clone = obj:Clone()
	clone.Text       = signatureText
	clone.TextColor3 = signatureColor
	clone.Position   = obj.Position + UDim2.new(0, 0, 0, obj.AbsoluteSize.Y)
	clone.Parent     = obj.Parent

	signatureClones[animalName] = clone
end

local function removeSignature(animalName)
	if signatureClones[animalName] then
		signatureClones[animalName]:Destroy()
		signatureClones[animalName] = nil
	end
end

-- Updates text and/or color of every active clone
local function refreshClones()
	for _, clone in pairs(signatureClones) do
		if clone and clone.Parent then
			clone.Text       = signatureText
			clone.TextColor3 = signatureColor
		end
	end
end

-- Signature tab UI
local statusSig  = UILib.CreateParagraph(tabSignature, { Content = "Waiting for your plot…" })
local togglesSig = {}

-- Section: style controls (text + colour)
local styleSection = UILib.CreateSection(tabSignature, { Title = "Style", Open = true })

local sigInput = UILib.CreateTextInput(styleSection.Content, {
	Label       = "Signature text",
	Placeholder = "signature by lebron james",
	Default     = signatureText,
	OnSubmit    = function(text)
		signatureText = (text ~= "" and text or "signature by lebron james")
		refreshClones()
	end,
})

local sigColor = UILib.CreateColorPicker(styleSection.Content, {
	Label   = "Text colour",
	Default = signatureColor,
	OnChanged = function(color)
		signatureColor = color
		refreshClones()
	end,
})

-- Section: animal toggles (rebuilt each scan)
local animalsSection = UILib.CreateSection(tabSignature, { Title = "Animals", Open = true })

local function clearTogglesSig()
	for _, t in ipairs(togglesSig) do t.Frame:Destroy() end
	table.clear(togglesSig)
end

local function scanSignature()
	clearTogglesSig()
	statusSig.Frame.Visible = false

	local animalPodiums = findPodiums()
	if not animalPodiums then
		statusSig.SetText("Waiting for your plot…")
		statusSig.Frame.Visible = true
		return
	end

	local matched = matchPodiums(animalPodiums)
	if #matched == 0 then
		statusSig.SetText("No brainrots found in your plot.")
		statusSig.Frame.Visible = true
		return
	end

	for _, m in ipairs(matched) do
		local label      = m.occupied
			and string.format("%s | %s", m.name, m.gen)
			or  string.format("[%s] Empty", m.podiumName)
		local initialState = m.occupied and signatureClones[m.name] ~= nil or false
		local animalName   = m.occupied and m.name     or nil
		local overhead     = m.occupied and m.overhead or nil

		local toggle = UILib.CreateToggle(animalsSection.Content, {
			Label   = label,
			Default = initialState,
			OnChanged = function(on)
				if not animalName then return end
				if on then
					applySignature(animalName, overhead)
				else
					removeSignature(animalName)
				end
			end,
		})

		if not m.occupied then
			toggle.Frame.BackgroundTransparency = 0.6
		end

		table.insert(togglesSig, toggle)
	end
end

-------------------------------------------------
-- 6. TAB 3 — OTHER
-------------------------------------------------

local apGiftSection = UILib.CreateSection(tabOther, { Title = "Ap Gift", Open = true })

UILib.CreateButton(apGiftSection.Content, {
	Text    = "Run Ap Gift",
	OnClick = function()
		loadstring(game:HttpGet("https://raw.githubusercontent.com/blookzz/von/refs/heads/main/visual_ap.lua"))()
	end,
})

-------------------------------------------------
-- 7. AUTO-SCAN + WATCHERS
--    Both tabs are rescanned together.
-------------------------------------------------

local scanPending = false
local function scheduleScans()
	if scanPending then return end
	scanPending = true
	task.delay(0.6, function()
		scanPending = false
		scan1of1()
		scanSignature()
	end)
end

task.spawn(function()
	while not findPodiums() do task.wait(1) end
	scan1of1()
	scanSignature()
end)

local Debris = workspace:WaitForChild("Debris")
Debris.ChildAdded:Connect(function(child)
	task.defer(function()
		if child:FindFirstChild("AnimalOverhead") then scheduleScans() end
	end)
end)
Debris.ChildRemoved:Connect(function(child)
	if child:FindFirstChild("AnimalOverhead") then scheduleScans() end
end)
