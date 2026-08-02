--!nonstrict
--[[
	Dely Booster Test 67  (Redstone theme)
	--------------------------------------
	LocalScript. Drop it in StarterPlayer > StarterPlayerScripts (or run it from
	a client-side script runner).

	How it works:
	  * An Attachment is created on the HumanoidRootPart.
	  * A LinearVelocity is bound to that Attachment in Plane mode, with the
	    plane spanned by the world X and Z axes. Because the constraint only
	    solves inside that plane, no force is ever applied on Y, so gravity,
	    jumping and falling behave exactly as normal.
	  * Every frame we read Humanoid.MoveDirection and push it into
	    PlaneVelocity as Vector2.new(MoveDirection.X * spd, MoveDirection.Z * spd),
	    where `spd` is the Normal or Carry speed depending on whether a brainrot
	    is being carried. Nothing ever writes to HumanoidRootPart.Velocity.
	  * When there is no input the constraint is disabled so the character can
	    slow down, get knocked around, and be moved by other physics normally.

	Normal vs Carry: while you hold a brainrot the game slows your WalkSpeed and
	sets a "Stealing" attribute. isCarryingBrainrot() reads that, and the mover
	switches from Normal Speed to Carry Speed automatically (and back on drop).

	Panel: a deepslate slab with pixel bevels and a redstone-dust border that
	only powers on (glows red) while the booster is enabled. A lever toggles it;
	RightShift does too. Draggable.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==============================================================
-- Config
--==============================================================

local DEFAULT_NORMAL_SPEED = 60
local DEFAULT_CARRY_SPEED = 27
local MIN_SPEED = 0
local MAX_SPEED = 1000
local CONFIG_FILE = "dely_booster_test67.json" -- auto-saved settings

-- Uploaded redstone-lever images: starts up (off), flips down when activated.
local LEVER_ON_IMAGE = "rbxassetid://102532019315855"  -- lever down = ON
local LEVER_OFF_IMAGE = "rbxassetid://130564537890360" -- lever up = OFF
-- Redstone-dust image in the header (replaces the drawn indicator).
local DUST_IMAGE = "rbxassetid://83833754384535"

-- The game drops your WalkSpeed below this while you carry a brainrot; that's
-- how we detect the carry state (alongside the "Stealing" attribute).
local CARRY_WALKSPEED_MAX = 25

--==============================================================
-- Redstone theme palette
--==============================================================

local STONE_TOP   = Color3.fromRGB(46, 46, 50)   -- deepslate, top of the slab
local STONE_BOT   = Color3.fromRGB(24, 24, 26)   -- darker toward the bottom
local SLOT        = Color3.fromRGB(18, 18, 20)   -- inset slot fill
local BEVEL_HI    = Color3.fromRGB(78, 78, 84)   -- light pixel edge (top/left)
local BEVEL_LO    = Color3.fromRGB(10, 10, 12)   -- dark pixel edge (bottom/right)
local REDDISH_BLACK = Color3.fromRGB(40, 7, 7)    -- unpowered (border sits here)
local CRIMSON       = Color3.fromRGB(178, 20, 48)
local RED           = Color3.fromRGB(235, 22, 22)
local SCARLET       = Color3.fromRGB(255, 62, 28)
local RED_DIM     = REDDISH_BLACK                 -- unpowered redstone dust/border
local RED_BRIGHT  = Color3.fromRGB(255, 48, 48)  -- powered redstone dust
local RED_MID     = Color3.fromRGB(200, 30, 30)

-- Powered border surge: flows through reddish-black -> crimson -> red -> scarlet
-- and back. Endpoints match so rotating it loops seamlessly.
local SURGE_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, REDDISH_BLACK),
	ColorSequenceKeypoint.new(0.25, CRIMSON),
	ColorSequenceKeypoint.new(0.50, RED),
	ColorSequenceKeypoint.new(0.70, SCARLET),
	ColorSequenceKeypoint.new(0.86, CRIMSON),
	ColorSequenceKeypoint.new(1.00, REDDISH_BLACK),
})
local TEXT        = Color3.fromRGB(228, 228, 232)
local SUBTEXT     = Color3.fromRGB(150, 150, 156)
local FONT        = Enum.Font.Arcade -- closest built-in to the Minecraft look

--==============================================================
-- State
--==============================================================

local enabled = false
local normalSpeed = DEFAULT_NORMAL_SPEED
local carrySpeed = DEFAULT_CARRY_SPEED
local carrying = false -- true while a brainrot is being carried

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local head: BasePart? = nil

local attachment: Attachment? = nil
local linearVelocity: LinearVelocity? = nil

local counterGui: BillboardGui? = nil
local counterLabel: TextLabel? = nil

-- Speed-counter (head readout) state
local counterEnabled = false
local prevSpeed = 0
local speedAnimActive = false
local lastSpeedFlash = 0
local counterScanT = 0
local COUNTER_BASE_Y = 2.6 -- studs above the head when nothing else is up there
local BB_NORMAL = UDim2.fromOffset(150, 40)
local BB_MID = UDim2.fromOffset(162, 44)
local BB_BIG = UDim2.fromOffset(174, 48)

-- Config persistence (executor filesystem)
local savedGuiPos = nil -- {xScale, xOffset, yScale, yOffset}
local suppressSave = false -- true while applying loaded values, so we don't re-save
local canPersist = typeof(writefile) == "function"
	and typeof(readfile) == "function"
	and typeof(isfile) == "function"

local function saveConfig()
	if not canPersist or suppressSave then
		return
	end
	local cfg = {
		normalSpeed = normalSpeed,
		carrySpeed = carrySpeed,
		enabled = enabled,
		counterEnabled = counterEnabled,
		guiPos = savedGuiPos,
	}
	pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(cfg))
	end)
end

local function loadConfig()
	if not canPersist or not isfile(CONFIG_FILE) then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

--==============================================================
-- Physics
--==============================================================

local function teardownMover()
	if linearVelocity then
		linearVelocity:Destroy()
		linearVelocity = nil
	end
	if attachment then
		attachment:Destroy()
		attachment = nil
	end
end

-- Builds the Attachment + LinearVelocity pair on the current HumanoidRootPart.
local function buildMover()
	teardownMover()
	if not rootPart then
		return
	end

	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = "SpeedBoosterAttachment"
	newAttachment.Parent = rootPart

	local newVelocity = Instance.new("LinearVelocity")
	newVelocity.Name = "SpeedBoosterVelocity"
	newVelocity.Attachment0 = newAttachment
	newVelocity.RelativeTo = Enum.ActuatorRelativeTo.World

	-- Plane mode: the solver only acts inside the plane we define below, so the
	-- Y axis is left completely untouched (force on Y is effectively 0).
	newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	newVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)   -- world X
	newVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1) -- world Z

	newVelocity.MaxForce = math.huge
	newVelocity.PlaneVelocity = Vector2.zero
	newVelocity.Enabled = false
	newVelocity.Parent = rootPart

	attachment = newAttachment
	linearVelocity = newVelocity
end

--==============================================================
-- Head counter
--==============================================================

local function teardownCounter()
	if counterGui then
		counterGui:Destroy()
		counterGui = nil
		counterLabel = nil
	end
end

-- Floating readout above the head. Created on the client only, so nobody else
-- sees it.
local function buildCounter()
	teardownCounter()
	if not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpeedBoosterCounter"
	billboard.Adornee = head
	billboard.Size = BB_NORMAL
	billboard.StudsOffsetWorldSpace = Vector3.new(0, COUNTER_BASE_Y, 0)
	billboard.AlwaysOnTop = true -- render over other head GUIs
	billboard.MaxDistance = 200
	billboard.Enabled = false
	billboard.Parent = head

	-- Minecraft nametag-style plate: dark translucent slab with a redstone edge.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Size = UDim2.fromScale(0.86, 0.78)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
	plate.BackgroundTransparency = 0.35
	plate.BorderSizePixel = 0
	plate.ZIndex = 1
	plate.Parent = billboard
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 6)
	plateCorner.Parent = plate
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = RED_MID
	plateStroke.Thickness = 1.5
	plateStroke.Transparency = 0.15
	plateStroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "0"
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.ZIndex = 2
	label.Parent = billboard

	counterGui = billboard
	counterLabel = label
end

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	head = newCharacter:WaitForChild("Head") :: BasePart
	buildMover()
	buildCounter()
end

--==============================================================
-- Carry / Normal speed
--==============================================================

-- True while a brainrot is being carried. The game slows the character's
-- WalkSpeed below CARRY_WALKSPEED_MAX (but keeps it above 0) and/or sets a
-- "Stealing" attribute on the player while carrying, so we read both.
local function isCarryingBrainrot(): boolean
	if player:GetAttribute("Stealing") == true then
		return true
	end
	if humanoid and humanoid.WalkSpeed > 0 and humanoid.WalkSpeed < CARRY_WALKSPEED_MAX then
		return true
	end
	return false
end

-- The two speeds, as their own functions.
local function getNormalSpeed(): number
	return normalSpeed
end
local function getCarrySpeed(): number
	return carrySpeed
end

-- Speed to apply this frame: Carry while holding a brainrot, Normal otherwise.
local function getActiveSpeed(): number
	if carrying then
		return getCarrySpeed()
	end
	return getNormalSpeed()
end

-- Assigned by the UI so a pick-up / drop updates the panel's mode readout.
local onCarryChanged: (() -> ())? = nil

--==============================================================
-- Movement loop
--==============================================================

-- Actual horizontal speed the character is travelling at, in studs/sec. Y is
-- dropped so falling never inflates the number.
local function measureHorizontalSpeed(): number
	if not rootPart then
		return 0
	end
	local assemblyVelocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(assemblyVelocity.X, 0, assemblyVelocity.Z).Magnitude
end

-- del-hub-style flash: on a sharp speed increase the readout punches bigger and
-- flashes red (big spike) or light-red (smaller spike), then eases back to white.
local function triggerSpeedFlash(big: boolean)
	if speedAnimActive then
		return
	end
	local bb = counterGui
	local label = counterLabel
	if not bb or not label then
		return
	end
	local now = tick()
	if now - lastSpeedFlash < 0.18 then
		return
	end
	lastSpeedFlash = now
	speedAnimActive = true

	local flashCol = big and RED_BRIGHT or Color3.fromRGB(255, 120, 120)
	local punchSize = big and BB_BIG or BB_MID
	TweenService:Create(bb, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = punchSize }):Play()
	TweenService:Create(label, TweenInfo.new(0.07), { TextColor3 = flashCol, TextStrokeTransparency = 0.1 }):Play()
	task.delay(0.1, function()
		if counterGui and counterLabel then
			TweenService:Create(counterGui, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = BB_NORMAL }):Play()
			TweenService:Create(counterLabel, TweenInfo.new(0.2), { TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.3 }):Play()
		end
		task.delay(0.22, function()
			speedAnimActive = false
		end)
	end)
end

-- Finds how high (in studs) any OTHER head billboard/text reaches, so we can sit
-- above it instead of overlapping it.
local function otherHeadTopY(): number
	local top = COUNTER_BASE_Y
	local c = character
	if not c then
		return top
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d ~= counterGui and d:IsA("BillboardGui") and d.Enabled then
			local y = math.max(d.StudsOffsetWorldSpace.Y, d.StudsOffset.Y) + 1.0
			if y > top then
				top = y
			end
		end
	end
	return top
end

local function updateCounter()
	local billboard = counterGui
	local label = counterLabel
	if not billboard or not label or not billboard.Parent then
		return
	end

	if not counterEnabled then
		billboard.Enabled = false
		return
	end
	billboard.Enabled = true

	local current = measureHorizontalSpeed()
	label.Text = tostring(math.round(current))

	-- del-hub flash on acceleration
	local delta = current - prevSpeed
	prevSpeed = current
	if delta > 18 then
		triggerSpeedFlash(true)
	elseif delta > 6 then
		triggerSpeedFlash(false)
	end

	-- overlay: float above any other nametag / speed counter on the head
	local now = tick()
	if now - counterScanT > 0.35 then
		counterScanT = now
		local target = Vector3.new(0, otherHeadTopY(), 0)
		if math.abs(billboard.StudsOffsetWorldSpace.Y - target.Y) > 0.05 then
			billboard.StudsOffsetWorldSpace = target
		end
	end
end

RunService.Heartbeat:Connect(function()
	-- Detect pick-up / drop every frame and switch modes when it changes.
	local nowCarrying = isCarryingBrainrot()
	if nowCarrying ~= carrying then
		carrying = nowCarrying
		if onCarryChanged then
			onCarryChanged()
		end
	end

	updateCounter()

	local velocity = linearVelocity
	if not velocity or not velocity.Parent then
		return
	end

	if not enabled or not humanoid or humanoid.Health <= 0 then
		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude <= 0.01 then
		-- No input: hand control back to the Humanoid so the character can stop,
		-- fall and be pushed around like usual.
		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	-- Carry Speed while holding a brainrot, Normal Speed otherwise. X and Z
	-- only -- Y never gets a component, so gravity is untouched.
	local spd = getActiveSpeed()
	velocity.PlaneVelocity = Vector2.new(moveDirection.X * spd, moveDirection.Z * spd)
	velocity.Enabled = true
end)

--==============================================================
-- UI helpers (Minecraft pixel bevels + powered redstone border)
--==============================================================

-- Rounds a corner and (optionally) gives it a soft edge stroke. Replaces the old
-- square pixel bevels so everything reads smooth.
local function round(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function edgeStroke(inst: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

-- Snappy scale pop: set to `from`, spring back to 1. Used all over for feedback.
local function punch(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Damped rotational shake, eased out. Used on load for the redstone dust + lever.
local function shake(gui: GuiObject?, amplitude: number, duration: number)
	if not gui then
		return
	end
	task.spawn(function()
		local t = 0
		while t < duration and gui.Parent do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			local decay = 1 - (t / duration)
			gui.Rotation = math.sin(t * 36) * amplitude * decay * decay
		end
		gui.Rotation = 0
	end)
end

-- Redstone dust border: dim when unpowered, glows/pulses red while the booster
-- is enabled (the whole "circuit" powers on together). Frames added to
-- redstoneLines get tinted the same way (used by the separator).
local redstoneLines: { Frame } = {}
local redstoneImages: { ImageLabel } = {} -- tinted via ImageColor3
local powerSurge = 0 -- brief flash to full brightness when the booster is switched on

-- The big panel border: reddish-black + still when unpowered, a flowing
-- crimson/scarlet gradient surge when powered. Assigned when the panel is built.
local panelBorder: UIStroke? = nil
local panelBorderGrad: UIGradient? = nil
local PANEL_BORDER_BASE = 3 -- overflows the panel edge a little

do
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		powerSurge = math.max(0, powerSurge - dt * 2.5) -- decays after a switch-on
		-- Only glow while powered (enabled); otherwise sit at the dim, unpowered red.
		-- The surge briefly overrides the sine so a flick flashes bright.
		local glow = enabled and math.max(0.5 + 0.5 * math.sin(t * 4), powerSurge) or 0
		local col = RED_DIM:Lerp(RED_BRIGHT, glow)
		for i = #redstoneLines, 1, -1 do
			local l = redstoneLines[i]
			if l.Parent then l.BackgroundColor3 = col else table.remove(redstoneLines, i) end
		end
		for i = #redstoneImages, 1, -1 do
			local img = redstoneImages[i]
			if img.Parent then img.ImageColor3 = col else table.remove(redstoneImages, i) end
		end

		-- panel border: powered = flowing gradient surge; off = still reddish-black
		if panelBorder and panelBorderGrad then
			if enabled then
				panelBorderGrad.Enabled = true
				panelBorder.Color = Color3.fromRGB(255, 255, 255) -- let the gradient show
				panelBorderGrad.Rotation = (panelBorderGrad.Rotation + dt * 100) % 360 -- flow
				panelBorder.Thickness = PANEL_BORDER_BASE + math.sin(t * 6) * 0.8 + powerSurge * 2
			else
				panelBorderGrad.Enabled = false
				panelBorder.Color = REDDISH_BLACK
				panelBorder.Thickness = PANEL_BORDER_BASE
			end
		end
	end)
end

--==============================================================
-- UI
--==============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedBoosterPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(250, 210)
panel.Position = UDim2.new(0, 24, 0.5, -105)
panel.BackgroundColor3 = STONE_TOP
panel.BorderSizePixel = 0
panel.Active = true
panel.ClipsDescendants = true -- so the black title bar keeps the panel's rounded top corners
panel.Parent = gui

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(STONE_TOP, STONE_BOT)
panelGradient.Parent = panel

round(panel, 12)                     -- smooth slab corners

-- Big redstone border that overflows the panel edge. Reddish-black + still when
-- off; a flowing crimson/scarlet gradient surge when powered (driven above).
panelBorder = Instance.new("UIStroke")
panelBorder.Thickness = PANEL_BORDER_BASE
panelBorder.Color = REDDISH_BLACK
panelBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelBorder.LineJoinMode = Enum.LineJoinMode.Round
panelBorder.Parent = panel
panelBorderGrad = Instance.new("UIGradient")
panelBorderGrad.Color = SURGE_SEQ
panelBorderGrad.Enabled = false
panelBorderGrad.Parent = panelBorder

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- Header ------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(10, 10, 12) -- black title bar
header.BackgroundTransparency = 0
header.BorderSizePixel = 0
header.ZIndex = 3
header.Parent = panel

-- redstone-dust indicator: dim when unpowered, glows/pulses red with the circuit
local dust = Instance.new("ImageLabel")
dust.Name = "RedstoneDust"
dust.AnchorPoint = Vector2.new(0.5, 0.5) -- center pivot so the load shake looks right
dust.Size = UDim2.fromOffset(20, 20)
dust.Position = UDim2.new(0, 19, 0.5, 0)
dust.BackgroundTransparency = 1
dust.Image = DUST_IMAGE
dust.ScaleType = Enum.ScaleType.Fit
dust.ImageColor3 = RED_DIM
dust.ZIndex = 4
dust.Parent = header
table.insert(redstoneImages, dust)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.fromOffset(34, 0)
title.BackgroundTransparency = 1
title.Text = "DELY BOOSTER TEST 67"
title.Font = FONT
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextStrokeTransparency = 0.5
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.ZIndex = 4
title.Parent = header

-- redstone dust separator (powers on with the circuit)
local sep = Instance.new("Frame")
sep.Name = "Separator"
sep.Size = UDim2.new(1, -20, 0, 3)
sep.Position = UDim2.fromOffset(10, 42)
sep.BackgroundColor3 = RED_DIM
sep.BorderSizePixel = 0
sep.ZIndex = 3
sep.Parent = panel
table.insert(redstoneLines, sep)

-- Recessed inner body: a darker well the rows/buttons sit inside, so the panel
-- reads like a real Minecraft window (outer slab + sunken content area).
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -20, 0, 154)
body.Position = UDim2.fromOffset(10, 48)
body.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
body.BorderSizePixel = 0
body.ZIndex = 1
body.Parent = panel
round(body, 9)
edgeStroke(body, Color3.fromRGB(8, 8, 10), 1, 0.15) -- dark rim = recessed look

-- Speed rows --------------------------------------------------
-- Builds a "<label> ..... [ slot ]" stone row and returns the box + label.
local function makeSpeedRow(name: string, labelText: string, defaultValue: number, y: number)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 32)
	row.Position = UDim2.fromOffset(10, y)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	row.BorderSizePixel = 0
	row.ZIndex = 2
	row.Parent = panel
	round(row, 6)
	edgeStroke(row, Color3.fromRGB(62, 62, 70), 1, 0.25) -- soft raised rim

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0.55, 0, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = FONT
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = TEXT
	label.ZIndex = 3
	label.Parent = row

	-- inventory-slot style box: inset bevel (dark top-left, light bottom-right)
	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Size = UDim2.fromOffset(72, 24)
	box.Position = UDim2.new(1, -8, 0.5, 0)
	box.BackgroundColor3 = SLOT
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = tostring(defaultValue)
	box.PlaceholderText = "studs/s"
	box.Font = FONT
	box.TextSize = 16
	box.TextColor3 = Color3.fromRGB(255, 90, 90)
	box.ZIndex = 3
	box.Parent = row
	round(box, 5)
	edgeStroke(box, Color3.fromRGB(8, 8, 10), 1, 0) -- dark rim = pressed-in slot
	local boxScale = Instance.new("UIScale")
	boxScale.Parent = box

	-- row hover: gently lighten the stone
	local base = row.BackgroundColor3
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end)

	-- slot focus: pop + warm the fill (restore is handled by updateMode on blur)
	box.Focused:Connect(function()
		punch(boxScale, 1.14)
		TweenService:Create(box, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(42, 20, 20) }):Play()
	end)

	return box, label, boxScale
end

local normalBox, normalLabel, normalBoxScale = makeSpeedRow("Normal", "NORMAL SPEED", DEFAULT_NORMAL_SPEED, 52)
local carryBox, carryLabel, carryBoxScale = makeSpeedRow("Carry", "CARRY SPEED", DEFAULT_CARRY_SPEED, 90)

-- Toggle row with a redstone lever -----------------------------
local toggleRow = Instance.new("Frame")
toggleRow.Name = "ToggleRow"
toggleRow.Size = UDim2.new(1, -20, 0, 32)
toggleRow.Position = UDim2.fromOffset(10, 128)
toggleRow.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
toggleRow.BorderSizePixel = 0
toggleRow.ZIndex = 2
toggleRow.Parent = panel
round(toggleRow, 6)
edgeStroke(toggleRow, Color3.fromRGB(62, 62, 70), 1, 0.25)
toggleRow.MouseEnter:Connect(function()
	TweenService:Create(toggleRow, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
end)
toggleRow.MouseLeave:Connect(function()
	TweenService:Create(toggleRow, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(34, 34, 38) }):Play()
end)

local toggleLabel = Instance.new("TextLabel")
toggleLabel.Name = "ToggleLabel"
toggleLabel.Size = UDim2.new(0.5, 0, 1, 0)
toggleLabel.Position = UDim2.fromOffset(10, 0)
toggleLabel.BackgroundTransparency = 1
toggleLabel.Text = "ENABLE"
toggleLabel.Font = FONT
toggleLabel.TextSize = 15
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.TextColor3 = TEXT
toggleLabel.ZIndex = 3
toggleLabel.Parent = toggleRow

-- lever cobble base
local leverBase = Instance.new("Frame")
leverBase.Name = "LeverBase"
leverBase.AnchorPoint = Vector2.new(1, 0.5)
leverBase.Size = UDim2.fromOffset(34, 12)
leverBase.Position = UDim2.new(1, -12, 0.5, 6)
leverBase.BackgroundColor3 = Color3.fromRGB(64, 64, 70)
leverBase.BorderSizePixel = 0
leverBase.ZIndex = 3
leverBase.Parent = toggleRow
round(leverBase, 4)
edgeStroke(leverBase, Color3.fromRGB(24, 24, 28), 1, 0.2)

-- lever handle (pivots at the base) — starts in the OFF position
local handle = Instance.new("Frame")
handle.Name = "Handle"
handle.AnchorPoint = Vector2.new(0.5, 1)
handle.Size = UDim2.fromOffset(7, 22)
handle.Position = UDim2.new(0.5, 0, 0, 1)
handle.Rotation = 38
handle.BackgroundColor3 = Color3.fromRGB(120, 120, 128)
handle.BorderSizePixel = 0
handle.ZIndex = 4
handle.Parent = leverBase
round(handle, 3)

-- knob at the top of the handle — the redstone tip that lights up when ON
local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.AnchorPoint = Vector2.new(0.5, 0)
knob.Size = UDim2.fromOffset(12, 12)
knob.Position = UDim2.new(0.5, 0, 0, -4)
knob.BackgroundColor3 = Color3.fromRGB(70, 22, 22)
knob.BorderSizePixel = 0
knob.ZIndex = 5
knob.Parent = handle
round(knob, 6) -- round redstone tip

-- If you uploaded a lever image, use it instead of the drawn one.
local useLeverImage = LEVER_ON_IMAGE ~= ""
local leverImage: ImageLabel? = nil
local leverImageScale: UIScale? = nil
if useLeverImage then
	leverBase.Visible = false -- hide the drawn base/handle/knob
	local img = Instance.new("ImageLabel")
	img.Name = "LeverImage"
	img.AnchorPoint = Vector2.new(1, 0.5)
	img.Size = UDim2.fromOffset(34, 34)
	img.Position = UDim2.new(1, -8, 0.5, 0)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = (LEVER_OFF_IMAGE ~= "" and LEVER_OFF_IMAGE) or LEVER_ON_IMAGE
	img.ZIndex = 4
	img.Parent = toggleRow
	local imgScale = Instance.new("UIScale")
	imgScale.Parent = img
	leverImage = img
	leverImageScale = imgScale
end

-- whole row is clickable
local leverButton = Instance.new("TextButton")
leverButton.Size = UDim2.fromScale(1, 1)
leverButton.BackgroundTransparency = 1
leverButton.Text = ""
leverButton.AutoButtonColor = false
leverButton.ZIndex = 6
leverButton.Parent = toggleRow

-- Speed Counter row (Minecraft-styled slide switch) ------------
local counterRow = Instance.new("Frame")
counterRow.Name = "CounterRow"
counterRow.Size = UDim2.new(1, -20, 0, 32)
counterRow.Position = UDim2.fromOffset(10, 166)
counterRow.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
counterRow.BorderSizePixel = 0
counterRow.ZIndex = 2
counterRow.Parent = panel
round(counterRow, 6)
edgeStroke(counterRow, Color3.fromRGB(62, 62, 70), 1, 0.25)
counterRow.MouseEnter:Connect(function()
	TweenService:Create(counterRow, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
end)
counterRow.MouseLeave:Connect(function()
	TweenService:Create(counterRow, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(34, 34, 38) }):Play()
end)

local counterLabelUi = Instance.new("TextLabel")
counterLabelUi.Name = "Label"
counterLabelUi.Size = UDim2.new(0.6, 0, 1, 0)
counterLabelUi.Position = UDim2.fromOffset(10, 0)
counterLabelUi.BackgroundTransparency = 1
counterLabelUi.Text = "SPEED COUNTER"
counterLabelUi.Font = FONT
counterLabelUi.TextSize = 15
counterLabelUi.TextXAlignment = Enum.TextXAlignment.Left
counterLabelUi.TextColor3 = TEXT
counterLabelUi.ZIndex = 3
counterLabelUi.Parent = counterRow

-- Minecraft slide switch: inset stone track + a redstone-block knob that lights
-- up and slides right when on.
local swTrack = Instance.new("Frame")
swTrack.Name = "SwitchTrack"
swTrack.AnchorPoint = Vector2.new(1, 0.5)
swTrack.Size = UDim2.fromOffset(44, 18)
swTrack.Position = UDim2.new(1, -10, 0.5, 0)
swTrack.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
swTrack.BorderSizePixel = 0
swTrack.ZIndex = 3
swTrack.Parent = counterRow
round(swTrack, 9) -- pill track
edgeStroke(swTrack, Color3.fromRGB(8, 8, 10), 1, 0.1)

local swKnob = Instance.new("Frame")
swKnob.Name = "SwitchKnob"
swKnob.Size = UDim2.fromOffset(16, 16)
swKnob.Position = UDim2.new(0, 1, 0.5, -8) -- off (left)
swKnob.BackgroundColor3 = Color3.fromRGB(70, 70, 76) -- stone (off)
swKnob.BorderSizePixel = 0
swKnob.ZIndex = 4
swKnob.Parent = swTrack
round(swKnob, 8) -- round knob

local counterButton = Instance.new("TextButton")
counterButton.Size = UDim2.fromScale(1, 1)
counterButton.BackgroundTransparency = 1
counterButton.Text = ""
counterButton.AutoButtonColor = false
counterButton.ZIndex = 6
counterButton.Parent = counterRow

-- Dragging (custom, since Frame.Draggable is deprecated) ------
do
	local dragging, dragStart, startPos = false, nil, nil
	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					local p = panel.Position
					savedGuiPos = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset }
					saveConfig()
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

--==============================================================
-- UI behaviour
--==============================================================

local function setNormalSpeed(value: number)
	normalSpeed = math.clamp(value, MIN_SPEED, MAX_SPEED)
	normalBox.Text = tostring(normalSpeed)
	saveConfig()
end

local function setCarrySpeed(value: number)
	carrySpeed = math.clamp(value, MIN_SPEED, MAX_SPEED)
	carryBox.Text = tostring(carrySpeed)
	saveConfig()
end

-- Flip the lever + warm the title when powered (dust pulses via the loop).
local function animLever(on: boolean)
	if useLeverImage and leverImage then
		leverImage.Image = on and LEVER_ON_IMAGE
			or ((LEVER_OFF_IMAGE ~= "" and LEVER_OFF_IMAGE) or LEVER_ON_IMAGE)
		-- flip snap: squash into the swap, spring back
		if leverImageScale then
			punch(leverImageScale, 0.7)
		end
	else
		TweenService:Create(handle, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Rotation = on and -38 or 38,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.16), {
			BackgroundColor3 = on and RED_BRIGHT or Color3.fromRGB(70, 22, 22),
		}):Play()
	end
	-- (the header dust pulses via the redstone loop) title warms when powered
	TweenService:Create(title, TweenInfo.new(0.18), {
		TextColor3 = on and Color3.fromRGB(255, 232, 232) or Color3.fromRGB(245, 245, 248),
	}):Play()
end

-- Reflect the active mode: highlight whichever speed row is live and update the
-- readout. Called on enable/disable, on a value edit, and on every carry/drop.
local function updateMode()
	local normalActive = enabled and not carrying
	local carryActive = enabled and carrying
	normalLabel.TextColor3 = normalActive and RED_BRIGHT or TEXT
	carryLabel.TextColor3 = carryActive and RED_BRIGHT or TEXT
	-- energise the live slot with a faint warm-red fill
	normalBox.BackgroundColor3 = normalActive and Color3.fromRGB(34, 16, 16) or SLOT
	carryBox.BackgroundColor3 = carryActive and Color3.fromRGB(34, 16, 16) or SLOT
end

local function setEnabled(value: boolean)
	enabled = value
	animLever(enabled)

	if enabled then
		powerSurge = 1        -- flash the whole circuit bright
		punch(panelScale, 1.03) -- little power "thunk"
	else
		if linearVelocity then
			linearVelocity.Enabled = false
			linearVelocity.PlaneVelocity = Vector2.zero
		end
	end
	updateMode()
	saveConfig()
end

-- Speed Counter toggle: shows/hides the head readout (independent of the boost).
local function animCounterSwitch(on: boolean)
	TweenService:Create(swKnob, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = on and UDim2.new(1, -17, 0.5, -8) or UDim2.new(0, 1, 0.5, -8),
	}):Play()
	TweenService:Create(swKnob, TweenInfo.new(0.16), {
		BackgroundColor3 = on and RED_BRIGHT or Color3.fromRGB(70, 70, 76),
	}):Play()
	counterLabelUi.TextColor3 = on and RED_BRIGHT or TEXT
end

local function setCounterEnabled(value: boolean)
	counterEnabled = value
	animCounterSwitch(value)
	if value then
		prevSpeed = measureHorizontalSpeed() -- avoid a false flash on the first frame
	end
	if counterGui then
		counterGui.Enabled = value
	end
	saveConfig()
end

-- Validated commit, shared by both speed boxes.
local function wireBox(box: TextBox, setter: (number) -> (), getter: () -> number)
	box.FocusLost:Connect(function()
		local value = tonumber(box.Text)
		if value then
			setter(value)
		else
			box.Text = tostring(getter()) -- reject junk input
		end
		updateMode()
	end)
end
wireBox(normalBox, setNormalSpeed, getNormalSpeed)
wireBox(carryBox, setCarrySpeed, getCarrySpeed)

leverButton.Activated:Connect(function()
	setEnabled(not enabled)
end)

counterButton.Activated:Connect(function()
	setCounterEnabled(not counterEnabled)
end)

--==============================================================
-- Boot
--==============================================================

-- movement loop calls this on pick-up / drop: refresh the readout + pop the
-- slot that just became active.
onCarryChanged = function()
	updateMode()
	if enabled then
		punch(carrying and carryBoxScale or normalBoxScale, 1.15)
	end
end

-- apply defaults, then load any saved config over the top (no re-saving while we do)
suppressSave = true
setNormalSpeed(DEFAULT_NORMAL_SPEED)
setCarrySpeed(DEFAULT_CARRY_SPEED)
setEnabled(false)
setCounterEnabled(false)

local savedCfg = loadConfig()
if savedCfg then
	if type(savedCfg.normalSpeed) == "number" then setNormalSpeed(savedCfg.normalSpeed) end
	if type(savedCfg.carrySpeed) == "number" then setCarrySpeed(savedCfg.carrySpeed) end
	if savedCfg.counterEnabled ~= nil then setCounterEnabled(savedCfg.counterEnabled == true) end
	if savedCfg.enabled ~= nil then setEnabled(savedCfg.enabled == true) end
	if type(savedCfg.guiPos) == "table" and #savedCfg.guiPos >= 4 then
		savedGuiPos = savedCfg.guiPos
		panel.Position = UDim2.new(savedCfg.guiPos[1], savedCfg.guiPos[2], savedCfg.guiPos[3], savedCfg.guiPos[4])
	end
end
suppressSave = false

-- intro: grow the panel in, then shake the redstone dust + lever as it powers up
punch(panelScale, 0.8)
task.delay(0.12, function()
	shake(dust, 16, 0.6)
	shake(leverImage, 12, 0.6)
end)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
