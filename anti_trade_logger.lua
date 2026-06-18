--// Anti Trade-Logger Exploit
--// 6+ Detection methods
--// Best sources at discord.gg/rNvAU6cjVB
--// I love you all <3 from magik.z

-- STEAL A BRAINROT
pcall(function()
if not game:IsLoaded() then game.Loaded:Wait() end

cloneref = cloneref or function(o) return o end
local getupvalues = (debug and debug.getupvalues) or getupvalues
local getprotos = (debug and debug.getprotos) or getprotos
if not getupvalues then return end

local RS = cloneref(game:GetService("ReplicatedStorage"))
local netFolder = RS:WaitForChild("Packages"):WaitForChild("Net")
local okMod, ctrl = pcall(require, RS:WaitForChild("Controllers"):WaitForChild("TradeController"))
if not okMod or type(ctrl) ~= "table" then return end

local remotes, names = {}, {}
do
	local seenFn, seenInst = {}, {}
	local function walk(fn)
		if type(fn) ~= "function" or seenFn[fn] then return end
		seenFn[fn] = true
		local ok, ups = pcall(getupvalues, fn)
		if ok and ups then
			for _, v in pairs(ups) do
				if typeof(v) == "Instance" and v.Parent == netFolder
					and (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) then
					if not seenInst[v] then
						seenInst[v] = true
						remotes[#remotes + 1] = v
						names[v.Name] = true
					end
				elseif type(v) == "function" then
					walk(v)
				end
			end
		end
		if getprotos then
			local ok2, ps = pcall(getprotos, fn)
			if ok2 and ps then for _, p in ipairs(ps) do walk(p) end end
		end
	end
	for _, fn in pairs(ctrl) do walk(fn) end
end

for _, r in ipairs(remotes) do
	pcall(function() r:Destroy() end)
end
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
