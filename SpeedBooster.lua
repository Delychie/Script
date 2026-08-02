--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DEFAULT_NORMAL_SPEED = 60
local DEFAULT_CARRY_SPEED = 27
local MIN_SPEED = 0
local MAX_SPEED = 1000
local CONFIG_FILE = "dely_booster_test67.json"

local LEVER_ON_IMAGE = "rbxassetid://102532019315855"
local LEVER_OFF_IMAGE = "rbxassetid://130564537890360"

local DUST_IMAGE = "rbxassetid://83833754384535"

local CARRY_WALKSPEED_MAX = 25

local STONE_TOP   = Color3.fromRGB(46, 46, 50)
local STONE_BOT   = Color3.fromRGB(24, 24, 26)
local SLOT        = Color3.fromRGB(18, 18, 20)
local BEVEL_HI    = Color3.fromRGB(78, 78, 84)
local BEVEL_LO    = Color3.fromRGB(10, 10, 12)
local REDDISH_BLACK = Color3.fromRGB(40, 7, 7)
local CRIMSON       = Color3.fromRGB(178, 20, 48)
local RED           = Color3.fromRGB(235, 22, 22)
local SCARLET       = Color3.fromRGB(255, 62, 28)
local RED_DIM     = REDDISH_BLACK
local RED_BRIGHT  = Color3.fromRGB(255, 48, 48)
local RED_MID     = Color3.fromRGB(200, 30, 30)

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
local FONT        = Enum.Font.Arcade

local enabled = false
local normalSpeed = DEFAULT_NORMAL_SPEED
local carrySpeed = DEFAULT_CARRY_SPEED
local carrying = false

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local head: BasePart? = nil

local attachment: Attachment? = nil
local linearVelocity: LinearVelocity? = nil

local counterGui: BillboardGui? = nil
local counterLabel: TextLabel? = nil

local counterEnabled = false
local prevSpeed = 0
local speedAnimActive = false
local lastSpeedFlash = 0
local counterScanT = 0
local lastShownSpeed = -1
local COUNTER_BASE_Y = 2.6
local BB_NORMAL = UDim2.fromOffset(150, 40)
local BB_MID = UDim2.fromOffset(162, 44)
local BB_BIG = UDim2.fromOffset(174, 48)

local savedGuiPos = nil
local suppressSave = false
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

	newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	newVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	newVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)

	newVelocity.MaxForce = math.huge
	newVelocity.PlaneVelocity = Vector2.zero
	newVelocity.Enabled = false
	newVelocity.Parent = rootPart

	attachment = newAttachment
	linearVelocity = newVelocity
end

local function teardownCounter()
	if counterGui then
		counterGui:Destroy()
		counterGui = nil
		counterLabel = nil
	end
end

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
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Enabled = false
	billboard.Parent = head

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

local function isCarryingBrainrot(): boolean
	if player:GetAttribute("Stealing") == true then
		return true
	end
	if humanoid and humanoid.WalkSpeed > 0 and humanoid.WalkSpeed < CARRY_WALKSPEED_MAX then
		return true
	end
	return false
end

local function getNormalSpeed(): number
	return normalSpeed
end
local function getCarrySpeed(): number
	return carrySpeed
end

local function getActiveSpeed(): number
	if carrying then
		return getCarrySpeed()
	end
	return getNormalSpeed()
end

local onCarryChanged: (() -> ())? = nil

local function measureHorizontalSpeed(): number
	if not rootPart then
		return 0
	end
	local assemblyVelocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(assemblyVelocity.X, 0, assemblyVelocity.Z).Magnitude
end

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
	local rounded = math.round(current)
	if rounded ~= lastShownSpeed then
		label.Text = tostring(rounded)
		lastShownSpeed = rounded
	end

	local delta = current - prevSpeed
	prevSpeed = current
	if delta > 18 then
		triggerSpeedFlash(true)
	elseif delta > 6 then
		triggerSpeedFlash(false)
	end

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

		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	local spd = getActiveSpeed()
	velocity.PlaneVelocity = Vector2.new(moveDirection.X * spd, moveDirection.Z * spd)
	velocity.Enabled = true
end)

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

local function punch(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

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

local redstoneLines: { Frame } = {}
local redstoneImages: { ImageLabel } = {}
local powerSurge = 0

local panelBorder: UIStroke? = nil
local panelBorderGrad: UIGradient? = nil
local PANEL_BORDER_BASE = 3
local borderSpin = 0

do
	local t = 0
	local idleApplied = false
	RunService.Heartbeat:Connect(function(dt)

		if not enabled and powerSurge <= 0.001 and math.abs(borderSpin) <= 0.5 then
			if not idleApplied then
				idleApplied = true
				powerSurge, borderSpin = 0, 0
				local col = RED_DIM
				for _, l in ipairs(redstoneLines) do if l.Parent then l.BackgroundColor3 = col end end
				for _, img in ipairs(redstoneImages) do if img.Parent then img.ImageColor3 = col end end
				if panelBorder and panelBorderGrad then
					panelBorderGrad.Enabled = false
					panelBorder.Color = REDDISH_BLACK
					panelBorder.Thickness = PANEL_BORDER_BASE
				end
			end
			return
		end
		idleApplied = false

		t += dt
		powerSurge = math.max(0, powerSurge - dt * 2.5)
		borderSpin = borderSpin - borderSpin * math.min(dt * 3.5, 1)

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

		if panelBorder and panelBorderGrad then
			if enabled then
				panelBorderGrad.Enabled = true
				panelBorder.Color = Color3.fromRGB(255, 255, 255)
				panelBorderGrad.Rotation = (panelBorderGrad.Rotation + (100 + borderSpin) * dt) % 360
				panelBorder.Thickness = PANEL_BORDER_BASE + math.sin(t * 6) * 0.8 + powerSurge * 2 + borderSpin * 0.004
			else
				panelBorderGrad.Enabled = false
				panelBorder.Color = REDDISH_BLACK
				panelBorder.Thickness = PANEL_BORDER_BASE
			end
		end
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedBoosterPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local PANEL_W, PANEL_H = 250, 200
local function computeScale(): number
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local target = IS_MOBILE and 1.3 or 1.0
	return math.clamp(math.min(target, (vp.X - 20) / PANEL_W, (vp.Y - 20) / PANEL_H), 0.55, 1.4)
end
local deviceScale = computeScale()

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 24, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(Color3.fromRGB(30, 30, 34), Color3.fromRGB(14, 14, 16))
panelGradient.Parent = panel

round(panel, 12)

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
panelScale.Scale = deviceScale
panelScale.Parent = panel

local function panelPop(from: number)
	panelScale.Scale = deviceScale * from
	TweenService:Create(panelScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = deviceScale,
	}):Play()
end

do
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			deviceScale = computeScale()
			panelScale.Scale = deviceScale
		end)
	end
end

local dust = Instance.new("ImageLabel")
dust.Name = "RedstoneDust"
dust.AnchorPoint = Vector2.new(0.5, 0.5)
dust.Size = UDim2.fromOffset(20, 20)
dust.Position = UDim2.new(0, 20, 0, 26)
dust.BackgroundTransparency = 1
dust.Image = DUST_IMAGE
dust.ScaleType = Enum.ScaleType.Fit
dust.ImageColor3 = RED_DIM
dust.ZIndex = 3
dust.Parent = panel
table.insert(redstoneImages, dust)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -46, 0, 24)
title.Position = UDim2.fromOffset(36, 14)
title.BackgroundTransparency = 1
title.Text = "DELY BOOSTER TEST 67"
title.Font = FONT
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextStrokeTransparency = 0.5
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.ZIndex = 3
title.Parent = panel

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
	edgeStroke(row, Color3.fromRGB(62, 62, 70), 1, 0.25)

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
	edgeStroke(box, Color3.fromRGB(8, 8, 10), 1, 0)
	local boxScale = Instance.new("UIScale")
	boxScale.Parent = box

	local base = row.BackgroundColor3
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end)

	box.Focused:Connect(function()
		punch(boxScale, 1.14)
		TweenService:Create(box, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(42, 20, 20) }):Play()
	end)

	return box, label, boxScale
end

local normalBox, normalLabel, normalBoxScale = makeSpeedRow("Normal", "NORMAL SPEED", DEFAULT_NORMAL_SPEED, 46)
local carryBox, carryLabel, carryBoxScale = makeSpeedRow("Carry", "CARRY SPEED", DEFAULT_CARRY_SPEED, 84)

local toggleRow = Instance.new("Frame")
toggleRow.Name = "ToggleRow"
toggleRow.Size = UDim2.new(1, -20, 0, 32)
toggleRow.Position = UDim2.fromOffset(10, 122)
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

local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.AnchorPoint = Vector2.new(0.5, 0)
knob.Size = UDim2.fromOffset(12, 12)
knob.Position = UDim2.new(0.5, 0, 0, -4)
knob.BackgroundColor3 = Color3.fromRGB(70, 22, 22)
knob.BorderSizePixel = 0
knob.ZIndex = 5
knob.Parent = handle
round(knob, 6)

local useLeverImage = LEVER_ON_IMAGE ~= ""
local leverImage: ImageLabel? = nil
local leverImageScale: UIScale? = nil
if useLeverImage then
	leverBase.Visible = false
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

local leverButton = Instance.new("TextButton")
leverButton.Size = UDim2.fromScale(1, 1)
leverButton.BackgroundTransparency = 1
leverButton.Text = ""
leverButton.AutoButtonColor = false
leverButton.ZIndex = 6
leverButton.Parent = toggleRow

local counterRow = Instance.new("Frame")
counterRow.Name = "CounterRow"
counterRow.Size = UDim2.new(1, -20, 0, 32)
counterRow.Position = UDim2.fromOffset(10, 160)
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

local swTrack = Instance.new("Frame")
swTrack.Name = "SwitchTrack"
swTrack.AnchorPoint = Vector2.new(1, 0.5)
swTrack.Size = UDim2.fromOffset(44, 18)
swTrack.Position = UDim2.new(1, -10, 0.5, 0)
swTrack.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
swTrack.BorderSizePixel = 0
swTrack.ZIndex = 3
swTrack.Parent = counterRow
round(swTrack, 9)
edgeStroke(swTrack, Color3.fromRGB(8, 8, 10), 1, 0.1)

local swKnob = Instance.new("Frame")
swKnob.Name = "SwitchKnob"
swKnob.Size = UDim2.fromOffset(16, 16)
swKnob.Position = UDim2.new(0, 1, 0.5, -8)
swKnob.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
swKnob.BorderSizePixel = 0
swKnob.ZIndex = 4
swKnob.Parent = swTrack
round(swKnob, 8)

local counterButton = Instance.new("TextButton")
counterButton.Size = UDim2.fromScale(1, 1)
counterButton.BackgroundTransparency = 1
counterButton.Text = ""
counterButton.AutoButtonColor = false
counterButton.ZIndex = 6
counterButton.Parent = counterRow

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

local function animLever(on: boolean)
	if useLeverImage and leverImage then
		leverImage.Image = on and LEVER_ON_IMAGE
			or ((LEVER_OFF_IMAGE ~= "" and LEVER_OFF_IMAGE) or LEVER_ON_IMAGE)

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

	TweenService:Create(title, TweenInfo.new(0.18), {
		TextColor3 = on and Color3.fromRGB(255, 232, 232) or Color3.fromRGB(245, 245, 248),
	}):Play()
end

local function updateMode()
	local normalActive = enabled and not carrying
	local carryActive = enabled and carrying
	normalLabel.TextColor3 = normalActive and RED_BRIGHT or TEXT
	carryLabel.TextColor3 = carryActive and RED_BRIGHT or TEXT

	normalBox.BackgroundColor3 = normalActive and Color3.fromRGB(34, 16, 16) or SLOT
	carryBox.BackgroundColor3 = carryActive and Color3.fromRGB(34, 16, 16) or SLOT
end

local function setEnabled(value: boolean)
	enabled = value
	animLever(enabled)

	if enabled then
		powerSurge = 1
		panelPop(1.03)
		borderSpin = 1000
		if panelBorder then
			panelBorder.Transparency = 1
			TweenService:Create(panelBorder, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0,
			}):Play()
		end
	else
		if linearVelocity then
			linearVelocity.Enabled = false
			linearVelocity.PlaneVelocity = Vector2.zero
		end
		if panelBorder then
			panelBorder.Transparency = 0
		end
	end
	updateMode()
	saveConfig()
end

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
		prevSpeed = measureHorizontalSpeed()
	end
	if counterGui then
		counterGui.Enabled = value
	end
	saveConfig()
end

local function wireBox(box: TextBox, setter: (number) -> (), getter: () -> number)
	box.FocusLost:Connect(function()
		local value = tonumber(box.Text)
		if value then
			setter(value)
		else
			box.Text = tostring(getter())
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

onCarryChanged = function()
	updateMode()
	if enabled then
		punch(carrying and carryBoxScale or normalBoxScale, 1.15)
	end
end

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

panelPop(0.8)
task.delay(0.12, function()
	shake(dust, 16, 0.6)
	shake(leverImage, 12, 0.6)
end)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
