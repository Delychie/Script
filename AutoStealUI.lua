--!nonstrict

-- AutoStealUI: the auto-steal loop for "Steal An Egg" with a tiny on/off GUI, a Pen/Field
-- target switch, and a toggle wired into your SAE Hub if it's open.
--
-- The steal is a CarryAreaEgg ProximityPrompt on a pen: the server handles its Triggered
-- event and requires you within ~8 studs. So each cycle goes to the prompt, teleports ONTO
-- it (3D) so the distance check passes, fires it to grab, then returns home and unequips
-- so the egg banks. Same flow as AutoSteal.lua - run EITHER this or that, not both.
--
-- Modes:
--   Pen   - nearest steal prompt away from your own base (the proven grab).
--   Field - the steal prompt nearest the best wild field egg (falls back to Pen).

--// ============================== CONFIG ==============================
local START_MODE   = "Pen"   -- "Pen" or "Field"
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
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

if _G.__AutoStealUICleanup then pcall(_G.__AutoStealUICleanup) end

local S = { on = false, mode = START_MODE, home = nil }
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

local function pickTarget()
	local root = hrp()
	if not root then return nil end
	local me = root.Position
	local prompts = collectPrompts()
	if #prompts == 0 then return nil end

	if S.mode == "Field" then
		local egg = bestFieldPos()
		if egg then
			local best, bd = nil, FIELD_RANGE
			for _, c in ipairs(prompts) do
				local d = (c.pos - egg).Magnitude
				if d < bd then bd, best = d, c end
			end
			if best then return best end
		end
	end

	local best, bd = nil, math.huge
	for _, c in ipairs(prompts) do
		if (c.pos - S.home).Magnitude > HOME_RADIUS then
			local d = (c.pos - me).Magnitude
			if d < bd then bd, best = d, c end
		end
	end
	return best
end

--// ------------------------------ movement + grab ------------------------------

local function hopTo(dest: Vector3)
	local root = hrp()
	if not root then return end
	local start = root.Position
	local delta = dest - start
	local steps = math.max(1, math.floor(delta.Magnitude / HOP))
	for i = 1, steps do
		if not S.on then return end
		tp(start + delta * (i / steps))
		task.wait(0.05)
	end
	tp(dest)
end

local function grab(c): boolean
	hopTo(c.pos + Vector3.new(0, GRAB_OFFSET, 0))
	if not S.on then return false end
	tp(c.pos + Vector3.new(0, GRAB_OFFSET, 0))
	task.wait(0.25)
	local fired = false
	for _ = 1, FIRES do
		if not S.on then break end
		pcall(function() fireproximityprompt(c.prompt) end)
		fired = true
		task.wait(HOLD)
	end
	return fired
end

local function bankHome()
	hopTo(S.home)
	tp(S.home)
	task.wait(1)
	local hum = humanoid()
	if hum then pcall(function() hum:UnequipTools() end) end
	task.wait(BANK_WAIT)
end

local function cycle(): boolean
	local target = pickTarget()
	if not target then
		notify("No steal prompt found.")
		return false
	end
	local grabbed = grab(target)
	task.wait(GRAB_WAIT)
	if S.on then bankHome() end
	return grabbed
end

--// ------------------------------ control ------------------------------

function S.start()
	if S.on then return end
	local root = hrp()
	if not root then notify("No character yet - respawn and retry.") return end
	S.home = HOME or root.Position
	S.on = true
	refresh()
	notify("Auto Steal ON (" .. S.mode .. ")")
	task.spawn(function()
		while S.on do
			local ok, grabbed = pcall(cycle)
			if ok and grabbed then notify("Grabbed", 2) end
			task.wait(LOOP_DELAY)
		end
		refresh()
		notify("Auto Steal OFF", 2)
	end)
end

function S.stop() S.on = false end
function S.toggle() if S.on then S.stop() else S.start() end end
function S.setMode(m)
	S.mode = (m == "Field") and "Field" or "Pen"
	refresh()
end
function S.cycleMode() S.setMode(S.mode == "Pen" and "Field" or "Pen") end

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

local function wireHub()
	local hub = CoreGui:FindFirstChild("SAEHub")
	local mainFrame = hub and hub:FindFirstChildWhichIsA("Frame")
	if not mainFrame or mainFrame:FindFirstChild("AutoStealHubBtn") then return end
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
-- If the hub opens later, attach then too.
local hubConn = CoreGui.ChildAdded:Connect(function(child)
	if child.Name == "SAEHub" then task.wait(0.5) pcall(wireHub) refresh() end
end)

_G.__AutoStealUICleanup = function()
	S.on = false
	pcall(function() hubConn:Disconnect() end)
	pcall(function() gui:Destroy() end)
	local hub = CoreGui:FindFirstChild("SAEHub")
	local mf = hub and hub:FindFirstChildWhichIsA("Frame")
	local hb = mf and mf:FindFirstChild("AutoStealHubBtn")
	if hb then pcall(function() hb:Destroy() end) end
end

refresh()
notify("Auto Steal UI loaded", 3)
