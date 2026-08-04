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
local MOVE_FORCE = 25000    -- movement authority; raise for snappier/heavier control, lower to let knockback/explosions shove you

local STEP_ASSIST = true    -- glide up small ledges/stairs instead of getting stuck
local STEP_HEIGHT = 3       -- tallest ledge that counts as a step (studs)
local STEP_PROBE = 1.8      -- how far ahead to look for a step (studs)
local STEP_UP_SPEED = 16    -- max rise rate while clearing a step
local GROUND_TOLERANCE = 0.9 -- feet-to-floor gap still counted as grounded
local FLOOR_VEL_DEADZONE = 0.25 -- ignore floor velocities smaller than this (kills jitter from settling parts)

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local attachment: Attachment? = nil
local moveLV: LinearVelocity? = nil
local jumpLV: LinearVelocity? = nil
local stepLV: LinearVelocity? = nil
local runTrack: AnimationTrack? = nil
local rayParams: RaycastParams? = nil

local footOffset = 3        -- HRP-centre to sole distance (recomputed per character / rig)
local jumpDebounce = false
local stepping = false
local stepTargetY = 0
local stepDeadline = 0
local airFloorVX, airFloorVZ = 0, 0 -- platform velocity retained through a jump

local connections: { RBXScriptConnection } = {}
local alive = true

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

local function computeFootOffset(char: Model, hum: Humanoid, hrp: BasePart): number
	local off = hrp.Size.Y / 2 + hum.HipHeight
	if hum.RigType == Enum.HumanoidRigType.R6 then
		local leg = char:FindFirstChild("Left Leg") or char:FindFirstChild("Right Leg")
		if leg and leg:IsA("BasePart") then
			off += leg.Size.Y
		end
	end
	return off
end

local function setupAnim(char: Model)
	runTrack = nil
	local myHum = humanoid
	if not myHum then
		return
	end
	task.spawn(function()
		local animator = myHum:FindFirstChildOfClass("Animator") or myHum:WaitForChild("Animator", 5)
		if not alive or humanoid ~= myHum or not animator then
			return
		end
		local animId: string? = nil
		local animate = char:FindFirstChild("Animate")
		if animate then
			for _, d in ipairs(animate:GetDescendants()) do
				if d:IsA("Animation") and d.AnimationId ~= "" and string.find(d.Name:lower(), "run") then
					animId = d.AnimationId
					break
				end
			end
			if not animId then
				for _, d in ipairs(animate:GetDescendants()) do
					if d:IsA("Animation") and d.AnimationId ~= "" then
						local n = d.Name:lower()
						if string.find(n, "walk") or string.find(n, "jog") or string.find(n, "sprint") or string.find(n, "loco") then
							animId = d.AnimationId
							break
						end
					end
				end
			end
		end
		if not animId or animId == "" then
			animId = (myHum.RigType == Enum.HumanoidRigType.R6) and "rbxassetid://180426354" or "rbxassetid://913376220"
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not alive or humanoid ~= myHum then
			return
		end
		if ok and track then
			pcall(function()
				track.Priority = Enum.AnimationPriority.Movement
				track.Looped = true
			end)
			runTrack = track
		end
	end)
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
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not alive or not hum then
		return
	end
	local hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not alive or not hrp then
		return
	end
	humanoid = hum
	rootPart = hrp
	footOffset = computeFootOffset(char, hum, hrp)
	build()
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.AutoRotate = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	rayParams = params

	jumpDebounce = false
	stepping = false
	airFloorVX, airFloorVZ = 0, 0
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
	if not hrp then
		return nil
	end
	return hrp.Position.Y - footOffset
end

-- returns floor top Y and the floor part beneath the character (or nil, nil)
local function groundInfo(): (number?, BasePart?)
	local hrp = rootPart
	if not hrp or not rayParams then
		return nil, nil
	end
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(footOffset + 2.5), 0), rayParams)
	if not hit then
		return nil, nil
	end
	return hit.Position.Y, hit.Instance :: BasePart
end

-- true only for a genuine climbable step (vertical face + walkable top within STEP_HEIGHT)
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
		return nil -- inclined surface (ramp): let the horizontal push climb it, don't force lift
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
	if hum.JumpHeight ~= 0 then hum.JumpHeight = 0 end
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

	-- step assist (decided first so the movement branch can keep pushing forward through a step)
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
		if topY and (topY - fy) > 0.25 and stepLV and stepLV.Parent then
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

	-- floor (platform) velocity so moving platforms carry you; retained through a jump
	local fvx, fvz = 0, 0
	if grounded and floorPart and floorTopY then
		local ok, v = pcall(function()
			return floorPart:GetVelocityAtPosition(Vector3.new(hrp.Position.X, floorTopY, hrp.Position.Z))
		end)
		if ok and v then
			fvx = math.abs(v.X) > FLOOR_VEL_DEADZONE and v.X or 0
			fvz = math.abs(v.Z) > FLOOR_VEL_DEADZONE and v.Z or 0
		end
		airFloorVX, airFloorVZ = fvx, fvz
	end
	local baseVX = grounded and fvx or airFloorVX
	local baseVZ = grounded and fvz or airFloorVZ

	if moving and (grounded or AIR_CONTROL or stepping) then
		move.PlaneVelocity = Vector2.new(dir.X * WALK_SPEED + baseVX, dir.Z * WALK_SPEED + baseVZ)
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
	alive = false
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	stopStep()
	teardown()
	local hum = humanoid
	if hum then
		pcall(function()
			hum.WalkSpeed = 16
			hum.JumpPower = 50
			hum.JumpHeight = 7.2
			hum.AutoRotate = true
		end)
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
