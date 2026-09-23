--!nonstrict

-- AutoSteal: a small auto-steal loop for "Steal An Egg".
--
-- The steal itself is a CarryAreaEgg ProximityPrompt (ActionText "Steal") on a pen: the
-- server handles its Triggered event, and it requires you to be within ~8 studs. So this
-- goes to the prompt, teleports ONTO it (3D) so the server's distance check passes, fires
-- it to grab, then returns to your bank spot and unequips so the egg banks.
--
-- This is your own recovered clean-room flow (steal / steal_run), calling only the game's
-- prompts. Run it from an executor while standing at your pen (it captures your bank spot).

--// ============================== CONFIG ==============================
local AUTO_START   = true    -- begin stealing as soon as the script runs
local MODE         = "Pen"   -- "Pen" (nearest steal prompt) or "Field" (near best wild egg)
local HOP          = 30      -- studs per micro-hop (smaller = safer vs anti-cheat)
local HOME         = nil     -- Vector3 bank spot; nil = your position when you start
local HOME_RADIUS  = 60      -- ignore steal prompts within this many studs of home (yours)
local FIELD_RANGE  = 60      -- Field mode: max distance a prompt may be from the target egg
local GRAB_OFFSET  = 4       -- studs above the prompt to sit while firing
local FIRES        = 2       -- how many times to fire the prompt per grab
local HOLD         = 0.4     -- pause between fires
local GRAB_WAIT    = 1.5     -- seconds to let the grab register before banking
local BANK_WAIT    = 2       -- seconds at home for the drop/bank to register
local LOOP_DELAY   = 1       -- seconds between steals
local NOTIFY       = true    -- Roblox toast notifications
--// ====================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

if _G.__AutoStealCleanup then pcall(_G.__AutoStealCleanup) end

local Steal = { on = false, home = nil }
_G.__AutoStealCleanup = function() Steal.on = false end

--// ------------------------------ helpers ------------------------------

local function notify(text: string, dur: number?)
	if not NOTIFY then return end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Auto Steal", Text = text, Duration = dur or 3 })
	end)
end

local function hrp(): BasePart?
	local c = LocalPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoid(): Humanoid?
	local c = LocalPlayer.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function rf(name: string)
	local pkgs = ReplicatedStorage:FindFirstChild("Packages")
	local n = pkgs and pkgs:FindFirstChild("Networking")
	return n and n:FindFirstChild(name, true)
end

local function tp(pos: Vector3)
	local root = hrp()
	if root then root.CFrame = CFrame.new(pos) end
end

-- A ProximityPrompt's world position, whatever it's parented to.
local function promptPos(pr: Instance): Vector3?
	local par = pr.Parent
	if not par then return nil end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Attachment") then return par.WorldPosition end
	local bp = (par:IsA("Model") and par.PrimaryPart) or par:FindFirstChildWhichIsA("BasePart")
	return bp and bp.Position or nil
end

local function collectPrompts()
	local out = {}
	for _, pr in ipairs(workspace:GetDescendants()) do
		if pr:IsA("ProximityPrompt") and pr.Name == "CarryAreaEgg" and pr.Enabled then
			local pos = promptPos(pr)
			if pos then out[#out + 1] = { prompt = pr, pos = pos } end
		end
	end
	return out
end

--// ------------------------------ targeting ------------------------------

local function tier(m): number
	if m == "Rainbow" then return 3 end
	if m == "Golden" then return 2 end
	if m == "Silver" then return 1 end
	return 0
end

local function bestFieldPos(): Vector3?
	local remote = rf("RF/EggWorld/AskFieldEggSnapshot")
	if not remote then return nil end
	local ok, snap = pcall(function() return remote:InvokeServer() end)
	if not ok or type(snap) ~= "table" or type(snap.Records) ~= "table" then return nil end
	local best, bestScore = nil, -1
	for _, e in pairs(snap.Records) do
		local score = tier(e.BaseMutation) * 1e12 + (tonumber(e.NestScale) or 0) * 1e6
		if score > bestScore then bestScore, best = score, e end
	end
	local cf = best and (best.BoundsCFrame or best.BottomCFrame)
	return cf and cf.Position or nil
end

-- Returns { prompt, pos } for the prompt to steal this cycle, or nil.
local function pickTarget()
	local root = hrp()
	if not root then return nil end
	local me = root.Position
	local prompts = collectPrompts()
	if #prompts == 0 then return nil end

	if MODE == "Field" then
		local egg = bestFieldPos()
		if egg then
			local best, bd = nil, FIELD_RANGE
			for _, c in ipairs(prompts) do
				local d = (c.pos - egg).Magnitude
				if d < bd then bd, best = d, c end
			end
			if best then return best end
		end
		-- fall through to nearest if no field data
	end

	-- Pen (or Field fallback): nearest prompt away from your own base.
	local best, bd = nil, math.huge
	for _, c in ipairs(prompts) do
		if (c.pos - Steal.home).Magnitude > HOME_RADIUS then
			local d = (c.pos - me).Magnitude
			if d < bd then bd, best = d, c end
		end
	end
	return best
end

--// ------------------------------ movement + grab ------------------------------

-- Hop in ~HOP-stud steps (full 3D) so no single teleport is big enough to trip the
-- server's displacement check, ending exactly at dest.
local function hopTo(dest: Vector3)
	local root = hrp()
	if not root then return end
	local start = root.Position
	local delta = dest - start
	local steps = math.max(1, math.floor(delta.Magnitude / HOP))
	for i = 1, steps do
		if not Steal.on then return end
		tp(start + delta * (i / steps))
		task.wait(0.05)
	end
	tp(dest)
end

local function grab(c): boolean
	-- Sit right on the prompt so the server's <8-stud check passes, then fire.
	hopTo(c.pos + Vector3.new(0, GRAB_OFFSET, 0))
	if not Steal.on then return false end
	tp(c.pos + Vector3.new(0, GRAB_OFFSET, 0))
	task.wait(0.25)
	local fired = false
	for _ = 1, FIRES do
		if not Steal.on then break end
		pcall(function() fireproximityprompt(c.prompt) end)
		fired = true
		task.wait(HOLD)
	end
	return fired
end

local function bankHome()
	hopTo(Steal.home)
	tp(Steal.home)
	task.wait(1)
	local hum = humanoid()
	if hum then pcall(function() hum:UnequipTools() end) end
	task.wait(BANK_WAIT)
end

--// ------------------------------ loop ------------------------------

local function cycle(): boolean
	local target = pickTarget()
	if not target then
		notify("No steal prompt found.")
		return false
	end
	local grabbed = grab(target)
	task.wait(GRAB_WAIT)
	if Steal.on then bankHome() end
	return grabbed
end

function Steal.start()
	if Steal.on then return end
	local root = hrp()
	if not root then notify("No character yet - respawn and retry.") return end
	Steal.home = HOME or root.Position
	Steal.on = true
	notify("Auto Steal ON (" .. MODE .. ")")
	task.spawn(function()
		while Steal.on do
			local ok, grabbed = pcall(cycle)
			if ok and grabbed then notify("Grabbed", 2) end
			task.wait(LOOP_DELAY)
		end
		notify("Auto Steal OFF", 2)
	end)
end

function Steal.stop() Steal.on = false end
function Steal.toggle() if Steal.on then Steal.stop() else Steal.start() end end

_G.AutoSteal = Steal

if AUTO_START then
	if not hrp() then
		pcall(function() LocalPlayer.CharacterAdded:Wait() end)
		task.wait(1)
	end
	Steal.start()
end
