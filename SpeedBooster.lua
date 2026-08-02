--!strict
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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==============================================================
-- Config
--==============================================================

local DEFAULT_NORMAL_SPEED = 60
local DEFAULT_CARRY_SPEED = 27
local MIN_SPEED = 0
local MAX_SPEED = 1000
local TOGGLE_KEY = Enum.KeyCode.RightShift
local PRESETS = { 16, 32, 60, 100, 200 }

-- Uploaded redstone-lever images: ON = lever up, OFF = lever down.
local LEVER_ON_IMAGE = "rbxassetid://130564537890360"
local LEVER_OFF_IMAGE = "rbxassetid://102532019315855"
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
local RED_DIM     = Color3.fromRGB(92, 14, 14)   -- unpowered redstone dust
local RED_BRIGHT  = Color3.fromRGB(255, 48, 48)  -- powered redstone dust
local RED_MID     = Color3.fromRGB(200, 30, 30)
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
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
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

local function updateCounter()
	local billboard = counterGui
	local label = counterLabel
	if not billboard or not label or not billboard.Parent then
		return
	end

	if not enabled then
		billboard.Enabled = false
		return
	end

	local current = measureHorizontalSpeed()
	label.Text = string.format("%d", math.round(current))

	-- Powered-redstone red while the mover is actively pushing, dimmed when idle.
	local pushing = linearVelocity ~= nil and linearVelocity.Enabled
	label.TextColor3 = pushing and Color3.fromRGB(255, 70, 70)
		or Color3.fromRGB(210, 210, 215)

	billboard.Enabled = true
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

-- Draws a 2px pixel bevel: light top/left, dark bottom/right. Pass the colours
-- swapped to get an inset (pressed-in) look for slots.
local function addBevel(frame: GuiObject, hi: Color3, lo: Color3)
	local function edge(size: UDim2, pos: UDim2, color: Color3)
		local f = Instance.new("Frame")
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = frame.ZIndex + 1
		f.Parent = frame
	end
	edge(UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 0, 0), hi) -- top
	edge(UDim2.new(0, 2, 1, 0), UDim2.new(0, 0, 0, 0), hi) -- left
	edge(UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), lo) -- bottom
	edge(UDim2.new(0, 2, 1, 0), UDim2.new(1, -2, 0, 0), lo) -- right
end

-- Redstone dust border: dim when unpowered, glows/pulses red while the booster
-- is enabled (the whole "circuit" powers on together). Frames added to
-- redstoneLines get tinted the same way (used by the separator).
local redstoneStrokes: { UIStroke } = {}
local redstoneLines: { Frame } = {}
local redstoneImages: { ImageLabel } = {} -- tinted via ImageColor3

local function addRedstoneStroke(frame: GuiObject, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2
	stroke.Color = RED_DIM
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	table.insert(redstoneStrokes, stroke)
	return stroke
end

do
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		-- Only glow while powered (enabled); otherwise sit at the dim, unpowered red.
		local glow = enabled and (0.5 + 0.5 * math.sin(t * 4)) or 0
		local col = RED_DIM:Lerp(RED_BRIGHT, glow)
		for i = #redstoneStrokes, 1, -1 do
			local s = redstoneStrokes[i]
			if s.Parent then s.Color = col else table.remove(redstoneStrokes, i) end
		end
		for i = #redstoneLines, 1, -1 do
			local l = redstoneLines[i]
			if l.Parent then l.BackgroundColor3 = col else table.remove(redstoneLines, i) end
		end
		for i = #redstoneImages, 1, -1 do
			local img = redstoneImages[i]
			if img.Parent then img.ImageColor3 = col else table.remove(redstoneImages, i) end
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
panel.Size = UDim2.fromOffset(250, 226)
panel.Position = UDim2.new(0, 24, 0.5, -113)
panel.BackgroundColor3 = STONE_TOP
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
-- sharp corners = blocky Minecraft slab (no UICorner)

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(STONE_TOP, STONE_BOT)
panelGradient.Parent = panel

addBevel(panel, BEVEL_HI, BEVEL_LO)  -- raised stone slab
addRedstoneStroke(panel, 2.5)        -- powered redstone dust outline

-- Header ------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.ZIndex = 3
header.Parent = panel

-- redstone-dust indicator: dim when unpowered, glows/pulses red with the circuit
local dust = Instance.new("ImageLabel")
dust.Name = "RedstoneDust"
dust.Size = UDim2.fromOffset(20, 20)
dust.Position = UDim2.new(0, 9, 0.5, -10)
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
body.Size = UDim2.new(1, -20, 0, 150)
body.Position = UDim2.fromOffset(10, 48)
body.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
body.BorderSizePixel = 0
body.ZIndex = 1
body.Parent = panel
addBevel(body, BEVEL_LO, BEVEL_HI) -- inset (sunken) bevel

-- Speed rows --------------------------------------------------
-- Builds a "<label> ..... [ slot ]" stone row and returns the box + label.
local function makeSpeedRow(name: string, labelText: string, defaultValue: number, y: number)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 34)
	row.Position = UDim2.fromOffset(10, y)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	row.BorderSizePixel = 0
	row.ZIndex = 2
	row.Parent = panel
	addBevel(row, BEVEL_HI, BEVEL_LO)

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
	addBevel(box, BEVEL_LO, BEVEL_HI) -- swapped = pressed-in slot

	return box, label, row
end

local normalBox, normalLabel = makeSpeedRow("Normal", "NORMAL SPEED", DEFAULT_NORMAL_SPEED, 52)
local carryBox, carryLabel = makeSpeedRow("Carry", "CARRY SPEED", DEFAULT_CARRY_SPEED, 90)

-- Presets (set the Normal speed) ------------------------------
local presetRow = Instance.new("Frame")
presetRow.Name = "Presets"
presetRow.Size = UDim2.new(1, -20, 0, 26)
presetRow.Position = UDim2.fromOffset(10, 130)
presetRow.BackgroundTransparency = 1
presetRow.ZIndex = 2
presetRow.Parent = panel

local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.Padding = UDim.new(0, 6)
presetLayout.Parent = presetRow

-- Toggle row with a redstone lever -----------------------------
local toggleRow = Instance.new("Frame")
toggleRow.Name = "ToggleRow"
toggleRow.Size = UDim2.new(1, -20, 0, 36)
toggleRow.Position = UDim2.fromOffset(10, 162)
toggleRow.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
toggleRow.BorderSizePixel = 0
toggleRow.ZIndex = 2
toggleRow.Parent = panel
addBevel(toggleRow, BEVEL_HI, BEVEL_LO)

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
addBevel(leverBase, Color3.fromRGB(96, 96, 104), Color3.fromRGB(28, 28, 32))

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
addBevel(handle, Color3.fromRGB(150, 150, 158), Color3.fromRGB(60, 60, 66))

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
addBevel(knob, Color3.fromRGB(150, 60, 60), Color3.fromRGB(40, 12, 12))

-- If you uploaded a lever image, use it instead of the drawn one.
local useLeverImage = LEVER_ON_IMAGE ~= ""
local leverImage: ImageLabel? = nil
if useLeverImage then
	leverBase.Visible = false -- hide the drawn base/handle/knob
	local img = Instance.new("ImageLabel")
	img.Name = "LeverImage"
	img.AnchorPoint = Vector2.new(1, 0.5)
	img.Size = UDim2.fromOffset(42, 42)
	img.Position = UDim2.new(1, -8, 0.5, 0)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = (LEVER_OFF_IMAGE ~= "" and LEVER_OFF_IMAGE) or LEVER_ON_IMAGE
	img.ZIndex = 4
	img.Parent = toggleRow
	leverImage = img
end

-- whole row is clickable
local leverButton = Instance.new("TextButton")
leverButton.Size = UDim2.fromScale(1, 1)
leverButton.BackgroundTransparency = 1
leverButton.Text = ""
leverButton.AutoButtonColor = false
leverButton.ZIndex = 6
leverButton.Parent = toggleRow

-- Mode readout / hint -----------------------------------------
local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.Size = UDim2.new(1, -20, 0, 16)
hint.Position = UDim2.fromOffset(10, 202)
hint.BackgroundTransparency = 1
hint.Text = "RIGHTSHIFT TO TOGGLE"
hint.Font = FONT
hint.TextSize = 13
hint.TextColor3 = SUBTEXT
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.ZIndex = 3
hint.Parent = panel

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
end

local function setCarrySpeed(value: number)
	carrySpeed = math.clamp(value, MIN_SPEED, MAX_SPEED)
	carryBox.Text = tostring(carrySpeed)
end

-- Flip the lever + warm the title when powered (dust pulses via the loop).
local function animLever(on: boolean)
	if useLeverImage and leverImage then
		leverImage.Image = on and LEVER_ON_IMAGE
			or ((LEVER_OFF_IMAGE ~= "" and LEVER_OFF_IMAGE) or LEVER_ON_IMAGE)
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

	if not enabled then
		hint.Text = "RIGHTSHIFT TO TOGGLE"
		hint.TextColor3 = SUBTEXT
	elseif carrying then
		hint.Text = string.format("CARRYING  -  %d", carrySpeed)
		hint.TextColor3 = RED_BRIGHT
	else
		hint.Text = string.format("NORMAL  -  %d", normalSpeed)
		hint.TextColor3 = Color3.fromRGB(120, 255, 165)
	end
end

local function setEnabled(value: boolean)
	enabled = value
	animLever(enabled)

	if not enabled then
		if linearVelocity then
			linearVelocity.Enabled = false
			linearVelocity.PlaneVelocity = Vector2.zero
		end
		if counterGui then
			counterGui.Enabled = false
		end
	end
	updateMode()
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

for _, preset in PRESETS do
	local button = Instance.new("TextButton")
	button.Name = "Preset" .. preset
	button.Size = UDim2.new(0, 38, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(70, 70, 76) -- cobblestone
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = tostring(preset)
	button.Font = FONT
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(225, 225, 230)
	button.ZIndex = 3
	button.Parent = presetRow
	addBevel(button, Color3.fromRGB(104, 104, 112), Color3.fromRGB(34, 34, 38))

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = RED_DIM }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(70, 70, 76) }):Play()
	end)
	-- pressed-block feel: sink on press, pop back on release
	local restSize = button.Size
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, TweenInfo.new(0.06), { Size = UDim2.new(0, 34, 1, -4) }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = restSize }):Play()
		end
	end)
	button.Activated:Connect(function()
		setNormalSpeed(preset) -- presets set the Normal speed
		updateMode()
	end)
end

leverButton.Activated:Connect(function()
	setEnabled(not enabled)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		setEnabled(not enabled)
	end
end)

--==============================================================
-- Boot
--==============================================================

setNormalSpeed(DEFAULT_NORMAL_SPEED)
setCarrySpeed(DEFAULT_CARRY_SPEED)
onCarryChanged = updateMode -- the movement loop calls this on pick-up / drop
setEnabled(false)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
