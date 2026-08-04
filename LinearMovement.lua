--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local WALK_SPEED = 16       -- horizontal speed in studs/s (16 = vanilla)
local JUMP_VELOCITY = 48    -- upward launch speed
local JUMP_HOLD = 0.04      -- how long the launch is held before gravity takes over
local JUMP_COOLDOWN = 0.18  -- minimum time between jumps
local AIR_CONTROL = true    -- allow steering while airborne
local MOVE_FORCE = math.huge -- lower this (e.g. 25000) if you want knockback/explosions to shove you while walking

local STEP_ASSIST = true    -- glide up small ledges/stairs instead of getting stuck
local STEP_HEIGHT = 3       -- tallest ledge that counts as a step (studs)
local STEP_PROBE = 1.8      -- how far ahead to look for a step (studs)
local STEP_UP_SPEED = 16    -- max rise rate while clearing a step
local GROUND_TOLERANCE = 0.9 -- feet-to-floor gap still counted as grounded

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local attachment: Attachment? = nil
local moveLV: LinearVelocity? = nil
local jumpLV: LinearVelocity? = nil
local stepLV: LinearVelocity? = nil
local runTrack: AnimationTrack? = nil
local rayParams: RaycastParams? = nil

local jumpDebounce = false
local stepping = false
local stepTargetY = 0
local stepDeadline = 0

local connections: { RBXScriptConnection } = {}

local function teardown()
	if moveLV then moveLV:Destroy() moveLV = nil end
	if jumpLV then jumpLV:Destroy() jumpLV = nil end
	if stepLV then stepLV:Destroy() stepLV = nil end
	if attachment then attachment:Destroy() attachment = nil end
end

if _G.__LinearMovementCleanup then
	pcall(_G.__LinearMovementCleanup)
end

local function purgeOld(part: BasePart)
	for _, c in ipairs(part:GetChildren()) do
		local n = c.Name
		if n == "LinearMoveAttachment" or n == "LinearMove" or n == "LinearJump" or n == "LinearStep" then
			c:Destroy()
		end
	end
end

local function newLine(att: Attachment, name: string): LinearVelocity
	local lv = Instance.new("LinearVelocity")
	lv.Name = name
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = Vector3.new(0, 1, 0)
	lv.MaxForce = math.huge
	lv.LineVelocity = 0
	lv.Enabled = false
	return lv
end

local function build()
	teardown()
	if not rootPart then
		return
	end
	purgeOld(rootPart)

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
	move.MaxForce = MOVE_FORCE
	move.PlaneVelocity = Vector2.zero
	move.Enabled = false
	move.Parent = rootPart

	local jump = newLine(att, "LinearJump")
	jump.Parent = rootPart
	local step = newLine(att, "LinearStep")
	step.Parent = rootPart

	attachment = att
	moveLV = move
	jumpLV = jump
	stepLV = step
end

local function setupAnim(char: Model)
	runTrack = nil
	local hum = humanoid
	if not hum then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animId: string? = nil
	local animate = char:FindFirstChild("Animate")
	if animate then
		for _, d in ipairs(animate:GetDescendants()) do
			if d:IsA("Animation") and d.AnimationId ~= "" and (string.find(d.Name:lower(), "run")) then
				animId = d.AnimationId
				break
			end
		end
		if not animId then
			for _, d in ipairs(animate:GetDescendants()) do
				if d:IsA("Animation") and d.AnimationId ~= "" and (string.find(d.Name:lower(), "walk")) then
					animId = d.AnimationId
					break
				end
			end
		end
	end
	if not animId or animId == "" then
		animId = "rbxassetid://913376220"
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		pcall(function()
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = true
		end)
		runTrack = track
	end
end

local function updateAnim(active: boolean)
	local track = runTrack
	if not track then
		return
	end
	if active then
		if not track.IsPlaying then
			pcall(function() track:Play(0.1) end)
		end
		pcall(function() track:AdjustSpeed(math.clamp(WALK_SPEED / 16, 0.5, 3)) end)
	elseif track.IsPlaying then
		pcall(function() track:Stop(0.15) end)
	end
end

local function onCharacterAdded(char: Model)
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	build()
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	rayParams = params

	stepping = false
	setupAnim(char)
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

local function feetY(): number?
	local hrp = rootPart
	local hum = humanoid
	if not hrp or not hum then
		return nil
	end
	return hrp.Position.Y - (hrp.Size.Y / 2 + hum.HipHeight)
end

-- returns floor top Y and the floor part beneath the character (or nil, nil)
local function groundInfo(): (number?, BasePart?)
	local hrp = rootPart
	local hum = humanoid
	if not hrp or not hum or not rayParams then
		return nil, nil
	end
	local reach = hrp.Size.Y / 2 + hum.HipHeight + 2.5
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -reach, 0), rayParams)
	if not hit then
		return nil, nil
	end
	return hit.Position.Y, hit.Instance :: BasePart
end

-- true only if there is a genuine climbable step (vertical face + walkable top within STEP_HEIGHT)
local function detectStep(flat: Vector3, floorTopY: number): number?
	local hrp = rootPart
	if not hrp or not rayParams then
		return nil
	end
	local faceOrigin = Vector3.new(hrp.Position.X, floorTopY + 0.2, hrp.Position.Z)
	local face = workspace:Raycast(faceOrigin, flat * STEP_PROBE, rayParams)
	if not face then
		return nil
	end
	if math.abs(face.Normal.Y) > 0.35 then
		return nil -- inclined surface (ramp), not a step: let the horizontal push climb it
	end
	local ahead = face.Position + flat * 0.5
	local topOrigin = Vector3.new(ahead.X, floorTopY + STEP_HEIGHT + 1.0, ahead.Z)
	local top = workspace:Raycast(topOrigin, Vector3.new(0, -(STEP_HEIGHT + 1.5), 0), rayParams)
	if not top then
		return nil -- no surface on top (railing / thin lip / overhang)
	end
	if top.Normal.Y < 0.7 then
		return nil -- top is not walkable
	end
	local h = top.Position.Y - floorTopY
	if h < 0.15 or h > STEP_HEIGHT then
		return nil
	end
	return top.Position.Y
end

local function stopStep()
	stepping = false
	if stepLV and stepLV.Parent then
		stepLV.Enabled = false
		stepLV.LineVelocity = 0
	end
end

local function disableAll()
	if moveLV and moveLV.Parent then
		moveLV.Enabled = false
		moveLV.PlaneVelocity = Vector2.zero
	end
	if jumpLV and jumpLV.Parent then
		jumpLV.Enabled = false
		jumpLV.LineVelocity = 0
	end
	stopStep()
end

local function isGroundedNow(): boolean
	local topY = groundInfo()
	local fy = feetY()
	return topY ~= nil and fy ~= nil and (fy - topY) <= GROUND_TOLERANCE
end

local function doJump()
	local jump = jumpLV
	local hum = humanoid
	if jumpDebounce or not jump or not jump.Parent or not hum then
		return
	end
	if hum.Health <= 0 or stateBlocksMovement() or not isGroundedNow() then
		return
	end
	stopStep() -- never let jump and step drive the Y axis in the same frame
	jumpDebounce = true
	jump.LineVelocity = JUMP_VELOCITY
	jump.Enabled = true
	task.delay(JUMP_HOLD, function()
		if jumpLV == jump and jump.Parent then
			jump.Enabled = false
			jump.LineVelocity = 0
		end
	end)
	task.delay(JUMP_COOLDOWN, function()
		jumpDebounce = false
	end)
end

table.insert(connections, UserInputService.JumpRequest:Connect(doJump))

table.insert(connections, RunService.Heartbeat:Connect(function()
	local move = moveLV
	local hum = humanoid
	local hrp = rootPart
	if not move or not move.Parent or not hum or not hrp then
		return
	end

	if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
	if hum.JumpPower ~= 0 then hum.JumpPower = 0 end
	if not hum.AutoRotate then hum.AutoRotate = true end

	if hum.Health <= 0 or stateBlocksMovement() then
		disableAll()
		updateAnim(false)
		return
	end

	local floorTopY, floorPart = groundInfo()
	local fy = feetY()
	local grounded = floorTopY ~= nil and fy ~= nil and (fy - floorTopY) <= GROUND_TOLERANCE

	local dir = hum.MoveDirection
	local moving = dir.Magnitude > 0.01
	local flat = moving and Vector3.new(dir.X, 0, dir.Z).Unit or Vector3.zero

	-- step assist (decide first so movement can keep pushing forward through a step)
	local jumping = jumpLV ~= nil and jumpLV.Enabled
	if not STEP_ASSIST or jumping or not moving then
		stopStep()
	elseif stepping then
		local nowFy = feetY()
		if nowFy == nil or nowFy >= stepTargetY - 0.1 or tick() > stepDeadline then
			stopStep()
		elseif stepLV and stepLV.Parent then
			stepLV.LineVelocity = math.clamp((stepTargetY - nowFy) * 8, 3, STEP_UP_SPEED)
			stepLV.Enabled = true
		end
	elseif grounded and floorTopY and fy then
		local topY = detectStep(flat, floorTopY)
		if topY and stepLV and stepLV.Parent then
			stepping = true
			stepTargetY = topY
			stepDeadline = tick() + 0.6
			stepLV.LineVelocity = math.clamp((topY - fy) * 8, 3, STEP_UP_SPEED)
			stepLV.Enabled = true
		else
			stopStep()
		end
	else
		stopStep()
	end

	-- horizontal movement (inherit the floor part's motion so moving platforms carry you)
	local fvx, fvz = 0, 0
	if grounded and floorPart then
		local ok, v = pcall(function()
			return floorPart:GetVelocityAtPosition(Vector3.new(hrp.Position.X, floorTopY, hrp.Position.Z))
		end)
		if ok and v then
			fvx, fvz = v.X, v.Z
		end
	end

	if moving and (grounded or AIR_CONTROL or stepping) then
		move.PlaneVelocity = Vector2.new(dir.X * WALK_SPEED + fvx, dir.Z * WALK_SPEED + fvz)
		move.Enabled = true
	elseif grounded then
		-- idle on ground: hold position (crisp stop) or ride the platform, no coasting
		move.PlaneVelocity = Vector2.new(fvx, fvz)
		move.Enabled = true
	else
		-- idle in the air: keep natural momentum, let external forces act
		move.Enabled = false
		move.PlaneVelocity = Vector2.zero
	end

	updateAnim(moving and grounded)
end))

local function cleanup()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	stopStep()
	teardown()
	local hum = humanoid
	if hum then
		pcall(function() hum.WalkSpeed = 16 end)
	end
	local track = runTrack
	if track then
		pcall(function() track:Stop(0) end)
	end
	runTrack = nil
	_G.__LinearMovementCleanup = nil
end
_G.__LinearMovementCleanup = cleanup

if player.Character then
	onCharacterAdded(player.Character)
end
table.insert(connections, player.CharacterAdded:Connect(onCharacterAdded))
