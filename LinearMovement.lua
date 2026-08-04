--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local WALK_SPEED = 16      -- horizontal speed in studs/s (16 = vanilla)
local JUMP_VELOCITY = 48   -- upward launch speed
local JUMP_HOLD = 0.04     -- how long the launch is held before gravity takes over
local AIR_CONTROL = true   -- allow steering while airborne

local STEP_ASSIST = true   -- glide up small ledges/stairs instead of getting stuck
local STEP_HEIGHT = 3      -- tallest ledge that counts as a step (studs)
local STEP_PROBE = 1.6     -- how far ahead to look for a step (studs)
local STEP_UP_SPEED = 14   -- how fast you rise over a step

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local attachment: Attachment? = nil
local moveLV: LinearVelocity? = nil
local jumpLV: LinearVelocity? = nil
local stepLV: LinearVelocity? = nil
local jumpDebounce = false
local rayParams: RaycastParams? = nil

local function teardown()
	if moveLV then moveLV:Destroy() moveLV = nil end
	if jumpLV then jumpLV:Destroy() jumpLV = nil end
	if stepLV then stepLV:Destroy() stepLV = nil end
	if attachment then attachment:Destroy() attachment = nil end
end

local function build()
	teardown()
	if not rootPart then
		return
	end

	local att = Instance.new("Attachment")
	att.Name = "LinearMoveAttachment"
	att.Parent = rootPart

	local move = Instance.new("LinearVelocity")
	move.Name = "LinearMove"
	move.Attachment0 = att
	move.RelativeTo = Enum.ActuatorRelativeTo.World
	move.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	move.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	move.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	move.MaxForce = math.huge
	move.PlaneVelocity = Vector2.zero
	move.Enabled = false
	move.Parent = rootPart

	local jump = Instance.new("LinearVelocity")
	jump.Name = "LinearJump"
	jump.Attachment0 = att
	jump.RelativeTo = Enum.ActuatorRelativeTo.World
	jump.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	jump.LineDirection = Vector3.new(0, 1, 0)
	jump.MaxForce = math.huge
	jump.LineVelocity = 0
	jump.Enabled = false
	jump.Parent = rootPart

	local step = Instance.new("LinearVelocity")
	step.Name = "LinearStep"
	step.Attachment0 = att
	step.RelativeTo = Enum.ActuatorRelativeTo.World
	step.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	step.LineDirection = Vector3.new(0, 1, 0)
	step.MaxForce = math.huge
	step.LineVelocity = 0
	step.Enabled = false
	step.Parent = rootPart

	attachment = att
	moveLV = move
	jumpLV = jump
	stepLV = step
end

local function onCharacterAdded(newCharacter: Model)
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	build()
	humanoid.WalkSpeed = 0
	pcall(function() humanoid.JumpPower = 0 end)
	pcall(function() humanoid.JumpHeight = 0 end)
	humanoid.AutoRotate = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { newCharacter }
	params.IgnoreWater = true
	rayParams = params
end

local function groundY(): number?
	local hrp = rootPart
	local hum = humanoid
	if not hrp or not hum or not rayParams then
		return nil
	end
	local reach = hrp.Size.Y / 2 + hum.HipHeight + 2.5
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -reach, 0), rayParams)
	return hit and hit.Position.Y or nil
end

local function needsStep(dir: Vector3): boolean
	if not STEP_ASSIST then
		return false
	end
	local hrp = rootPart
	if not hrp or not rayParams then
		return false
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return false
	end
	flat = flat.Unit
	local gy = groundY()
	if not gy then
		return false
	end
	local low = workspace:Raycast(
		Vector3.new(hrp.Position.X, gy + 0.25, hrp.Position.Z),
		flat * STEP_PROBE, rayParams)
	if not low then
		return false
	end
	local high = workspace:Raycast(
		Vector3.new(hrp.Position.X, gy + STEP_HEIGHT + 0.1, hrp.Position.Z),
		flat * STEP_PROBE, rayParams)
	return high == nil
end

local function stateBlocksMovement(): boolean
	local hum = humanoid
	if not hum then
		return true
	end
	local st = hum:GetState()
	return st == Enum.HumanoidStateType.Ragdoll
		or st == Enum.HumanoidStateType.Physics
		or st == Enum.HumanoidStateType.FallingDown
		or st == Enum.HumanoidStateType.Seated
		or st == Enum.HumanoidStateType.Dead
end

local function isGrounded(): boolean
	local hum = humanoid
	if not hum then
		return false
	end
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
		return false
	end
	return hum.FloorMaterial ~= Enum.Material.Air
end

local function doJump()
	local jump = jumpLV
	local hum = humanoid
	if jumpDebounce or not jump or not jump.Parent or not hum then
		return
	end
	if hum.Health <= 0 or stateBlocksMovement() or not isGrounded() then
		return
	end
	jumpDebounce = true
	jump.LineVelocity = JUMP_VELOCITY
	jump.Enabled = true
	task.delay(JUMP_HOLD, function()
		if jumpLV == jump and jump.Parent then
			jump.Enabled = false
			jump.LineVelocity = 0
		end
	end)
	task.delay(0.2, function()
		jumpDebounce = false
	end)
end

UserInputService.JumpRequest:Connect(doJump)

RunService.Heartbeat:Connect(function()
	local move = moveLV
	local hum = humanoid
	local hrp = rootPart
	if not move or not move.Parent or not hum or not hrp then
		return
	end

	if hum.WalkSpeed ~= 0 then
		hum.WalkSpeed = 0
	end

	local function clearStep()
		if stepLV and stepLV.Parent then
			stepLV.Enabled = false
			stepLV.LineVelocity = 0
		end
	end

	if hum.Health <= 0 or stateBlocksMovement() then
		move.Enabled = false
		move.PlaneVelocity = Vector2.zero
		clearStep()
		return
	end

	if not AIR_CONTROL and not isGrounded() then
		move.Enabled = false
		move.PlaneVelocity = Vector2.zero
		clearStep()
		return
	end

	local dir = hum.MoveDirection
	if dir.Magnitude > 0.01 then
		move.PlaneVelocity = Vector2.new(dir.X * WALK_SPEED, dir.Z * WALK_SPEED)
		move.Enabled = true
	else
		move.PlaneVelocity = Vector2.zero
		move.Enabled = false
	end

	local jumping = jumpLV ~= nil and jumpLV.Enabled
	if move.Enabled and not jumping and needsStep(dir) then
		if stepLV and stepLV.Parent then
			stepLV.LineVelocity = STEP_UP_SPEED
			stepLV.Enabled = true
		end
	else
		clearStep()
	end
end)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
