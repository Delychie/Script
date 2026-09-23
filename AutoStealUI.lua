--!nonstrict

-- AutoStealUI: the auto-steal loop for "Steal An Egg" with a tiny on/off GUI, plus a
-- Field/Pen target switch. It also wires itself into your SAE Hub if that hub is open.
--
-- This is a self-contained companion to AutoSteal.lua (same proven flow: hop-train to a
-- target, fire the CarryAreaEgg prompt to grab, return to your bank spot and unequip).
-- Run EITHER this or AutoSteal.lua, not both. Nothing here is auto-started; the button is.
--
-- Modes:
--   Field - pick the best wild field egg (RF/EggWorld/AskFieldEggSnapshot).
--   Pen   - go for the nearest CarryAreaEgg prompt away from your own base (steal from pens).

--// ============================== CONFIG ==============================
local START_MODE   = "Field" -- "Field" or "Pen"
local HOP          = 30      -- studs per micro-hop (smaller = safer vs anti-cheat)
local FLY_Y        = nil     -- locked travel height; nil = your height when you start
local HOME         = nil     -- Vector3 bank spot; nil = your position when you start
local PICK_BY      = "mutation" -- Field mode: "mutation" (tier, then size) or "size"
local GRAB_RANGE   = 8       -- how close a CarryAreaEgg prompt must be to fire (studs)
local APPROACH_OFF = 40      -- drop-in offset behind the target before the last hop
local HOME_RADIUS  = 60      -- Pen mode: ignore prompts within this many studs of home (yours)
local HOLD         = 0.3     -- pause between the two prompt fires
local GRAB_WAIT    = 2.5     -- seconds to let the grab register
local BANK_WAIT    = 2       -- seconds at home for the drop/bank to register
local LOOP_DELAY   = 1       -- seconds between steals
local NOTIFY       = true    -- Roblox toast notifications
--// ====================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

if _G.__AutoStealUICleanup then pcall(_G.__AutoStealUICleanup) end

local S = { on = false, mode = START_MODE, home = nil, flyY = nil }
local indicators: { (boolean, string) -> () } = {}

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

local function refresh()
	for _, f in ipairs(indicators) do pcall(f, S.on, S.mode) end
end

--// ------------------------------ targeting ------------------------------

local function tier(m): number
	if m == "Rainbow" then return 3 end
	if m == "Golden" then return 2 end
	if m == "Silver" then return 1 end
	return 0
end

-- Field mode: best wild egg's world position.
local function bestFieldPos(): Vector3?
	local remote = rf("RF/EggWorld/AskFieldEggSnapshot")
	if not remote then return nil end
	local ok, snap = pcall(function() return remote:InvokeServer() end)
	if not ok or type(snap) ~= "table" or type(snap.Records) ~= "table" then return nil end
	local best, bestScore = nil, -1
	for _, e in pairs(snap.Records) do
		local size = tonumber(e.NestScale) or 0
		local score = (PICK_BY == "size") and size or (tier(e.BaseMutation) * 1e12 + size * 1e6)
		if score > bestScore then bestScore, best = score, e end
	end
	if not best then return nil end
	local cf = best.BoundsCFrame or best.BottomCFrame
	return cf and cf.Position or nil
end

-- Pen mode: nearest CarryAreaEgg prompt away from your own base.
local function nearestPenPos(): Vector3?
	local root = hrp()
	if not root then return nil end
	local me = root.Position
	local best, bestDist = nil, math.huge
	for _, pr in ipairs(workspace:GetDescendants()) do
		if pr:IsA("ProximityPrompt") and pr.Name == "CarryAreaEgg" and pr.Enabled then
			local part = pr.Parent
			local ppos = part and part:IsA("BasePart") and part.Position
			if ppos and (ppos - S.home).Magnitude > HOME_RADIUS then
				local d = (ppos - me).Magnitude
				if d < bestDist then bestDist, best = d, ppos end
			end
		end
	end
	return best
end

--// ------------------------------ movement + grab ------------------------------

local function hopTo(dest: Vector3)
	local root = hrp()
	if not root then return end
	local p = root.Position
	local flat = Vector3.new(dest.X - p.X, 0, dest.Z - p.Z)
	local steps = math.max(1, math.floor(flat.Magnitude / HOP))
	for i = 1, steps do
		if not S.on then return end
		local t = i / steps
		tp(Vector3.new(p.X + flat.X * t, S.flyY, p.Z + flat.Z * t))
		task.wait(0.05)
	end
	tp(Vector3.new(dest.X, S.flyY, dest.Z))
end

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

local function cycle(): boolean
	local target = (S.mode == "Pen") and nearestPenPos() or bestFieldPos()
	if not target then
		notify("No " .. S.mode:lower() .. " target found.")
		return false
	end
	tp(Vector3.new(target.X, S.flyY, target.Z + APPROACH_OFF))
	hopTo(target)
	local grabbed = fireNear(target)
	task.wait(GRAB_WAIT)
	if not S.on then return grabbed end
	hopTo(S.home)
	tp(S.home)
	task.wait(1)
	local hum = humanoid()
	if hum then pcall(function() hum:UnequipTools() end) end
	task.wait(BANK_WAIT)
	return grabbed
end

--// ------------------------------ control ------------------------------

function S.start()
	if S.on then return end
	local root = hrp()
	if not root then notify("No character yet - respawn and retry.") return end
	S.home = HOME or root.Position
	S.flyY = FLY_Y or root.Position.Y
	S.on = true
	refresh()
	notify("Auto Steal ON (" .. S.mode .. ")")
	task.spawn(function()
		while S.on do
			local ok, grabbed = pcall(cycle)
			if ok and grabbed then notify("Stole an egg", 2) end
			task.wait(LOOP_DELAY)
		end
		refresh()
		notify("Auto Steal OFF", 2)
	end)
end

function S.stop() S.on = false end
function S.toggle() if S.on then S.stop() else S.start() end end
function S.setMode(m)
	S.mode = (m == "Pen") and "Pen" or "Field"
	refresh()
end
function S.cycleMode() S.setMode(S.mode == "Field" and "Pen" or "Field") end

_G.AutoStealUI = S

--// ------------------------------ GUI (tiny toggle) ------------------------------

local ON_COLOR  = Color3.fromRGB(40, 160, 70)
local OFF_COLOR = Color3.fromRGB(60, 60, 72)

local gui = Instance.new("ScreenGui")
gui.Name = "AutoStealUI"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local panel = Instance.new("Frame", gui)
panel.Size = UDim2.new(0, 150, 0, 66)
panel.Position = UDim2.new(0, 20, 0, 200)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

local toggle = Instance.new("TextButton", panel)
toggle.Size = UDim2.new(1, -12, 0, 32)
toggle.Position = UDim2.new(0, 6, 0, 6)
toggle.BackgroundColor3 = OFF_COLOR
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 14
toggle.Text = "Auto Steal: OFF"
toggle.AutoButtonColor = true
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6)

local modeBtn = Instance.new("TextButton", panel)
modeBtn.Size = UDim2.new(1, -12, 0, 20)
modeBtn.Position = UDim2.new(0, 6, 0, 42)
modeBtn.BackgroundColor3 = Color3.fromRGB(44, 44, 58)
modeBtn.TextColor3 = Color3.fromRGB(210, 210, 220)
modeBtn.Font = Enum.Font.Gotham
modeBtn.TextSize = 12
modeBtn.Text = "Mode: " .. S.mode
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

toggle.MouseButton1Click:Connect(function() S.toggle() end)
modeBtn.MouseButton1Click:Connect(function() S.cycleMode() end)

table.insert(indicators, function(on, mode)
	toggle.Text = "Auto Steal: " .. (on and "ON" or "OFF")
	toggle.BackgroundColor3 = on and ON_COLOR or OFF_COLOR
	modeBtn.Text = "Mode: " .. mode
end)

--// ------------------------------ SAE Hub wire-in ------------------------------

-- If your SAE Hub is open, drop a matching toggle into it too, sharing the same state.
local function wireHub()
	local hub = CoreGui:FindFirstChild("SAEHub")
	local mainFrame = hub and hub:FindFirstChildWhichIsA("Frame")
	if not mainFrame then return end
	if mainFrame:FindFirstChild("AutoStealHubBtn") then return end
	local b = Instance.new("TextButton", mainFrame)
	b.Name = "AutoStealHubBtn"
	b.Size = UDim2.new(0, 100, 0, 26)
	b.Position = UDim2.new(0, 6, 1, -32)
	b.BackgroundColor3 = OFF_COLOR
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = "Steal: OFF"
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.MouseButton1Click:Connect(function() S.toggle() end)
	table.insert(indicators, function(on)
		if not b.Parent then return end
		b.Text = "Steal: " .. (on and "ON" or "OFF")
		b.BackgroundColor3 = on and ON_COLOR or OFF_COLOR
	end)
end
pcall(wireHub)

_G.__AutoStealUICleanup = function()
	S.on = false
	pcall(function() gui:Destroy() end)
	local hub = CoreGui:FindFirstChild("SAEHub")
	local mf = hub and hub:FindFirstChildWhichIsA("Frame")
	local hb = mf and mf:FindFirstChild("AutoStealHubBtn")
	if hb then pcall(function() hb:Destroy() end) end
end

refresh()
notify("Auto Steal UI loaded", 3)
