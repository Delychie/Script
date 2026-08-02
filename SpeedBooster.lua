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

local attachment: Attachment? = nil
local linearVelocity: LinearVelocity? = nil

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

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	buildMover()
end

--==============================================================
-- Movement loop
--==============================================================

RunService.Heartbeat:Connect(function()
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
-- UI
--==============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedBoosterPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(240, 172)
panel.Position = UDim2.new(0, 24, 0.5, -86)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true -- simple built-in dragging
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 60, 70)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 34)
title.BackgroundTransparency = 1
title.Text = "Speed Booster"
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.Parent = panel

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(0, 56, 0, 30)
speedLabel.Position = UDim2.fromOffset(12, 40)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Speed"
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
speedLabel.Parent = panel

local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedBox"
speedBox.Size = UDim2.new(1, -80, 0, 30)
speedBox.Position = UDim2.fromOffset(68, 40)
speedBox.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
speedBox.BorderSizePixel = 0
speedBox.ClearTextOnFocus = false
speedBox.Text = tostring(DEFAULT_SPEED)
speedBox.PlaceholderText = "studs / sec"
speedBox.Font = Enum.Font.Gotham
speedBox.TextSize = 14
speedBox.TextColor3 = Color3.fromRGB(235, 235, 240)
speedBox.Parent = panel

local speedBoxCorner = Instance.new("UICorner")
speedBoxCorner.CornerRadius = UDim.new(0, 6)
speedBoxCorner.Parent = speedBox

local presetRow = Instance.new("Frame")
presetRow.Name = "Presets"
presetRow.Size = UDim2.new(1, -24, 0, 26)
presetRow.Position = UDim2.fromOffset(12, 78)
presetRow.BackgroundTransparency = 1
presetRow.Parent = panel

local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.Padding = UDim.new(0, 6)
presetLayout.Parent = presetRow

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "Toggle"
toggleButton.Size = UDim2.new(1, -24, 0, 36)
toggleButton.Position = UDim2.fromOffset(12, 116)
toggleButton.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
toggleButton.BorderSizePixel = 0
toggleButton.AutoButtonColor = true
toggleButton.Text = "OFF"
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 15
toggleButton.TextColor3 = Color3.fromRGB(235, 235, 240)
toggleButton.Parent = panel

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleButton

--==============================================================
-- UI behaviour
--==============================================================

local function setSpeed(value: number)
	speed = math.clamp(value, MIN_SPEED, MAX_SPEED)
	speedBox.Text = tostring(speed)
end

local function setEnabled(value: boolean)
	enabled = value
	toggleButton.Text = enabled and "ON" or "OFF"
	toggleButton.BackgroundColor3 = enabled and Color3.fromRGB(46, 150, 92)
		or Color3.fromRGB(58, 58, 66)

	if not enabled and linearVelocity then
		linearVelocity.Enabled = false
		linearVelocity.PlaneVelocity = Vector2.zero
	end
end

speedBox.FocusLost:Connect(function()
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
	button.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
	button.BorderSizePixel = 0
	button.Text = tostring(preset)
	button.Font = Enum.Font.Gotham
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(200, 200, 210)
	button.Parent = presetRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	button.Activated:Connect(function()
		setSpeed(preset)
	end)
end

toggleButton.Activated:Connect(function()
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
