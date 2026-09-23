--!nonstrict

-- AutoSteal: a small auto-steal loop for "Steal An Egg".
--
-- Each cycle it picks the best wild field egg (RF/EggWorld/AskFieldEggSnapshot), hop-trains
-- to it at a locked height (small steps avoid the server's displacement/teleport kick),
-- fires the nearby CarryAreaEgg ProximityPrompt to grab it, then returns to your bank spot
-- and unequips so the egg banks. Grab-via-prompt and the hop-train are the proven paths;
-- everything is your own recovered clean-room flow (steal_run / steal_target), no game code.
--
-- Run it from an executor. It captures YOUR bank spot + travel height when it starts, so
-- stand at your pen when you turn it on. Stop with _G.AutoSteal.stop().

--// ============================== CONFIG ==============================
local AUTO_START   = true    -- begin stealing as soon as the script runs
local HOP          = 30      -- studs per micro-hop (smaller = safer vs anti-cheat)
local FLY_Y        = nil     -- locked travel height; nil = your height when you start
local HOME         = nil     -- Vector3 bank spot; nil = your position when you start
local PICK_BY      = "mutation" -- "mutation" (tier, then size) or "size" (NestScale only)
local GRAB_RANGE   = 8       -- how close a CarryAreaEgg prompt must be to fire (studs)
local APPROACH_OFF = 40      -- drop-in offset behind the egg before hopping the last bit
local HOLD         = 0.3     -- pause between the two prompt fires
local GRAB_WAIT    = 2.5     -- seconds to let the grab register
local BANK_WAIT    = 2       -- seconds at home for the drop/bank to register
local LOOP_DELAY   = 1       -- seconds between steals
local NOTIFY       = true    -- Roblox toast notifications
--// ====================================================================

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui      = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

if _G.__AutoStealCleanup then pcall(_G.__AutoStealCleanup) end

local Steal = { on = false, home = nil, flyY = nil }
_G.__AutoStealCleanup = function() Steal.on = false end

--// ------------------------------ helpers ------------------------------

local function notify(text: string, duration: number?)
	if not NOTIFY then return end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Auto Steal", Text = text, Duration = duration or 3 })
	end)
end

local function char()
	return LocalPlayer.Character
end

local function hrp(): BasePart?
	local c = char()
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoid(): Humanoid?
	local c = char()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function net()
	local pkgs = ReplicatedStorage:FindFirstChild("Packages")
	return pkgs and pkgs:FindFirstChild("Networking")
end

local function rf(name: string)
	local n = net()
	return n and n:FindFirstChild(name, true)
end

local function tp(pos: Vector3)
	local root = hrp()
	if root then root.CFrame = CFrame.new(pos) end
end

--// ------------------------------ targeting ------------------------------

local function tier(m): number
	if m == "Rainbow" then return 3 end
	if m == "Golden" then return 2 end
	if m == "Silver" then return 1 end
	return 0
end

-- Best wild field egg from the live snapshot. Returns its world position, or nil.
local function bestEggPos(): Vector3?
	local remote = rf("RF/EggWorld/AskFieldEggSnapshot")
	if not remote then return nil end
	local ok, snap = pcall(function() return remote:InvokeServer() end)
	if not ok or type(snap) ~= "table" or type(snap.Records) ~= "table" then return nil end

	local best, bestScore = nil, -1
	for _, e in pairs(snap.Records) do
		local size = tonumber(e.NestScale) or 0
		local score = (PICK_BY == "size") and size or (tier(e.BaseMutation) * 1e12 + size * 1e6)
		if score > bestScore then
			bestScore = score
			best = e
		end
	end
	if not best then return nil end
	local cf = best.BoundsCFrame or best.BottomCFrame
	return cf and cf.Position or nil
end

--// ------------------------------ movement ------------------------------

-- Hop in ~HOP-stud steps at a locked height, so no single teleport is big enough to trip
-- the server's displacement check.
local function hopTo(dest: Vector3)
	local root = hrp()
	if not root then return end
	local p = root.Position
	local flat = Vector3.new(dest.X - p.X, 0, dest.Z - p.Z)
	local dist = flat.Magnitude
	local steps = math.max(1, math.floor(dist / HOP))
	for i = 1, steps do
		if not Steal.on then return end
		local t = i / steps
		tp(Vector3.new(p.X + flat.X * t, Steal.flyY, p.Z + flat.Z * t))
		task.wait(0.05)
	end
	tp(Vector3.new(dest.X, Steal.flyY, dest.Z))
end

-- Fire any CarryAreaEgg prompt within reach of pos (twice, like the traced grab).
local function fireNear(pos: Vector3): boolean
	local fired = false
	for _, pr in ipairs(workspace:GetDescendants()) do
		if pr:IsA("ProximityPrompt") and pr.Name == "CarryAreaEgg" and pr.Enabled then
			local part = pr.Parent
			local ppos = part and part:IsA("BasePart") and part.Position
			if ppos and (ppos - pos).Magnitude < GRAB_RANGE then
				pcall(function() fireproximityprompt(pr) end)
				task.wait(HOLD)
				pcall(function() fireproximityprompt(pr) end)
				fired = true
			end
		end
	end
	return fired
end

--// ------------------------------ loop ------------------------------

local function stealOnce(): boolean
	local eggPos = bestEggPos()
	if not eggPos then
		notify("No field egg found.")
		return false
	end

	-- Drop in behind the egg, hop the rest of the way, grab it.
	tp(Vector3.new(eggPos.X, Steal.flyY, eggPos.Z + APPROACH_OFF))
	hopTo(eggPos)
	local grabbed = fireNear(eggPos)
	task.wait(GRAB_WAIT)

	-- Back to your pen and unequip so it banks.
	if not Steal.on then return grabbed end
	hopTo(Steal.home)
	tp(Steal.home)
	task.wait(1)
	local hum = humanoid()
	if hum then pcall(function() hum:UnequipTools() end) end
	task.wait(BANK_WAIT)
	return grabbed
end

function Steal.start()
	if Steal.on then return end
	local root = hrp()
	if not root then
		notify("No character yet - respawn and retry.")
		return
	end
	Steal.home = HOME or root.Position
	Steal.flyY = FLY_Y or root.Position.Y
	Steal.on = true
	notify("Auto Steal ON", 3)
	task.spawn(function()
		while Steal.on do
			local ok, grabbed = pcall(stealOnce)
			if ok and grabbed then
				notify("Stole an egg", 2)
			end
			task.wait(LOOP_DELAY)
		end
		notify("Auto Steal OFF", 2)
	end)
end

function Steal.stop()
	Steal.on = false
end

function Steal.toggle()
	if Steal.on then Steal.stop() else Steal.start() end
end

_G.AutoSteal = Steal

if AUTO_START then
	-- Wait for a character before the first run.
	if not hrp() then
		pcall(function() LocalPlayer.CharacterAdded:Wait() end)
		task.wait(1)
	end
	Steal.start()
end
