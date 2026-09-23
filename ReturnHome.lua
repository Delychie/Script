--!nonstrict

-- ReturnHome: press V to walk back to your base. It moves you with the same LinearVelocity
-- plane mover as SpeedBooster's Auto Left/Right (no teleport, no AssemblyLinearVelocity
-- writes) at your walkspeed, and stops when you arrive. Press V again to cancel.
-- Home is where you're standing when you run this, so run it at your base (or set HOME).

local KEY    = Enum.KeyCode.V
local SPEED  = 800   -- studs/s; 0 = use your Humanoid.WalkSpeed
local HOME   = nil   -- Vector3; nil = your position when the script runs
local ARRIVE = 2.5   -- stop within this many studs of home (flat distance)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

if _G.__ReturnHomeCleanup then
	pcall(_G.__ReturnHomeCleanup)
end

local connections: { RBXScriptConnection } = {}
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local attachment: Attachment? = nil
local mover: LinearVelocity? = nil
local returning = false
local home: Vector3? = HOME
local stuckTime = 0

local function notify(text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Return Home", Text = text, Duration = 3 })
	end)
end

local function speedLabel(): string
	return SPEED > 0 and (tostring(SPEED) .. " studs/s") or "your WalkSpeed"
end

local function stop()
	returning = false
	stuckTime = 0
	if mover then
		mover.Enabled = false
		mover.PlaneVelocity = Vector2.zero
	end
end

local function teardown()
	if mover then mover:Destroy() mover = nil end
	if attachment then attachment:Destroy() attachment = nil end
end

local function build(char: Model)
	teardown()
	stop()
	humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid?
	rootPart = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not rootPart then return end

	local att = Instance.new("Attachment")
	att.Name = "ReturnHomeAttachment"
	att.Parent = rootPart

	-- World XZ plane only: Y is never driven, so gravity and jumping work normally.
	local lv = Instance.new("LinearVelocity")
	lv.Name = "ReturnHomeVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.MaxForce = math.huge
	lv.PlaneVelocity = Vector2.zero
	lv.Enabled = false
	lv.Parent = rootPart

	attachment = att
	mover = lv
	if not home then
		home = rootPart.Position
	end
end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	if not returning then return end
	local hum, hrp, lv = humanoid, rootPart, mover
	if not hum or not hrp or not lv or not lv.Parent or not home or hum.Health <= 0 then
		stop()
		return
	end

	-- Let knockback / ragdoll play out instead of fighting it.
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
		lv.Enabled = false
		return
	end

	local pos = hrp.Position
	local flat = Vector3.new(home.X - pos.X, 0, home.Z - pos.Z)
	if flat.Magnitude < ARRIVE then
		stop()
		notify("Home")
		return
	end

	local spd = SPEED > 0 and SPEED or hum.WalkSpeed
	-- Ease off near home so a high speed doesn't overshoot and jitter around it.
	spd = math.min(spd, flat.Magnitude * 10)
	if spd <= 0 then
		lv.Enabled = false
		return
	end

	local dir = flat.Unit
	lv.PlaneVelocity = Vector2.new(dir.X * spd, dir.Z * spd)
	lv.Enabled = true

	-- Blocked by a ledge or wall: hop over it.
	local v = hrp.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude < spd * 0.25 then
		stuckTime += dt
		if stuckTime > 0.4 then
			hum.Jump = true
			stuckTime = 0
		end
	else
		stuckTime = 0
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= KEY then return end
	if returning then
		stop()
		notify("Cancelled")
	elseif home and mover then
		returning = true
		stuckTime = 0
		notify("Going home at " .. speedLabel())
	end
end))

table.insert(connections, player.CharacterAdded:Connect(function(char)
	build(char)
end))

if player.Character then
	task.spawn(build, player.Character)
end

_G.__ReturnHomeCleanup = function()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	stop()
	teardown()
end

notify("Loaded - V goes home at " .. speedLabel())
