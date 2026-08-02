--!strict
--[[
	Speed Booster
	-------------
	LocalScript. Drop it in StarterPlayer > StarterPlayerScripts (or run it from
	a client-side script runner).

	How it works:
	  * An Attachment is created on the HumanoidRootPart.
	  * A LinearVelocity is bound to that Attachment in Plane mode, with the
	    plane spanned by the world X and Z axes. Because the constraint only
	    solves inside that plane, no force is ever applied on Y, so gravity,
	    jumping and falling behave exactly as normal.
	  * Every frame we read Humanoid.MoveDirection and push it into
	    PlaneVelocity as Vector2.new(MoveDirection.X * speed, MoveDirection.Z * speed).
	    Nothing ever writes to HumanoidRootPart.Velocity.
	  * When there is no input the constraint is disabled so the character can
	    slow down, get knocked around, and be moved by other physics normally.

	Panel: draggable, has a speed box (+ a couple of quick presets) and an
	ON/OFF button. RightShift toggles it as well.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==============================================================
-- Config
--==============================================================

local DEFAULT_SPEED = 60
local MIN_SPEED = 0
local MAX_SPEED = 1000
local TOGGLE_KEY = Enum.KeyCode.RightShift
local PRESETS = { 16, 32, 60, 100, 200 }

--==============================================================
-- State
--==============================================================

local enabled = false
local speed = DEFAULT_SPEED

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
	billboard.Size = UDim2.fromOffset(150, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Enabled = false
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "0"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
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

	-- Themed red glow while the mover is actively pushing, dimmed when idle.
	local pushing = linearVelocity ~= nil and linearVelocity.Enabled
	label.TextColor3 = pushing and Color3.fromRGB(255, 90, 90)
		or Color3.fromRGB(225, 225, 235)

	billboard.Enabled = true
end

RunService.Heartbeat:Connect(function()
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

	-- X and Z only. Y never gets a component, so gravity is untouched.
	velocity.PlaneVelocity = Vector2.new(moveDirection.X * speed, moveDirection.Z * speed)
	velocity.Enabled = true
end)

--==============================================================
-- UI  (styled to match the del hub look: dark cards, animated
-- "spark" gradient borders, a pill toggle, and Gotham fonts)
--==============================================================

local TweenService = game:GetService("TweenService")

-- Theme
local PRIMARY       = Color3.fromRGB(200, 0, 0)
local PRIMARY_LIGHT = Color3.fromRGB(255, 60, 60)
local PRIMARY_DARK  = Color3.fromRGB(100, 0, 0)
local BG            = Color3.fromRGB(12, 12, 14)
local CARD          = Color3.fromRGB(22, 22, 26)
local FIELD         = Color3.fromRGB(24, 24, 28)
local TEXT          = Color3.fromRGB(230, 230, 230)
local SUBTEXT       = Color3.fromRGB(170, 170, 180)

-- Animated "spark" gradient border, ported straight from the hub. Every stroke
-- created through addAnimatedStroke registers its gradient with one shared loop
-- that rotates them all in sync.
local strokeRegistry = {}

local function makeSparkSeq(p: Color3): ColorSequence
	local white = Color3.fromRGB(255, 255, 255)
	local function dim(c: Color3, a: number)
		return c:Lerp(Color3.fromRGB(22, 22, 22), a)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(35, 35, 35)),
		ColorSequenceKeypoint.new(0.30, Color3.fromRGB(55, 55, 55)),
		ColorSequenceKeypoint.new(0.44, dim(p, 0.45)),
		ColorSequenceKeypoint.new(0.48, p),
		ColorSequenceKeypoint.new(0.50, p:Lerp(white, 0.35)),
		ColorSequenceKeypoint.new(0.52, p),
		ColorSequenceKeypoint.new(0.60, dim(p, 0.55)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(55, 55, 55)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(35, 35, 35)),
	})
end
local sparkSeq = makeSparkSeq(PRIMARY)

local function addAnimatedStroke(frame: GuiObject, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local grad = Instance.new("UIGradient")
	grad.Color = sparkSeq
	grad.Parent = stroke

	table.insert(strokeRegistry, grad)
	return stroke
end

do
	local angle = 0
	RunService.Heartbeat:Connect(function(dt)
		angle = (angle + 90 * dt) % 360
		for i = #strokeRegistry, 1, -1 do
			local grad = strokeRegistry[i]
			if grad.Parent then
				grad.Rotation = angle
			else
				table.remove(strokeRegistry, i)
			end
		end
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedBoosterPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(250, 200)
panel.Position = UDim2.new(0, 24, 0.5, -100)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(BG:Lerp(CARD, 0.6), Color3.fromRGB(8, 8, 10))
panelGradient.Parent = panel

addAnimatedStroke(panel, 2.5)

-- Header ------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.Parent = panel

local statusDot = Instance.new("Frame")
statusDot.Name = "StatusDot"
statusDot.Size = UDim2.fromOffset(8, 8)
statusDot.Position = UDim2.new(0, 14, 0.5, -4)
statusDot.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
statusDot.BorderSizePixel = 0
statusDot.Parent = header
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -34, 1, 0)
title.Position = UDim2.fromOffset(30, 0)
title.BackgroundTransparency = 1
title.Text = "Dely Booster Test 67"
title.Font = Enum.Font.GothamBlack
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local sep = Instance.new("Frame")
sep.Name = "Separator"
sep.Size = UDim2.new(1, -18, 0, 2)
sep.Position = UDim2.fromOffset(9, 42)
sep.BackgroundColor3 = PRIMARY
sep.BorderSizePixel = 0
sep.Parent = panel
-- breathing separator, same idle animation the hub uses
task.spawn(function()
	while sep and sep.Parent do
		local t1 = TweenService:Create(sep, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.35 })
		t1:Play(); t1.Completed:Wait()
		local t2 = TweenService:Create(sep, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0 })
		t2:Play(); t2.Completed:Wait()
	end
end)

-- Speed row ---------------------------------------------------
local speedRow = Instance.new("Frame")
speedRow.Name = "SpeedRow"
speedRow.Size = UDim2.new(1, -18, 0, 34)
speedRow.Position = UDim2.fromOffset(9, 52)
speedRow.BackgroundColor3 = CARD
speedRow.BorderSizePixel = 0
speedRow.Parent = panel
Instance.new("UICorner", speedRow).CornerRadius = UDim.new(0, 6)
addAnimatedStroke(speedRow, 1)

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(0.5, 0, 1, 0)
speedLabel.Position = UDim2.fromOffset(10, 0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Speed"
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.TextColor3 = TEXT
speedLabel.Parent = speedRow

local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedBox"
speedBox.AnchorPoint = Vector2.new(1, 0.5)
speedBox.Size = UDim2.fromOffset(74, 24)
speedBox.Position = UDim2.new(1, -8, 0.5, 0)
speedBox.BackgroundColor3 = FIELD
speedBox.BorderSizePixel = 0
speedBox.ClearTextOnFocus = false
speedBox.Text = tostring(DEFAULT_SPEED)
speedBox.PlaceholderText = "studs/s"
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 13
speedBox.TextColor3 = PRIMARY_LIGHT
speedBox.Parent = speedRow
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 4)

local speedBoxStroke = Instance.new("UIStroke")
speedBoxStroke.Color = PRIMARY_DARK
speedBoxStroke.Thickness = 1
speedBoxStroke.Parent = speedBox

-- Presets -----------------------------------------------------
local presetRow = Instance.new("Frame")
presetRow.Name = "Presets"
presetRow.Size = UDim2.new(1, -18, 0, 26)
presetRow.Position = UDim2.fromOffset(9, 92)
presetRow.BackgroundTransparency = 1
presetRow.Parent = panel

local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.Padding = UDim.new(0, 6)
presetLayout.Parent = presetRow

-- Enable pill -------------------------------------------------
local toggleRow = Instance.new("Frame")
toggleRow.Name = "ToggleRow"
toggleRow.Size = UDim2.new(1, -18, 0, 36)
toggleRow.Position = UDim2.fromOffset(9, 126)
toggleRow.BackgroundColor3 = CARD
toggleRow.BorderSizePixel = 0
toggleRow.Parent = panel
Instance.new("UICorner", toggleRow).CornerRadius = UDim.new(0, 6)
addAnimatedStroke(toggleRow, 1)

local toggleLabel = Instance.new("TextLabel")
toggleLabel.Name = "ToggleLabel"
toggleLabel.Size = UDim2.new(0.5, 0, 1, 0)
toggleLabel.Position = UDim2.fromOffset(10, 0)
toggleLabel.BackgroundTransparency = 1
toggleLabel.Text = "Enable"
toggleLabel.Font = Enum.Font.GothamBold
toggleLabel.TextSize = 13
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.TextColor3 = TEXT
toggleLabel.Parent = toggleRow

local pill = Instance.new("Frame")
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(1, 0.5)
pill.Size = UDim2.fromOffset(46, 24)
pill.Position = UDim2.new(1, -10, 0.5, 0)
pill.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
pill.BorderSizePixel = 0
pill.Parent = toggleRow
Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.Size = UDim2.fromOffset(18, 18)
dot.Position = UDim2.new(0, 3, 0.5, -9)
dot.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
dot.BorderSizePixel = 0
dot.Parent = pill
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local pillButton = Instance.new("TextButton")
pillButton.Size = UDim2.fromScale(1, 1)
pillButton.BackgroundTransparency = 1
pillButton.Text = ""
pillButton.AutoButtonColor = false
pillButton.Parent = pill

-- Hint --------------------------------------------------------
local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.Size = UDim2.new(1, -18, 0, 16)
hint.Position = UDim2.fromOffset(9, 172)
hint.BackgroundTransparency = 1
hint.Text = "RightShift to toggle"
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = SUBTEXT
hint.TextXAlignment = Enum.TextXAlignment.Center
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

local function setSpeed(value: number)
	speed = math.clamp(value, MIN_SPEED, MAX_SPEED)
	speedBox.Text = tostring(speed)
end

local function animPill(on: boolean)
	TweenService:Create(pill, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
		BackgroundColor3 = on and PRIMARY_DARK or Color3.fromRGB(30, 30, 36),
	}):Play()
	TweenService:Create(dot, TweenInfo.new(0.18, Enum.EasingStyle.Back), {
		Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
		BackgroundColor3 = on and PRIMARY or Color3.fromRGB(100, 100, 100),
	}):Play()
	TweenService:Create(statusDot, TweenInfo.new(0.18), {
		BackgroundColor3 = on and Color3.fromRGB(0, 255, 90) or Color3.fromRGB(120, 120, 120),
	}):Play()
end

local function setEnabled(value: boolean)
	enabled = value
	animPill(enabled)

	if not enabled then
		if linearVelocity then
			linearVelocity.Enabled = false
			linearVelocity.PlaneVelocity = Vector2.zero
		end
		if counterGui then
			counterGui.Enabled = false
		end
	end
end

speedBox.Focused:Connect(function()
	TweenService:Create(speedBoxStroke, TweenInfo.new(0.12), { Color = PRIMARY }):Play()
end)
speedBox.FocusLost:Connect(function()
	TweenService:Create(speedBoxStroke, TweenInfo.new(0.12), { Color = PRIMARY_DARK }):Play()
	local value = tonumber(speedBox.Text)
	if value then
		setSpeed(value)
	else
		speedBox.Text = tostring(speed) -- reject junk input
	end
end)

for _, preset in PRESETS do
	local button = Instance.new("TextButton")
	button.Name = "Preset" .. preset
	button.Size = UDim2.new(0, 38, 1, 0)
	button.BackgroundColor3 = FIELD
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = tostring(preset)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(200, 200, 210)
	button.Parent = presetRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = PRIMARY_DARK
	btnStroke.Thickness = 1
	btnStroke.Transparency = 0.4
	btnStroke.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = PRIMARY_DARK }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = FIELD }):Play()
	end)
	button.Activated:Connect(function()
		setSpeed(preset)
	end)
end

pillButton.Activated:Connect(function()
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

setEnabled(false)
setSpeed(DEFAULT_SPEED)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
