--!nonstrict

-- LinearMovement: boosts your movement through a LinearVelocity constraint layered
-- ON TOP of normal humanoid movement. Native walking still handles animation, jumping,
-- slopes, stairs, rooting and the game's own WalkSpeed (e.g. carry slow-downs); the
-- constraint only kicks in when your effective speed is above the game's, and drives
-- the extra speed. When you are not boosting it does nothing, so movement stays vanilla.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Speed: effective = SPEED_FIXED (if > 0) else the game's current WalkSpeed * SPEED_MULT.
-- Multiply mode respects carry slow-downs / boosts and never fights the game's rooting.
local SPEED_MULT = 1        -- multiplier on the game's live WalkSpeed (1 = vanilla speed; raise it to go faster)
local SPEED_FIXED = 0       -- if > 0, move at exactly this speed instead of multiplying

local AIR_CONTROL = true    -- steer while airborne (only matters while boosting)
-- Dominance: force other scripts' movement off so only this one moves you.
-- SUPPRESS_OTHER wipes foreign BodyVelocity/LinearVelocity/etc off your HRP each frame.
-- MASK_WALKSPEED (>0) pins WalkSpeed to that value so other scripts' WalkSpeed spikes are hidden;
-- pair it with SPEED_FIXED for your real speed. NOTE: neither can hide a raw AssemblyLinearVelocity
-- write or beat a server displacement check - for those, disable the other script's mover instead.
local SUPPRESS_OTHER = false
local MASK_WALKSPEED = 0
-- Executor-only: no-op ANY Lua write to Velocity / AssemblyLinearVelocity on your HRP, so other
-- scripts (e.g. del hub) that move you by writing velocity are neutralised and only this constraint
-- moves you. Needs hookmetamethod + newcclosure. Read the caveats before enabling it.
local BLOCK_FOREIGN_VELOCITY = false
local SLOPE_GLUE = true     -- hug slopes instead of launching off them at high speed
local STEP_ASSIST = true    -- glide up small ledges/stairs while boosting
local STEP_HEIGHT = 3       -- tallest ledge treated as a step (studs)
local STEP_PROBE = 1.8      -- base look-ahead for a step (studs; grows with speed)
local STEP_UP_SPEED = 40    -- base rise rate over a step (studs/s; grows with speed)
local GROUND_TOLERANCE = 0.9
local FLOOR_VEL_DEADZONE = 0.25

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local attachment: Attachment? = nil
local moveLV: LinearVelocity? = nil
local stepLV: LinearVelocity? = nil
local rayParams: RaycastParams? = nil

local footOffset = 3
local stepping = false
local stepTargetY = 0
local stepDeadline = 0
local jumpSuppressUntil = 0
local knockUntil = 0
local lastGlueTime = 0
local lastGlueVy = 0
local airFloorVX, airFloorVZ = 0, 0
local charGen = 0

local KNOCK_THRESHOLD = 50   -- horizontal speed over expected that counts as external knockback

local connections: { RBXScriptConnection } = {}
local alive = true

local function teardown()
	if moveLV then moveLV:Destroy() moveLV = nil end
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
	move.MaxForce = math.huge
	move.PlaneVelocity = Vector2.zero
	move.Enabled = false
	move.Parent = rootPart

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
	stepLV = step
end

local function computeFootOffset(char: Model, hum: Humanoid, hrp: BasePart): number
	local off = hrp.Size.Y / 2 + hum.HipHeight
	if hum.RigType == Enum.HumanoidRigType.R6 then
		local leg = char:FindFirstChild("Left Leg") or char:FindFirstChild("Right Leg")
		if leg and leg:IsA("BasePart") then
			off += leg.Size.Y
		else
			off = math.max(off, 3)
		end
	end
	return off
end

local function onCharacterAdded(char: Model)
	charGen += 1
	local myGen = charGen
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	if not alive or myGen ~= charGen or not hum then
		return
	end
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	if not alive or myGen ~= charGen or not hrp then
		return
	end
	humanoid = hum
	rootPart = hrp
	footOffset = computeFootOffset(char, hum, hrp)
	build()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	rayParams = params

	stepping = false
	jumpSuppressUntil = 0
	knockUntil = 0
	lastGlueTime = 0
	airFloorVX, airFloorVZ = 0, 0

	-- also suppress step-assist on programmatic jumps (not just JumpRequest input)
	table.insert(connections, hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			jumpSuppressUntil = tick() + 0.25
			stopStep()
		end
	end))
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
		or st == Enum.HumanoidStateType.Climbing
		or st == Enum.HumanoidStateType.Swimming
		or st == Enum.HumanoidStateType.PlatformStanding
		or st == Enum.HumanoidStateType.GettingUp
		or st == Enum.HumanoidStateType.Dead
end

local function feetY(): number?
	local hrp = rootPart
	if not hrp then
		return nil
	end
	return hrp.Position.Y - footOffset
end

-- floor top Y, the floor part, and the floor normal beneath the character
local function groundInfo(): (number?, BasePart?, Vector3?)
	local hrp = rootPart
	if not hrp or not rayParams then
		return nil, nil, nil
	end
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(footOffset + 2.5), 0), rayParams)
	if not hit then
		return nil, nil, nil
	end
	return hit.Position.Y, hit.Instance :: BasePart, hit.Normal
end

-- genuine climbable step (near-vertical face + walkable top within STEP_HEIGHT)
local function detectStep(flat: Vector3, floorTopY: number, probe: number): number?
	local hrp = rootPart
	if not hrp or not rayParams then
		return nil
	end
	local faceOrigin = Vector3.new(hrp.Position.X, floorTopY + 0.2, hrp.Position.Z)
	local face = workspace:Raycast(faceOrigin, flat * probe, rayParams)
	if not face then
		return nil
	end
	if math.abs(face.Normal.Y) > 0.35 then
		return nil -- ramp, handled by slope glue
	end
	local ahead = face.Position + flat * 0.5
	local topOrigin = Vector3.new(ahead.X, floorTopY + STEP_HEIGHT + 1.0, ahead.Z)
	local top = workspace:Raycast(topOrigin, Vector3.new(0, -(STEP_HEIGHT + 1.5), 0), rayParams)
	if not top or top.Normal.Y < 0.7 then
		return nil
	end
	local h = top.Position.Y - floorTopY
	if h < 0.15 or h > STEP_HEIGHT then
		return nil
	end
	return top.Position.Y
end

local OURS = { LinearMove = true, LinearStep = true, LinearMoveAttachment = true }
local function suppressForeign()
	local hrp = rootPart
	if not hrp then
		return
	end
	for _, d in ipairs(hrp:GetChildren()) do
		if not OURS[d.Name] and (d:IsA("BodyMover") or d:IsA("Constraint")) then
			d:Destroy()
		end
	end
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
	airFloorVX, airFloorVZ = 0, 0
	stopStep()
end

table.insert(connections, UserInputService.JumpRequest:Connect(function()
	jumpSuppressUntil = tick() + 0.25
	stopStep()
end))

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	local move = moveLV
	local hum = humanoid
	local hrp = rootPart
	if not move or not move.Parent or not hum or not hrp then
		return
	end

	if SUPPRESS_OTHER then
		suppressForeign()
	end
	if MASK_WALKSPEED > 0 and hum.WalkSpeed ~= MASK_WALKSPEED then
		hum.WalkSpeed = MASK_WALKSPEED
	end

	if hum.Health <= 0 or stateBlocksMovement() then
		disableAll()
		return
	end

	local gameWS = hum.WalkSpeed
	local rooted = gameWS <= 0.01
	local effectiveSpeed = (SPEED_FIXED > 0) and SPEED_FIXED or (gameWS * SPEED_MULT)
	local boosting = (not rooted) and effectiveSpeed > gameWS + 0.1

	if not boosting then
		-- vanilla native movement handles everything (speed, slopes, stairs, anim, rooting)
		disableAll()
		return
	end

	local floorTopY, floorPart, floorNormal = groundInfo()
	local fy = feetY()
	local grounded = floorTopY ~= nil and fy ~= nil and (fy - floorTopY) <= GROUND_TOLERANCE

	local dir = hum.MoveDirection
	local moving = dir.Magnitude > 0.01
	local flat = moving and Vector3.new(dir.X, 0, dir.Z).Unit or Vector3.zero
	local liftCap = math.max(STEP_UP_SPEED, effectiveSpeed)

	-- vertical control via stepLV: step-assist (climb ledges) + slope-glue (hug ramps).
	-- an in-progress step is NOT gated on grounded (it lifts you off the ground by design).
	local now = tick()
	if now < jumpSuppressUntil or not moving then
		stopStep()
	elseif stepping then
		local nowFy = feetY()
		if nowFy == nil or nowFy >= stepTargetY - 0.1 or now > stepDeadline then
			stopStep()
		elseif stepLV and stepLV.Parent then
			stepLV.LineVelocity = math.clamp((stepTargetY - nowFy) * 20, 4, liftCap)
			stepLV.Enabled = true
		end
	elseif grounded then
		local handled = false
		if STEP_ASSIST and floorTopY and fy then
			local topY = detectStep(flat, floorTopY, STEP_PROBE + effectiveSpeed * 0.04)
			if topY and (topY - fy) > 0.25 and stepLV and stepLV.Parent then
				stepping = true
				stepTargetY = topY
				stepDeadline = now + 0.6
				stepLV.LineVelocity = math.clamp((topY - fy) * 20, 4, liftCap)
				stepLV.Enabled = true
				handled = true
			end
		end
		if not handled and stepLV and stepLV.Parent then
			if SLOPE_GLUE and floorNormal and floorNormal.Y > 0.1 and floorNormal.Y < 0.999 then
				-- hug the slope: drive Y so velocity stays tangent to the surface (up or down)
				local vhx = dir.X * effectiveSpeed
				local vhz = dir.Z * effectiveSpeed
				local vy = -(vhx * floorNormal.X + vhz * floorNormal.Z) / floorNormal.Y
				local cap = effectiveSpeed * 3.5 + 5
				vy = math.clamp(vy, -cap, cap)
				stepLV.LineVelocity = vy
				stepLV.Enabled = true
				lastGlueTime = now
				lastGlueVy = vy
			elseif lastGlueVy > 0 and now - lastGlueTime < 0.2 then
				-- just crested from an upslope onto flat: bleed the residual upward velocity so you don't launch
				stepLV.LineVelocity = 0
				stepLV.Enabled = true
			else
				stopStep()
			end
		end
	else
		stopStep()
	end

	-- inherit the floor's motion so moving platforms carry you; decays after you leave one
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
	else
		local decay = math.max(0, 1 - dt * 3)
		airFloorVX *= decay
		airFloorVZ *= decay
	end
	local baseVX = grounded and fvx or airFloorVX
	local baseVZ = grounded and fvz or airFloorVZ

	-- let external knockback/impulses through: if we're moving much faster horizontally than we
	-- asked for, something is shoving us, so back off the constraint briefly and let it play out.
	local av = hrp.AssemblyLinearVelocity
	local hspeed = Vector3.new(av.X, 0, av.Z).Magnitude
	local expected = effectiveSpeed + Vector2.new(baseVX, baseVZ).Magnitude
	if hspeed > expected + KNOCK_THRESHOLD then
		knockUntil = now + 0.3
	end

	if now < knockUntil then
		move.Enabled = false
		move.PlaneVelocity = Vector2.zero
	elseif moving and (grounded or AIR_CONTROL or stepping) then
		move.PlaneVelocity = Vector2.new(dir.X * effectiveSpeed + baseVX, dir.Z * effectiveSpeed + baseVZ)
		move.Enabled = true
	else
		-- idle (or airborne with no air control): let native movement hold/carry you
		move.Enabled = false
		move.PlaneVelocity = Vector2.zero
	end
end))

local function cleanup()
	alive = false
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	stopStep()
	teardown()
	_G.__LinearMovementCleanup = nil
end
_G.__LinearMovementCleanup = cleanup

if BLOCK_FOREIGN_VELOCITY and hookmetamethod and newcclosure then
	pcall(function()
		local realNewindex
		realNewindex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
			-- Only swallow velocity writes on our HRP WHILE we're actively walking. That's when
			-- del hub's manual mover fires, so its walking is replaced by ours -- but its other
			-- features (TP, auto-grab, etc., which act when you're not moving) still work.
			if (key == "Velocity" or key == "AssemblyLinearVelocity") and self == rootPart and typeof(value) == "Vector3" then
				local hum = humanoid
				if hum and hum.MoveDirection.Magnitude > 0.01 then
					-- only swallow horizontal (walk) overrides; let vertical writes (jumps / inf jump) through
					local cur = self[key]
					if math.abs(value.Y - cur.Y) < 1 then
						return
					end
				end
			end
			return realNewindex(self, key, value)
		end))
	end)
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
table.insert(connections, player.CharacterAdded:Connect(onCharacterAdded))
