--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CLICK_OFFSET = 0.4
local clickSound = Instance.new("Sound")
clickSound.SoundId = "rbxassetid://88073348503000"
clickSound.Volume = 1
clickSound.Parent = game:GetService("SoundService")
task.spawn(function()
	pcall(function() game:GetService("ContentProvider"):PreloadAsync({ clickSound }) end)
end)
local function playClick()
	clickSound:Play()
	clickSound.TimePosition = CLICK_OFFSET
end
local function hookClick(btn: TextButton)
	btn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			playClick()
		end
	end)
end

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
local antiDie = false
local infJump = false
local antiAfk = false
local fpsUnlock = false

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local head: BasePart? = nil

local attachment: Attachment? = nil
local linearVelocity: LinearVelocity? = nil
local jumpVelocity: LinearVelocity? = nil

local counterGui: BillboardGui? = nil
local counterLabel: TextLabel? = nil

local discordGui: BillboardGui? = nil
local discordEnabled = true
local discordScanT = 0
local DISCORD_BASE_Y = 2.6
local DISCORD_TEXT = "discord.gg/delhub"

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
		antiDie = antiDie,
		infJump = infJump,
		discordEnabled = discordEnabled,
		antiAfk = antiAfk,
		fpsUnlock = fpsUnlock,
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
	if jumpVelocity then
		jumpVelocity:Destroy()
		jumpVelocity = nil
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

	local newJump = Instance.new("LinearVelocity")
	newJump.Name = "SpeedBoosterJump"
	newJump.Attachment0 = newAttachment
	newJump.RelativeTo = Enum.ActuatorRelativeTo.World
	newJump.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	newJump.LineDirection = Vector3.new(0, 1, 0)
	newJump.MaxForce = math.huge
	newJump.LineVelocity = 0
	newJump.Enabled = false
	newJump.Parent = rootPart

	attachment = newAttachment
	linearVelocity = newVelocity
	jumpVelocity = newJump
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

local function teardownDiscord()
	if discordGui then
		discordGui:Destroy()
		discordGui = nil
	end
end

local function buildDiscord()
	teardownDiscord()
	if not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DelDiscordTag"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(172, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, DISCORD_BASE_Y, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Enabled = discordEnabled
	billboard.Parent = head

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Size = UDim2.fromScale(0.94, 0.82)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
	plate.BackgroundTransparency = 0.3
	plate.BorderSizePixel = 0
	plate.ZIndex = 1
	plate.Parent = billboard
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 6)
	plateCorner.Parent = plate
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = RED_MID
	plateStroke.Thickness = 1.5
	plateStroke.Transparency = 0.1
	plateStroke.Parent = plate
	local plateGrad = Instance.new("UIGradient")
	plateGrad.Rotation = 90
	plateGrad.Color = ColorSequence.new(Color3.fromRGB(24, 8, 8), Color3.fromRGB(10, 10, 12))
	plateGrad.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "Tag"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = DISCORD_TEXT
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.ZIndex = 2
	label.Parent = billboard
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label

	discordGui = billboard
end

local onCharacterReady: (() -> ())? = nil

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	head = newCharacter:WaitForChild("Head") :: BasePart
	buildMover()
	buildCounter()
	buildDiscord()
	if onCharacterReady then
		onCharacterReady()
	end
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

local AP_L1 = Vector3.new(-476.47, -6.28, 92.73)
local AP_L2 = Vector3.new(-483.12, -4.95, 94.81)
local AP_R1 = Vector3.new(-476.16, -6.52, 25.62)
local AP_R2 = Vector3.new(-483.06, -5.03, 25.48)
local AUTO_LEFT_WPS = { AP_L1, AP_L2 }
local AUTO_RIGHT_WPS = { AP_R1, AP_R2 }
local AUTO_ARRIVE = 2.5

local autoLeftEnabled = false
local autoRightEnabled = false
local autoPhase = 1
local setAutoLeftVisual: ((boolean) -> ())? = nil
local setAutoRightVisual: ((boolean) -> ())? = nil

local function stopAutoPath()
	autoLeftEnabled = false
	autoRightEnabled = false
	autoPhase = 1
	if setAutoLeftVisual then setAutoLeftVisual(false) end
	if setAutoRightVisual then setAutoRightVisual(false) end
	if linearVelocity then
		linearVelocity.Enabled = false
		linearVelocity.PlaneVelocity = Vector2.zero
	end
end

local function setAutoLeft(on: boolean)
	autoLeftEnabled = on
	autoPhase = 1
	if on and autoRightEnabled then
		autoRightEnabled = false
		if setAutoRightVisual then setAutoRightVisual(false) end
	end
	if setAutoLeftVisual then setAutoLeftVisual(on) end
	if not on and not autoRightEnabled and linearVelocity then
		linearVelocity.Enabled = false
		linearVelocity.PlaneVelocity = Vector2.zero
	end
end

local function setAutoRight(on: boolean)
	autoRightEnabled = on
	autoPhase = 1
	if on and autoLeftEnabled then
		autoLeftEnabled = false
		if setAutoLeftVisual then setAutoLeftVisual(false) end
	end
	if setAutoRightVisual then setAutoRightVisual(on) end
	if not on and not autoLeftEnabled and linearVelocity then
		linearVelocity.Enabled = false
		linearVelocity.PlaneVelocity = Vector2.zero
	end
end

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

local function highestTagTop(base: number, skipA: Instance?, skipB: Instance?): number
	local top = base
	local c = character
	if not c then
		return top
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d ~= skipA and d ~= skipB and d:IsA("BillboardGui") and d.Enabled then
			local y = math.max(d.StudsOffsetWorldSpace.Y, d.StudsOffset.Y) + 1.0
			if y > top then
				top = y
			end
		end
	end
	return top
end

local function updateDiscord()
	local billboard = discordGui
	if not billboard or not billboard.Parent then
		return
	end
	if not discordEnabled then
		billboard.Enabled = false
		return
	end
	billboard.Enabled = true

	local now = tick()
	if now - discordScanT > 0.35 then
		discordScanT = now
		local y = highestTagTop(DISCORD_BASE_Y, billboard)
		if math.abs(billboard.StudsOffsetWorldSpace.Y - y) > 0.05 then
			billboard.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
		end
	end
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
		local y = highestTagTop(COUNTER_BASE_Y, billboard, discordGui)
		if math.abs(billboard.StudsOffsetWorldSpace.Y - y) > 0.05 then
			billboard.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
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
	updateDiscord()

	local velocity = linearVelocity
	if not velocity or not velocity.Parent then
		return
	end

	local hum = humanoid
	local hrp = rootPart
	if not hum or not hrp or hum.Health <= 0 then
		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	if autoLeftEnabled or autoRightEnabled then
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
			velocity.Enabled = false
			return
		end
		local wps = autoLeftEnabled and AUTO_LEFT_WPS or AUTO_RIGHT_WPS
		local target = wps[autoPhase]
		if not target then
			stopAutoPath()
			return
		end
		local pos = hrp.Position
		local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		if flat.Magnitude < AUTO_ARRIVE then
			autoPhase += 1
			if autoPhase > #wps then
				stopAutoPath()
			end
			velocity.Enabled = false
			velocity.PlaneVelocity = Vector2.zero
			return
		end
		local dir = flat.Unit
		local spd = getNormalSpeed()
		velocity.PlaneVelocity = Vector2.new(dir.X * spd, dir.Z * spd)
		velocity.Enabled = true
		return
	end

	if not enabled then
		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	local moveDirection = hum.MoveDirection
	if moveDirection.Magnitude <= 0.01 then
		velocity.Enabled = false
		velocity.PlaneVelocity = Vector2.zero
		return
	end

	local spd = getActiveSpeed()
	velocity.PlaneVelocity = Vector2.new(moveDirection.X * spd, moveDirection.Z * spd)
	velocity.Enabled = true
end)

local grab = {
	enabled = false,
	radius = 55,
	fireRange = 10,
	holdMin = 1.3,
	holdMax = 2.6,
	entryDelay = 0.3,
	data = {},
	busy = false,
	conn = nil,
	stealing = false,
	stealStart = 0,
	stealFlash = 0,
}

local function grabIsMyPlot(plotName)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return false end
	local plot = plots:FindFirstChild(plotName)
	if not plot then return false end
	local sign = plot:FindFirstChild("PlotSign")
	if sign then
		local yb = sign:FindFirstChild("YourBase")
		if yb and yb:IsA("BillboardGui") then
			return yb.Enabled == true
		end
	end
	return false
end

local function grabRoot()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

local function grabNearestPrompt()
	local root = grabRoot()
	if not root then return nil end
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	local nearest, dist = nil, math.huge
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") and not grabIsMyPlot(plot.Name) then
			local pods = plot:FindFirstChild("AnimalPodiums")
			if pods then
				for _, pod in ipairs(pods:GetChildren()) do
					local base = pod:FindFirstChild("Base")
					local sp = base and base:FindFirstChild("Spawn")
					if sp then
						local d = (sp.Position - root.Position).Magnitude
						if d <= grab.radius and d < dist then
							local found = nil
							local att = sp:FindFirstChild("PromptAttachment")
							if att then
								for _, pr in ipairs(att:GetChildren()) do
									if pr:IsA("ProximityPrompt") and pr.ActionText and pr.ActionText:find("Steal") then
										found = pr
									end
								end
							end
							if not found then
								for _, pr in ipairs(sp:GetDescendants()) do
									if pr:IsA("ProximityPrompt") and pr.ActionText and pr.ActionText:find("Steal") then
										found = pr
									end
								end
							end
							if found then
								nearest, dist = found, d
							end
						end
					end
				end
			end
		end
	end
	return nearest
end

local function grabPromptDist(prompt)
	local root = grabRoot()
	if not root then return math.huge end
	local part = prompt.Parent
	if part and part:IsA("Attachment") then part = part.Parent end
	if part and part:IsA("BasePart") then
		return (part.Position - root.Position).Magnitude
	end
	return math.huge
end

local function grabExecute(prompt)
	if grab.busy then return end
	if not grab.data[prompt] then
		grab.data[prompt] = { hold = {}, trigger = {}, ready = true }
		if getconnections then
			for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
				if c.Function then table.insert(grab.data[prompt].hold, c.Function) end
			end
			for _, c in ipairs(getconnections(prompt.Triggered)) do
				if c.Function then table.insert(grab.data[prompt].trigger, c.Function) end
			end
		end
	end
	local data = grab.data[prompt]
	if not data.ready then return end
	data.ready = false
	grab.busy = true
	local start = tick()
	grab.stealing = true
	grab.stealStart = start
	task.spawn(function()
		for _, fn in ipairs(data.hold) do task.spawn(fn) end
		task.wait(grab.holdMin)
		local inRange = grabPromptDist(prompt) <= grab.fireRange
		while true do
			local el = tick() - start
			if el > grab.holdMax or not prompt.Parent then break end
			if grabPromptDist(prompt) <= grab.fireRange then
				if not inRange then task.wait(grab.entryDelay) end
				for _, fn in ipairs(data.trigger) do task.spawn(fn) end
				grab.stealFlash = tick()
				break
			end
			task.wait()
		end
		grab.stealing = false
		task.wait(0.05)
		data.ready = true
		grab.busy = false
	end)
end

local function startAutoGrab()
	if grab.conn then return end
	grab.conn = RunService.Heartbeat:Connect(function()
		if not grab.enabled or grab.busy then return end
		local p = grabNearestPrompt()
		if p then grabExecute(p) end
	end)
end

local function stopAutoGrab()
	if grab.conn then grab.conn:Disconnect(); grab.conn = nil end
	grab.busy = false
	grab.stealing = false
end

local resetRemote = nil
local RESET_GUID = "f888ee6e-c86d-46e1-93d7-0639d6635d42"
local resetDebounce = false

pcall(function()
	if hookfunction and newcclosure then
		local oldFire
		oldFire = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
			if not resetRemote and typeof(self) == "Instance" and self:IsA("RemoteEvent") and self.Name:sub(1, 3) == "RE/" then
				resetRemote = self
			end
			return oldFire(self, ...)
		end))
	end
end)

local function findResetRemote()
	if resetRemote then return resetRemote end
	for _, desc in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
		if desc:IsA("RemoteEvent") and desc.Name:sub(1, 3) == "RE/" then
			resetRemote = desc
			break
		end
	end
	return resetRemote
end

local function instantReset()
	if resetDebounce then return end
	local remote = findResetRemote()
	if not remote then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		pcall(function() remote:FireServer(RESET_GUID, player, "balloon") end)
		return
	end
	resetDebounce = true
	local detected = false
	local conns = {}
	if hum then
		table.insert(conns, hum.Died:Connect(function() detected = true end))
		table.insert(conns, hum:GetPropertyChangedSignal("Health"):Connect(function()
			if hum.Health <= 0 then detected = true end
		end))
	end
	if char then
		table.insert(conns, char.AncestryChanged:Connect(function(_, parent)
			if not parent then detected = true end
		end))
	end
	task.spawn(function()
		for _ = 1, 10 do
			if detected then break end
			pcall(function() remote:FireServer(RESET_GUID, player, "balloon") end)
			task.wait(0.05)
		end
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		task.delay(0.6, function() resetDebounce = false end)
	end)
end

local setAntiDieVisual: ((boolean) -> ())? = nil

local function applyAntiDieState()
	local hum = humanoid
	if not hum then
		return
	end
	hum.BreakJointsOnDeath = not antiDie
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, not antiDie)
	end)
	if antiDie and hum.Health < hum.MaxHealth then
		hum.Health = hum.MaxHealth
	end
end

onCharacterReady = function()
	applyAntiDieState()
end

RunService.Heartbeat:Connect(function()
	if antiDie and humanoid and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
end)

local function setAntiDie(on: boolean)
	antiDie = on
	applyAntiDieState()
	if setAntiDieVisual then
		setAntiDieVisual(on)
	end
	saveConfig()
end

local JUMP_VELOCITY = 50
local JUMP_HOLD = 0.12
local setInfJumpVisual: ((boolean) -> ())? = nil

local function doInfJump()
	local jv = jumpVelocity
	local hum = humanoid
	if not jv or not jv.Parent or not hum or hum.Health <= 0 then
		return
	end
	jv.LineVelocity = JUMP_VELOCITY
	jv.Enabled = true
	task.delay(JUMP_HOLD, function()
		if jumpVelocity == jv and jv.Parent then
			jv.Enabled = false
			jv.LineVelocity = 0
		end
	end)
end

UserInputService.JumpRequest:Connect(function()
	if infJump then
		doInfJump()
	end
end)

local function setInfJump(on: boolean)
	infJump = on
	if not on and jumpVelocity then
		jumpVelocity.Enabled = false
		jumpVelocity.LineVelocity = 0
	end
	if setInfJumpVisual then
		setInfJumpVisual(on)
	end
	saveConfig()
end

local setDiscordVisual: ((boolean) -> ())? = nil

local function setDiscordTag(on: boolean)
	discordEnabled = on
	if discordGui then
		discordGui.Enabled = on
	end
	if setDiscordVisual then
		setDiscordVisual(on)
	end
	saveConfig()
end

local setAntiAfkVisual: ((boolean) -> ())? = nil
local setFpsUnlockVisual: ((boolean) -> ())? = nil

do
	local ok, virtualUser = pcall(function()
		return game:GetService("VirtualUser")
	end)
	if ok and virtualUser then
		player.Idled:Connect(function()
			if not antiAfk then
				return
			end
			pcall(function()
				virtualUser:CaptureController()
				virtualUser:ClickButton2(Vector2.new())
			end)
		end)
	end
end

local function setAntiAfk(on: boolean)
	antiAfk = on
	if setAntiAfkVisual then
		setAntiAfkVisual(on)
	end
	saveConfig()
end

local FPS_UNLOCKED = 240
local FPS_CAPPED = 60

local function setFpsUnlock(on: boolean)
	fpsUnlock = on
	if typeof(setfpscap) == "function" then
		pcall(function()
			setfpscap(on and FPS_UNLOCKED or FPS_CAPPED)
		end)
	end
	if setFpsUnlockVisual then
		setFpsUnlockVisual(on)
	end
	saveConfig()
end

local function rejoinServer()
	local TeleportService = game:GetService("TeleportService")
	pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
	end)
end

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
local PANEL_W, PANEL_H = 250, 236
local function computeScale(): number
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local target = IS_MOBILE and 1.05 or 1.0
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

local TITLE_H = 34
local TAB_Y = 42
local TAB_H = 26
local CONTENT_TOP = 78

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundTransparency = 1
titleBar.ZIndex = 2
titleBar.Parent = panel

local dust = Instance.new("ImageLabel")
dust.Name = "RedstoneDust"
dust.AnchorPoint = Vector2.new(0.5, 0.5)
dust.Size = UDim2.fromOffset(20, 20)
dust.Position = UDim2.new(0, 20, 0.5, 3)
dust.BackgroundTransparency = 1
dust.Image = DUST_IMAGE
dust.ScaleType = Enum.ScaleType.Fit
dust.ImageColor3 = RED_DIM
dust.ZIndex = 3
dust.Parent = titleBar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -46, 1, 0)
title.Position = UDim2.fromOffset(36, 3)
title.BackgroundTransparency = 1
title.Text = "DELY BOOSTER TEST 67"
title.Font = FONT
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextStrokeTransparency = 0.5
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.ZIndex = 3
title.Parent = titleBar

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -20, 0, TAB_H)
tabBar.Position = UDim2.fromOffset(10, TAB_Y)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 2
tabBar.Parent = panel

local function makeTab(): (Frame, UIScale)
	local c = Instance.new("Frame")
	c.Name = "TabContent"
	c.Size = UDim2.new(1, 0, 1, -CONTENT_TOP - 8)
	c.Position = UDim2.fromOffset(0, CONTENT_TOP)
	c.BackgroundTransparency = 1
	c.Visible = false
	c.ZIndex = 2
	c.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Parent = c
	return c, sc
end

local moveTab, moveScale = makeTab()
local autoTab, autoScale = makeTab()
local playerTab, playerScale = makeTab()
local miscTab, miscScale = makeTab()

local tabContents = { moveTab, autoTab, playerTab, miscTab }
local tabScales = { moveScale, autoScale, playerScale, miscScale }
local tabDefs = { "MOVE", "AUTO", "PLAYER", "MISC" }
local tabButtons: { TextButton } = {}
local activeTab = 1
local TAB_COUNT = #tabDefs

local function setTab(index: number)
	activeTab = index
	for i, content in ipairs(tabContents) do
		content.Visible = (i == index)
	end
	for i, btn in ipairs(tabButtons) do
		local on = i == index
		TweenService:Create(btn, TweenInfo.new(0.14), {
			BackgroundColor3 = on and CRIMSON or Color3.fromRGB(30, 30, 34),
		}):Play()
		btn.TextColor3 = on and Color3.fromRGB(255, 235, 235) or SUBTEXT
	end
	punch(tabScales[index], 0.95)
end

for i, name in ipairs(tabDefs) do
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Tab"
	btn.Size = UDim2.new(1 / TAB_COUNT, -3, 1, 0)
	btn.Position = UDim2.new((i - 1) / TAB_COUNT, 1.5, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	btn.Text = name
	btn.Font = FONT
	btn.TextSize = 13
	btn.TextColor3 = SUBTEXT
	btn.AutoButtonColor = false
	btn.ZIndex = 3
	btn.Parent = tabBar
	round(btn, 6)
	edgeStroke(btn, Color3.fromRGB(62, 62, 70), 1, 0.4)
	btn.Activated:Connect(function()
		setTab(i)
	end)
	tabButtons[i] = btn
end

local function makeSpeedRow(name: string, labelText: string, defaultValue: number, y: number, parent: Instance)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 32)
	row.Position = UDim2.fromOffset(10, y)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	row.BorderSizePixel = 0
	row.ZIndex = 2
	row.Parent = parent
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

local normalBox, normalLabel, normalBoxScale = makeSpeedRow("Normal", "NORMAL SPEED", DEFAULT_NORMAL_SPEED, 0, moveTab)
local carryBox, carryLabel, carryBoxScale = makeSpeedRow("Carry", "CARRY SPEED", DEFAULT_CARRY_SPEED, 38, moveTab)

local toggleRow = Instance.new("Frame")
toggleRow.Name = "ToggleRow"
toggleRow.Size = UDim2.new(1, -20, 0, 32)
toggleRow.Position = UDim2.fromOffset(10, 76)
toggleRow.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
toggleRow.BorderSizePixel = 0
toggleRow.ZIndex = 2
toggleRow.Parent = moveTab
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

local function makeSwitchRow(name: string, labelText: string, y: number, parent: Instance, onClick: () -> ())
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 32)
	row.Position = UDim2.fromOffset(10, y)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	row.BorderSizePixel = 0
	row.ZIndex = 2
	row.Parent = parent
	round(row, 6)
	edgeStroke(row, Color3.fromRGB(62, 62, 70), 1, 0.25)
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(34, 34, 38) }):Play()
	end)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = FONT
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = TEXT
	label.ZIndex = 3
	label.Parent = row

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Size = UDim2.fromOffset(44, 18)
	track.Position = UDim2.new(1, -10, 0.5, 0)
	track.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	track.BorderSizePixel = 0
	track.ZIndex = 3
	track.Parent = row
	round(track, 9)
	edgeStroke(track, Color3.fromRGB(8, 8, 10), 1, 0.1)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = UDim2.new(0, 1, 0.5, -8)
	knob.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
	knob.BorderSizePixel = 0
	knob.ZIndex = 4
	knob.Parent = track
	round(knob, 8)

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 6
	btn.Parent = row
	btn.Activated:Connect(onClick)

	return function(on: boolean)
		TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -17, 0.5, -8) or UDim2.new(0, 1, 0.5, -8),
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.16), {
			BackgroundColor3 = on and RED_BRIGHT or Color3.fromRGB(70, 70, 76),
		}):Play()
		label.TextColor3 = on and RED_BRIGHT or TEXT
	end
end

setInfJumpVisual = makeSwitchRow("InfJump", "INF JUMP", 114, moveTab, function()
	setInfJump(not infJump)
end)

local function makeAutoRow(y: number, parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "AutoRow"
	row.Size = UDim2.new(1, -20, 0, 40)
	row.Position = UDim2.fromOffset(10, y)
	row.BackgroundTransparency = 1
	row.ZIndex = 2
	row.Parent = parent

	local function makeBtn(text: string, xScale: number)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.5, -3, 1, 0)
		btn.Position = UDim2.new(xScale, xScale == 0 and 0 or 3, 0, 0)
		btn.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
		btn.Text = text
		btn.Font = FONT
		btn.TextSize = 16
		btn.TextColor3 = TEXT
		btn.AutoButtonColor = false
		btn.ZIndex = 3
		btn.Parent = row
		round(btn, 6)
		edgeStroke(btn, Color3.fromRGB(62, 62, 70), 1, 0.25)
		local sc = Instance.new("UIScale")
		sc.Parent = btn
		return btn, sc
	end

	local leftBtn, leftScale = makeBtn("AUTO LEFT", 0)
	local rightBtn, rightScale = makeBtn("AUTO RIGHT", 0.5)

	local function hover(btn: TextButton, isOn: () -> boolean)
		btn.MouseEnter:Connect(function()
			if not isOn() then
				TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(46, 46, 52) }):Play()
			end
		end)
		btn.MouseLeave:Connect(function()
			if not isOn() then
				TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(34, 34, 38) }):Play()
			end
		end)
	end
	hover(leftBtn, function() return autoLeftEnabled end)
	hover(rightBtn, function() return autoRightEnabled end)

	leftBtn.Activated:Connect(function()
		punch(leftScale, 0.9)
		setAutoLeft(not autoLeftEnabled)
	end)
	rightBtn.Activated:Connect(function()
		punch(rightScale, 0.9)
		setAutoRight(not autoRightEnabled)
	end)

	local function styler(btn: TextButton)
		return function(on: boolean)
			TweenService:Create(btn, TweenInfo.new(0.14), {
				BackgroundColor3 = on and CRIMSON or Color3.fromRGB(34, 34, 38),
			}):Play()
			btn.TextColor3 = on and Color3.fromRGB(255, 235, 235) or TEXT
		end
	end

	return styler(leftBtn), styler(rightBtn)
end

setAutoLeftVisual, setAutoRightVisual = makeAutoRow(0, autoTab)

local setStealBarVisible: ((boolean) -> ())? = nil

local setAutoGrabVisual
setAutoGrabVisual = makeSwitchRow("AutoGrab", "AUTO GRAB", 48, autoTab, function()
	grab.enabled = not grab.enabled
	if grab.enabled then startAutoGrab() else stopAutoGrab() end
	setAutoGrabVisual(grab.enabled)
	if setStealBarVisible then setStealBarVisible(grab.enabled) end
end)

setAntiDieVisual = makeSwitchRow("AntiDie", "ANTI DIE", 0, playerTab, function()
	setAntiDie(not antiDie)
end)

setAntiAfkVisual = makeSwitchRow("AntiAfk", "ANTI AFK", 38, playerTab, function()
	setAntiAfk(not antiAfk)
end)

local counterRow = Instance.new("Frame")
counterRow.Name = "CounterRow"
counterRow.Size = UDim2.new(1, -20, 0, 32)
counterRow.Position = UDim2.fromOffset(10, 76)
counterRow.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
counterRow.BorderSizePixel = 0
counterRow.ZIndex = 2
counterRow.Parent = playerTab
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

local function makeFlatButton(name: string, labelText: string, y: number, parent: Instance, onClick: () -> ())
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Button"
	btn.Size = UDim2.new(1, -20, 0, 32)
	btn.Position = UDim2.fromOffset(10, y)
	btn.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	btn.Text = labelText
	btn.Font = FONT
	btn.TextSize = 16
	btn.TextColor3 = TEXT
	btn.AutoButtonColor = false
	btn.ZIndex = 2
	btn.Parent = parent
	round(btn, 6)
	edgeStroke(btn, Color3.fromRGB(62, 62, 70), 1, 0.25)
	local sc = Instance.new("UIScale")
	sc.Parent = btn

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = CRIMSON, TextColor3 = Color3.fromRGB(255, 235, 235) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(34, 34, 38), TextColor3 = TEXT }):Play()
	end)
	btn.Activated:Connect(function()
		punch(sc, 0.9)
		onClick()
	end)
	return btn
end

makeFlatButton("InstantReset", "INSTANT RESET", 114, playerTab, instantReset)

setFpsUnlockVisual = makeSwitchRow("FpsUnlock", "FPS UNLOCK", 0, miscTab, function()
	setFpsUnlock(not fpsUnlock)
end)

makeFlatButton("Rejoin", "REJOIN SERVER", 38, miscTab, rejoinServer)

setDiscordVisual = makeSwitchRow("DiscordTag", "DISCORD TAG", 76, miscTab, function()
	setDiscordTag(not discordEnabled)
end)

local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credit"
creditLabel.Size = UDim2.new(1, -20, 0, 20)
creditLabel.Position = UDim2.fromOffset(10, 116)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = DISCORD_TEXT
creditLabel.Font = FONT
creditLabel.TextSize = 14
creditLabel.TextXAlignment = Enum.TextXAlignment.Center
creditLabel.TextColor3 = SUBTEXT
creditLabel.ZIndex = 3
creditLabel.Parent = miscTab

setTab(1)

local stealBar = Instance.new("Frame")
stealBar.Name = "StealBar"
stealBar.AnchorPoint = Vector2.new(0.5, 1)
stealBar.Size = UDim2.fromOffset(240, 46)
stealBar.Position = UDim2.new(0.5, 0, 1, 46)
stealBar.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
stealBar.BorderSizePixel = 0
stealBar.Visible = false
stealBar.ZIndex = 15
stealBar.Parent = gui
round(stealBar, 8)
edgeStroke(stealBar, REDDISH_BLACK, 1.5, 0.1)
local stealBarScale = Instance.new("UIScale")
stealBarScale.Parent = stealBar

local stealGrad = Instance.new("UIGradient")
stealGrad.Rotation = 90
stealGrad.Color = ColorSequence.new(Color3.fromRGB(30, 30, 34), Color3.fromRGB(16, 16, 18))
stealGrad.Parent = stealBar

local stealLabel = Instance.new("TextLabel")
stealLabel.Name = "Label"
stealLabel.Size = UDim2.new(1, -20, 0, 16)
stealLabel.Position = UDim2.fromOffset(10, 5)
stealLabel.BackgroundTransparency = 1
stealLabel.Text = "AUTO GRAB"
stealLabel.Font = FONT
stealLabel.TextSize = 13
stealLabel.TextXAlignment = Enum.TextXAlignment.Left
stealLabel.TextColor3 = TEXT
stealLabel.TextStrokeTransparency = 0.6
stealLabel.ZIndex = 16
stealLabel.Parent = stealBar

local stealTrack = Instance.new("Frame")
stealTrack.Name = "Track"
stealTrack.AnchorPoint = Vector2.new(0.5, 1)
stealTrack.Size = UDim2.new(1, -20, 0, 12)
stealTrack.Position = UDim2.new(0.5, 0, 1, -8)
stealTrack.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
stealTrack.BorderSizePixel = 0
stealTrack.ZIndex = 16
stealTrack.Parent = stealBar
round(stealTrack, 6)
edgeStroke(stealTrack, Color3.fromRGB(8, 8, 10), 1, 0.2)

local stealFill = Instance.new("Frame")
stealFill.Name = "Fill"
stealFill.Size = UDim2.new(0, 0, 1, 0)
stealFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
stealFill.BorderSizePixel = 0
stealFill.ZIndex = 17
stealFill.Parent = stealTrack
round(stealFill, 6)
local stealFillGrad = Instance.new("UIGradient")
stealFillGrad.Color = ColorSequence.new(CRIMSON, SCARLET)
stealFillGrad.Parent = stealFill

local SB_SHOW = UDim2.new(0.5, 0, 1, -26)
local SB_HIDE = UDim2.new(0.5, 0, 1, 46)
local sbVisible = false

setStealBarVisible = function(on: boolean)
	if on == sbVisible then
		return
	end
	sbVisible = on
	if on then
		stealBar.Visible = true
		stealBar.Position = SB_HIDE
		stealBarScale.Scale = 0.7
		TweenService:Create(stealBar, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SB_SHOW }):Play()
		TweenService:Create(stealBarScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		local tw = TweenService:Create(stealBar, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = SB_HIDE })
		tw:Play()
		TweenService:Create(stealBarScale, TweenInfo.new(0.24), { Scale = 0.7 }):Play()
		tw.Completed:Connect(function()
			if not sbVisible then
				stealBar.Visible = false
			end
		end)
	end
end

do
	local shownFill = 0
	local lastText = ""
	RunService.Heartbeat:Connect(function(dt)
		if not sbVisible then
			return
		end
		local flashing = (tick() - grab.stealFlash) < 0.45
		local target = 0
		if grab.stealing then
			target = math.clamp((tick() - grab.stealStart) / grab.holdMax, 0.02, 1)
		end
		if flashing then
			target = 1
		end
		shownFill = shownFill + (target - shownFill) * math.min(dt * 12, 1)
		stealFill.Size = UDim2.new(shownFill, 0, 1, 0)

		local txt = "AUTO GRAB"
		if flashing then
			txt = "STOLEN"
		elseif grab.stealing then
			txt = "STEALING"
		end
		if txt ~= lastText then
			lastText = txt
			stealLabel.Text = txt
			stealLabel.TextColor3 = (flashing and SCARLET) or (grab.stealing and RED_BRIGHT) or TEXT
		end
	end)
end

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleButton"
toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
toggleBtn.Size = UDim2.fromOffset(46, 46)
toggleBtn.Position = UDim2.new(0.5, 0, 0, 12)
toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
toggleBtn.Text = ""
toggleBtn.AutoButtonColor = false
toggleBtn.Active = true
toggleBtn.ZIndex = 20
toggleBtn.Parent = gui
round(toggleBtn, 12)
edgeStroke(toggleBtn, REDDISH_BLACK, 2, 0)
local toggleGrad = Instance.new("UIGradient")
toggleGrad.Rotation = 90
toggleGrad.Color = ColorSequence.new(Color3.fromRGB(30, 30, 34), Color3.fromRGB(14, 14, 16))
toggleGrad.Parent = toggleBtn
local toggleScale = Instance.new("UIScale")
toggleScale.Parent = toggleBtn

local toggleIcon = Instance.new("ImageLabel")
toggleIcon.Name = "Icon"
toggleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
toggleIcon.Position = UDim2.fromScale(0.5, 0.5)
toggleIcon.Size = UDim2.fromOffset(28, 28)
toggleIcon.BackgroundTransparency = 1
toggleIcon.Image = DUST_IMAGE
toggleIcon.ScaleType = Enum.ScaleType.Fit
toggleIcon.ImageColor3 = Color3.fromRGB(230, 60, 60)
toggleIcon.ZIndex = 21
toggleIcon.Parent = toggleBtn

local panelVisible = true
local function setPanelVisible(v: boolean)
	if v == panelVisible then
		return
	end
	panelVisible = v
	punch(toggleScale, 0.8)
	if v then
		panel.Visible = true
		panelScale.Scale = deviceScale * 0.6
		TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = deviceScale }):Play()
	else
		local tw = TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = deviceScale * 0.5 })
		tw:Play()
		tw.Completed:Connect(function()
			if not panelVisible then
				panel.Visible = false
			end
		end)
	end
end

do
	local dragging, moved, dragStart, startPos = false, false, nil, nil
	toggleBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = toggleBtn.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved then
						setPanelVisible(not panelVisible)
					end
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			if delta.Magnitude > 6 then
				moved = true
			end
			toggleBtn.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

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
setAntiDie(false)
setInfJump(false)
setDiscordTag(true)
setAntiAfk(false)
setFpsUnlock(false)

local savedCfg = loadConfig()
if savedCfg then
	if type(savedCfg.normalSpeed) == "number" then setNormalSpeed(savedCfg.normalSpeed) end
	if type(savedCfg.carrySpeed) == "number" then setCarrySpeed(savedCfg.carrySpeed) end
	if savedCfg.counterEnabled ~= nil then setCounterEnabled(savedCfg.counterEnabled == true) end
	if savedCfg.antiDie ~= nil then setAntiDie(savedCfg.antiDie == true) end
	if savedCfg.infJump ~= nil then setInfJump(savedCfg.infJump == true) end
	if savedCfg.discordEnabled ~= nil then setDiscordTag(savedCfg.discordEnabled == true) end
	if savedCfg.antiAfk ~= nil then setAntiAfk(savedCfg.antiAfk == true) end
	if savedCfg.fpsUnlock ~= nil then setFpsUnlock(savedCfg.fpsUnlock == true) end
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

for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("TextButton") then
		hookClick(d)
	end
end
gui.DescendantAdded:Connect(function(d)
	if d:IsA("TextButton") then
		hookClick(d)
	end
end)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
