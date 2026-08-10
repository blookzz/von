-- Von | Open Source Auto Collect Honey
-- discord.gg/rNvAU6cjVB

local UILib = loadstring(game:HttpGet("https://raw.githubusercontent.com/blookzz/skibidi/refs/heads/main/UILib.lua"))()

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local MAX_HEIGHT_DIFF = 5

local enabled = false
local target  = nil

local function getChar()
	local char = LocalPlayer.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then return hum, hrp end
end

-- workspace.Honey may be a single part or a folder/model of honey parts
local function getHoneyParts()
	local out  = {}
	local root = workspace:FindFirstChild("Honey")
	if not root then return out end
	if root:IsA("BasePart") then
		table.insert(out, root)
	else
		for _, child in ipairs(root:GetChildren()) do
			local part = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart", true)
			if part then table.insert(out, part) end
		end
	end
	return out
end

local function nearestHoney(from)
	local best, bestDist
	for _, part in ipairs(getHoneyParts()) do
		if math.abs(part.Position.Y - from.Y) <= MAX_HEIGHT_DIFF then
			local d = (part.Position - from).Magnitude
			if not bestDist or d < bestDist then best, bestDist = part, d end
		end
	end
	return best
end

local function walkTo(hum, hrp)
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	local ok = pcall(path.ComputeAsync, path, hrp.Position, target.Position)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		hum:MoveTo(target.Position)
		task.wait(0.2)
		return
	end

	for _, wp in ipairs(path:GetWaypoints()) do
		if not enabled or not target.Parent then return end
		if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
		local t = 0
		while (hrp.Position - wp.Position).Magnitude > 3 do
			hum:MoveTo(wp.Position)
			t += RunService.Heartbeat:Wait()
			if not enabled or not target.Parent or t > 2 then return end
		end
	end
end

task.spawn(function()
	while true do
		if enabled then
			local hum, hrp = getChar()
			if hum and hrp then
				target = nearestHoney(hrp.Position)
				if target then walkTo(hum, hrp) end
			end
		end
		RunService.Heartbeat:Wait()
	end
end)

local Panel = UILib.CreatePanel({
	Name      = "Von",
	Title     = "VON HUB",
	Width     = 260,
	Height    = 60,
	Discord   = true,
	ToggleKey = "RightShift",
})

UILib.CreateToggle(Panel.Content, {
	Label   = "Auto Collect Honey",
	Default = false,
	OnChanged = function(state)
		enabled = state
		if not state then
			target = nil
			local hum, hrp = getChar()
			if hum and hrp then hum:MoveTo(hrp.Position) end
		end
	end,
})
