--// Anti Trade-Logger Exploit
--// 6+ Detection methods
--// Best sources at discord.gg/rNvAU6cjVB
--// I love you all <3 from magik.z

-- STEAL A BRAINROT
pcall(function()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==================================================
-- CONFIG
--==================================================

local PROTECTED_GUIS = {
	BrainrotTrader = true,
	TradeLiveTrade = true,
	TradePrompts = true,
	LeftCenter = true,
}

local BLACKLISTED_GUIDS = {
	["afb005f9-6e81-4e0a-8bb0-3555938a9658"] = "Trade Logger Signature #1",
	["6b5f15fb-5cb9-4d07-a031-bbff8e641eda"] = "Trade Logger Signature #2",
	["d73acf93-6f32-44df-b813-0f6b32c7afd9"] = "Trade Logger Signature #3",
	["918ee0f5-e98f-413f-b76e-baee47b021cb"] = "Trade Logger Signature #4",
}

local RATE_LIMITS = {
	Invite = {limit = 5, window = 10},
	Ready = {limit = 8, window = 5},
	Accept = {limit = 8, window = 5},
	AddBrainrot = {limit = 15, window = 5},
}

local remoteLog = {}
local lastReady = 0

--==================================================
-- HELPER
--==================================================

local function detectionKick(reason)
	player:Kick("[ANTI TRADE LOGGER] " .. reason)
end

--==================================================
-- DETECTION 1: GUI REMOVAL
--==================================================

local existing = {}

for guiName in pairs(PROTECTED_GUIS) do
	existing[guiName] = playerGui:FindFirstChild(guiName) ~= nil
end

playerGui.ChildAdded:Connect(function(child)
	if PROTECTED_GUIS[child.Name] then
		existing[child.Name] = true
	end
end)

playerGui.ChildRemoved:Connect(function(child)

	if PROTECTED_GUIS[child.Name] and existing[child.Name] then

		detectionKick(
			"Protected trade GUI removed (" .. child.Name .. ")"
		)
	end
end)

--==================================================
-- DETECTION 2: GUI HIDDEN
--==================================================

local function monitorVisibility(obj)

	if not obj:IsA("GuiObject") then
		return
	end

	obj:GetPropertyChangedSignal("Visible"):Connect(function()

		if PROTECTED_GUIS[obj.Name] and obj.Visible == false then

			detectionKick(
				"Protected trade GUI hidden (" .. obj.Name .. ")"
			)
		end
	end)
end

for _, obj in ipairs(playerGui:GetDescendants()) do
	monitorVisibility(obj)
end

playerGui.DescendantAdded:Connect(monitorVisibility)

--==================================================
-- DETECTION 3: LEFTCENTER BACKUP CLONE
--==================================================

playerGui.DescendantAdded:Connect(function(obj)

	if obj.Name == "LeftCenter_Backup" then

		detectionKick(
			"Trade logger clone GUI detected"
		)
	end
end)

--==================================================
-- DETECTION 4: REMOTE SPAM
--==================================================

local function checkSpam(action)

	local cfg = RATE_LIMITS[action]

	if not cfg then
		return false
	end

	local now = tick()

	if not remoteLog[action] then
		remoteLog[action] = {}
	end

	local log = remoteLog[action]

	for i = #log, 1, -1 do

		if now - log[i] > cfg.window then
			table.remove(log, i)
		end
	end

	table.insert(log, now)

	return #log > cfg.limit
end

--==================================================
-- DETECTION 5: TRADE REMOTE HOOKING
--==================================================

local tradeService = ReplicatedStorage:FindFirstChild("TradeService")

if tradeService then

	local function hookRemote(remote, actionName)

		if not remote or not remote:IsA("RemoteEvent") then
			return
		end

		local oldFireServer = remote.FireServer

		remote.FireServer = function(self, ...)

			--========================
			-- SPAM CHECK
			--========================

			if checkSpam(actionName) then

				detectionKick(
					"Suspicious trade remote spam (" .. actionName .. ")"
				)

				return
			end

			--========================
			-- GUID CHECK
			--========================

			for _, arg in ipairs({...}) do

				if type(arg) == "string" then

					local reason = BLACKLISTED_GUIDS[arg]

					if reason then

						detectionKick(
							"Known trade logger signature detected"
						)

						return
					end
				end
			end

			--========================
			-- READY -> ACCEPT CHECK
			--========================

			if actionName == "Ready" then
				lastReady = tick()
			end

			if actionName == "Accept" then

				local diff = tick() - lastReady

				if diff < 0.6 then

					detectionKick(
						"Automated trade accept behavior detected"
					)

					return
				end
			end

			return oldFireServer(self, ...)
		end
	end

	hookRemote(tradeService:FindFirstChild("Invite"), "Invite")
	hookRemote(tradeService:FindFirstChild("Ready"), "Ready")
	hookRemote(tradeService:FindFirstChild("Accept"), "Accept")
	hookRemote(tradeService:FindFirstChild("AddBrainrot"), "AddBrainrot")
end

--==================================================
-- DETECTION 6: TRANSPARENCY HIDING
--==================================================

local function monitorTransparency(obj)

	if not obj:IsA("GuiObject") then
		return
	end

	obj:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()

		if PROTECTED_GUIS[obj.Name] then

			if obj.BackgroundTransparency >= 1 then

				detectionKick(
					"Protected trade GUI transparency modified"
				)
			end
		end
	end)
end

for _, obj in ipairs(playerGui:GetDescendants()) do
	monitorTransparency(obj)
end

playerGui.DescendantAdded:Connect(monitorTransparency)

print("[ANTI TRADE LOGGER] Loaded")
end


-- GROW A GARDEN
pcall(function()
    local StarterGui = game:GetService("StarterGui")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local BLOCKED_CATEGORIES = {
        "Pets", "Seeds", "WateringCans", "Signs", "Sprinklers", "Mushrooms", "Crates"
    }

    local Packet = ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Packet")
    local TargetRemote = Packet:WaitForChild("RemoteEvent")

    local function showBlockedNotification(category)
        StarterGui:SetCore("SendNotification", {
            Title = "Remote Blocked",
            Text = "Blocked unauthorized transaction.",
            Duration = 5,
            Button1 = "Dismiss"
        })
    end

    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if self == TargetRemote and method == "FireServer" then
            local bufferData = args[1]
            
            if typeof(bufferData) == "buffer" then
                local bufferString = buffer.tostring(bufferData)

                local hasItemKey = string.find(bufferString, "ItemKey")
                local hasCount = string.find(bufferString, "Count")
                local hasCategory = string.find(bufferString, "Category")

                if hasItemKey and hasCount and hasCategory then
                    for _, categoryName in ipairs(BLOCKED_CATEGORIES) do
                        if string.find(bufferString, categoryName) then
                            task.spawn(showBlockedNotification, categoryName)
                            return
                        end
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)

    setreadonly(mt, true)

    StarterGui:SetCore("SendNotification", {
        Title = "Von Hub",
        Text = "Mailbox Anti-Logger Loaded",
        Duration = 5,
        Button1 = "Dismiss"
    })
end)
