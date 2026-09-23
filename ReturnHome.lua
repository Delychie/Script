--!nonstrict

-- ReturnHome: press V to go back to your base, press V again to cancel.
-- Uses the bundle's hop-train (steal_run.luau hopTo): teleport HOP studs every STEP_WAIT
-- seconds at a locked height, then land on home. No velocity mover.
-- Home is where you're standing when you run this, so run it at your base (or set HOME).

local KEY       = Enum.KeyCode.V
local HOP       = 30     -- studs per hop (bundle: 30)
local STEP_WAIT = 0.05   -- seconds between hops (bundle: 0.05) -> ~600 studs/s
local FLY_Y     = nil    -- locked travel height; nil = home's height (bundle: 70.5)
local HOME      = nil    -- Vector3; nil = your position when the script runs

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

if _G.__ReturnHomeCleanup then
	pcall(_G.__ReturnHomeCleanup)
end

local connections: { RBXScriptConnection } = {}
local home: Vector3? = HOME
local returning = false
local runId = 0

local function notify(text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Return Home", Text = text, Duration = 3 })
	end)
end

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function tp(pos: Vector3)
	local hrp = rootPart()
	if hrp then
		hrp.CFrame = CFrame.new(pos) * hrp.CFrame.Rotation
	end
end

local function goHome()
	runId += 1
	local myRun = runId
	returning = true

	local hrp = rootPart()
	if not hrp or not home then
		returning = false
		return
	end

	local y = FLY_Y or home.Y
	local p = hrp.Position
	local d = Vector3.new(home.X - p.X, 0, home.Z - p.Z)
	local steps = math.max(1, math.floor(d.Magnitude / HOP))
	for i = 1, steps do
		if runId ~= myRun then return end
		local t = i / steps
		tp(Vector3.new(p.X + d.X * t, y, p.Z + d.Z * t))
		task.wait(STEP_WAIT)
	end
	if runId ~= myRun then return end
	tp(home)
	returning = false
	notify("Home")
end

local function cancel()
	runId += 1
	returning = false
end

local function captureHome()
	if home then return end
	local hrp = rootPart()
	if not hrp then
		local char = player.Character or player.CharacterAdded:Wait()
		hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	end
	if hrp then
		home = hrp.Position
	end
end

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= KEY then return end
	if returning then
		cancel()
		notify("Cancelled")
	elseif home then
		notify("Going home")
		task.spawn(goHome)
	end
end))

table.insert(connections, player.CharacterAdded:Connect(cancel))

_G.__ReturnHomeCleanup = function()
	cancel()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
end

task.spawn(function()
	captureHome()
	notify("Loaded - V hops home (" .. HOP .. " studs / " .. STEP_WAIT .. "s)")
end)
