--!nonstrict

-- AutoBlocker: every time you join a server, this blocks ONE random player who is
-- NOT your friend, then (optionally) server-hops you into a fresh server you have not
-- visited yet. Roblox matchmaking tries to keep you out of servers full of people you
-- have blocked, so building up a block list is what actually stops you from landing
-- back in the same server every time you hop.
--
-- Friends are NEVER blocked. If the friend check for a candidate fails for any reason,
-- that candidate is skipped (fail-safe), so a friend can't be blocked by accident.
--
-- Blocking is a normal Roblox client feature: the person isn't notified, isn't
-- reported, and nothing happens to their account - you just stop being matched with
-- and seeing them. Nothing here targets a specific person; it picks at random.
--
-- Run it from a client-side script runner (executor). Server-list fetching, the
-- filesystem "remember visited servers" feature, and auto-chaining across hops all
-- need executor functions and no-op safely when they aren't available.

--// ============================ CONFIG ============================
local BLOCK_ON_JOIN   = true   -- block one random non-friend the moment the script runs
local HOP_AFTER_BLOCK = false  -- OFF: only block, never server-hop
local AVOID_FRIENDS   = true   -- never block friends (leave this on)
local AUTO_CHAIN      = false  -- (only relevant if hopping is on)

local BLOCK_DELAY     = 0      -- extra seconds to wait before blocking (0 = as soon as ready)
local HOP_DELAY       = 1.5    -- seconds to wait after blocking before hopping (only if hopping)
local MAX_BLOCKS      = 0      -- stop blocking after this many total blocks (0 = no limit)
-- Auto-execute runs this before the game/players have loaded, so it first waits for the
-- game, your LocalPlayer, and at least one other player (up to this many seconds) before
-- blocking. On a manual run everything's already loaded, so it stays instant.
local READY_TIMEOUT   = 20     -- max seconds to wait for the game + LocalPlayer
local PLAYER_TIMEOUT  = 15     -- max seconds to wait for another player to be blockable

-- If the silent block module can't be found on your client, fall back to the native
-- block prompt (StarterGui SetCore "PromptBlockPlayer"). This always works on any client.
local USE_PROMPT_FALLBACK = true
-- When that native prompt is used, auto-confirm it so the block still happens with no
-- manual tap. It first tries firing the confirm button's handlers, then (the reliable
-- path) sends a real mouse click on the button via VirtualInputManager, because the
-- confirm handler is a CoreScript connection an executor usually can't fire directly.
local AUTO_ACCEPT_PROMPT  = true
local USE_VIRTUAL_CLICK   = true   -- allow the real-mouse-click confirm (needs VirtualInputManager)

local NOTIFY          = true   -- show Roblox toast notifications for what it's doing
local STATE_FILE      = "dely_autoblocker.json" -- remembers total block count (executor fs)

-- Only used if HOP_AFTER_BLOCK + AUTO_CHAIN are on: raw url this script is hosted at.
local SELF_URL        = ""
--// ================================================================

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local StarterGui      = game:GetService("StarterGui")
local HttpService     = game:GetService("HttpService")
local CoreGui         = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

pcall(function()
	math.randomseed(os.clock() * 1e6 + (os.time() or 0) + #tostring(game.JobId))
end)

-- Clean up a previous run (re-inject safe): drop old connections so we don't stack.
if _G.__AutoBlockerCleanup then
	pcall(_G.__AutoBlockerCleanup)
end
local connections: { RBXScriptConnection } = {}
_G.__AutoBlockerCleanup = function()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
end

--// ---------------------------- helpers ----------------------------

local function notify(title: string, text: string, duration: number?)
	if not NOTIFY then return end
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = duration or 4,
		})
	end)
end

-- Executor filesystem is optional; everything degrades to in-memory if it's missing.
local hasFS = (typeof(writefile) == "function")
	and (typeof(readfile) == "function")
	and (typeof(isfile) == "function")

local state = { visited = {}, blocks = 0 }

local function loadState()
	if not hasFS then return end
	pcall(function()
		if isfile(STATE_FILE) then
			local decoded = HttpService:JSONDecode(readfile(STATE_FILE))
			if type(decoded) == "table" then
				state.visited = (type(decoded.visited) == "table") and decoded.visited or {}
				state.blocks = tonumber(decoded.blocks) or 0
			end
		end
	end)
end

local function saveState()
	if not hasFS then return end
	pcall(function()
		writefile(STATE_FILE, HttpService:JSONEncode(state))
	end)
end

-- Try the common executor HTTP entry points, in order.
local function httpGet(url: string): string?
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if ok and type(res) == "string" then return res end
	ok, res = pcall(function() return game:HttpGetAsync(url) end)
	if ok and type(res) == "string" then return res end
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if type(req) == "function" then
		local ok2, resp = pcall(req, { Url = url, Method = "GET" })
		if ok2 and type(resp) == "table" and resp.Body then return resp.Body end
	end
	return nil
end

--// ------------------------ blocking utility ------------------------

-- Newer Roblox clients no longer keep a standalone "BlockingUtility" ModuleScript at a
-- fixed path (that's why a fixed lookup fails), so we find the blocker by BEHAVIOUR
-- across several strategies and cache whatever we get.
local cachedBlocker = nil

local function tryRequire(inst: Instance)
	if not (inst and inst:IsA("ModuleScript")) then return nil end
	local ok, mod = pcall(require, inst)
	if ok and type(mod) == "table" then return mod end
	return nil
end

local function hasBlockMethod(mod): boolean
	if type(mod) ~= "table" then return false end
	-- rawget never triggers a metatable __index, so modules whose __index THROWS on an
	-- unknown key (e.g. CameraShakePresets) can't blow up the scan. Covers the common
	-- case where BlockPlayerAsync is a direct key on the returned table.
	local ok, fn = pcall(rawget, mod, "BlockPlayerAsync")
	if ok and type(fn) == "function" then return true end
	-- Guarded normal index too, for modules that expose methods via __index (OOP).
	ok, fn = pcall(function() return mod.BlockPlayerAsync end)
	return ok and type(fn) == "function"
end

-- The block module only ever lives in Roblox's own containers, never in game code.
-- Restricting the scan to these keeps us from requiring/indexing game modules (which
-- may throw from their __index, e.g. a GUI accessor or CameraShakePresets).
local corePackages = game:FindService("CorePackages")
local function isCoreModule(m: Instance): boolean
	if not (m and m:IsA("ModuleScript")) then return false end
	local ok, inCore = pcall(function()
		return m:IsDescendantOf(CoreGui) or (corePackages ~= nil and m:IsDescendantOf(corePackages))
	end)
	return ok and inCore
end

local function findBlockModule()
	if cachedBlocker then return cachedBlocker end

	-- 1) Version-independent: scan Roblox's OWN loaded modules for one that exposes
	--    BlockPlayerAsync. This survives Roblox moving/renaming the internal paths,
	--    and skips game code so a game module's throwing __index can't break us.
	if type(getloadedmodules) == "function" then
		local ok, mods = pcall(getloadedmodules)
		if ok and type(mods) == "table" then
			for _, m in ipairs(mods) do
				if isCoreModule(m) then
					local mod = tryRequire(m)
					if hasBlockMethod(mod) then
						cachedBlocker = mod
						return mod
					end
				end
			end
		end
	end

	-- 2) Known standalone BlockingUtility ModuleScript locations.
	local paths = {
		{ "RobloxGui", "Modules", "PlayerList", "BlockingUtility" },
		{ "RobloxGui", "Modules", "Common", "BlockingUtility" },
		{ "RobloxGui", "Modules", "BlockingUtility" },
		{ "RobloxGui", "Modules", "Settings", "Resources", "BlockingUtility" },
	}
	for _, path in ipairs(paths) do
		local node: Instance? = CoreGui
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		local mod = node and tryRequire(node)
		if hasBlockMethod(mod) then
			cachedBlocker = mod
			return mod
		end
	end

	-- 3) A PlayerDropDown module that can *create* a blocking utility for us.
	local rg = CoreGui:FindFirstChild("RobloxGui")
	local modules = rg and rg:FindFirstChild("Modules")
	if modules then
		for _, name in ipairs({ "PlayerDropDown", "PlayerDropDownModule" }) do
			local mod = tryRequire(modules:FindFirstChild(name))
			if mod and type(mod.CreateBlockingUtility) == "function" then
				local ok, bu = pcall(function() return mod:CreateBlockingUtility() end)
				if ok and hasBlockMethod(bu) then
					cachedBlocker = bu
					return bu
				end
			end
		end
	end

	-- 4) Last resort: descendant search for anything named BlockingUtility.
	for _, d in ipairs(CoreGui:GetDescendants()) do
		if d:IsA("ModuleScript") and d.Name == "BlockingUtility" then
			local mod = tryRequire(d)
			if hasBlockMethod(mod) then
				cachedBlocker = mod
				return mod
			end
		end
	end

	return nil
end

local function isAlreadyBlocked(blockUtil, userId: number): boolean
	local blocked = false
	pcall(function()
		if blockUtil and type(blockUtil.IsPlayerBlockedByUserId) == "function" then
			blocked = blockUtil:IsPlayerBlockedByUserId(userId) and true or false
		end
	end)
	return blocked
end

local hasFireSignal = type((getgenv and getgenv().firesignal) or firesignal) == "function"
local fireSignalFn = (getgenv and getgenv().firesignal) or firesignal
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)
if not VirtualInputManager then
	pcall(function() VirtualInputManager = game:FindService("VirtualInputManager") end)
end
local GuiService = game:GetService("GuiService")
local canVirtualClick = USE_VIRTUAL_CLICK and VirtualInputManager ~= nil
local canFireHandlers = (type(getconnections) == "function") or hasFireSignal
local canAutoAccept = canFireHandlers or canVirtualClick

-- Fire a button's click handlers directly, no real cursor click needed. We do NOT hide
-- anything: when the real handler runs it blocks AND closes its own dialog. Returns true
-- if we managed to fire something.
local function fireButton(btn: Instance): boolean
	local fired = false
	local signals = {}
	pcall(function() table.insert(signals, (btn :: any).Activated) end)
	pcall(function() table.insert(signals, (btn :: any).MouseButton1Click) end)
	pcall(function() table.insert(signals, (btn :: any).MouseButton1Down) end)
	pcall(function() table.insert(signals, (btn :: any).MouseButton1Up) end)

	if type(getconnections) == "function" then
		for _, sig in ipairs(signals) do
			local ok, conns = pcall(getconnections, sig)
			if ok and type(conns) == "table" then
				for _, c in ipairs(conns) do
					pcall(function() if c.Enabled == false and c.Enable then c:Enable() end end)
					pcall(function() if c.Fire then c:Fire() end end)
					pcall(function() if c.Function then task.spawn(c.Function) end end)
					fired = true
				end
			end
		end
	end
	if not fired and hasFireSignal then
		for _, sig in ipairs(signals) do
			if pcall(fireSignalFn, sig) then fired = true end
		end
	end
	return fired
end

local function looksLikeConfirm(btn: Instance): boolean
	local name = btn.Name:lower()
	if name:find("cancel") or name:find("close") or name:find("report") or name:find("dismiss") then
		return false
	end
	local text = ""
	pcall(function() text = tostring((btn :: any).Text or ""):lower() end)
	if text:find("cancel") or text:find("close") or text:find("report") then return false end
	return text == "block"
		or text:find("block") ~= nil
		or text == "confirm"
		or text == "yes"
		or text == "ok"
		or name:find("confirm") ~= nil
		or name:find("block") ~= nil
		or name:find("accept") ~= nil
		or name == "primarybutton"
end

-- The confirm button in the native block dialog, if it's currently on screen.
local function findConfirmButton(): Instance?
	for _, d in ipairs(CoreGui:GetDescendants()) do
		if d:IsA("TextButton") or d:IsA("ImageButton") then
			local visible = true
			pcall(function() visible = (d :: any).Visible and (d :: any).AbsoluteSize.Y > 0 end)
			if visible and looksLikeConfirm(d) then
				return d
			end
		end
	end
	return nil
end

-- Send a real left-click at a GUI element's centre. The confirm handler is a CoreScript
-- connection an executor can't fire directly, so we drive the genuine input path instead.
local function virtualClick(btn: Instance, yOffset: number): boolean
	if not VirtualInputManager then return false end
	return (pcall(function()
		local pos = (btn :: any).AbsolutePosition
		local size = (btn :: any).AbsoluteSize
		local x = pos.X + size.X / 2
		local y = pos.Y + size.Y / 2 + yOffset
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.03)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end))
end

-- After the native prompt fires, confirm it. Never force-hides: a successful confirm makes
-- Roblox close its own dialog; if we can't confirm, the dialog stays so you can tap it.
local function autoAcceptPrompt()
	if not AUTO_ACCEPT_PROMPT or not canAutoAccept then return end
	task.spawn(function()
		-- Wait for the confirm button to actually appear.
		local btn
		local appear = os.clock() + 5
		repeat
			btn = findConfirmButton()
			if btn then break end
			task.wait(0.05)
		until os.clock() > appear
		if not btn then return end

		-- 1) Try firing the handler connections (works on some executors).
		if canFireHandlers then
			fireButton(btn)
			task.wait(0.3)
			if not findConfirmButton() then return end
		end

		-- 2) Real mouse click. AbsolutePosition may or may not include the top-bar inset,
		--    so try centre, then +inset, then -inset, stopping as soon as the dialog closes.
		if canVirtualClick then
			local inset = 36
			pcall(function() inset = GuiService:GetGuiInset().Y end)
			for _, yoff in ipairs({ 0, inset, -inset }) do
				local target = findConfirmButton()
				if not target then return end
				virtualClick(target, yoff)
				task.wait(0.35)
				if not findConfirmButton() then return end
			end
		end
	end)
end

-- Native block prompt: always registered by the CoreScripts, works on any client. Early
-- (auto-execute) it can throw "not registered by CoreScripts" until they load, so retry.
local function promptBlock(target: Player): boolean
	local ok = false
	local deadline = os.clock() + 10
	repeat
		ok = pcall(function()
			StarterGui:SetCore("PromptBlockPlayer", target)
		end)
		if ok then break end
		task.wait(0.5)
	until os.clock() > deadline
	if ok then autoAcceptPrompt() end
	return ok
end

-- Returns "silent", "prompt", or nil.
local function doBlock(target: Player): string?
	local blockUtil = findBlockModule()
	if blockUtil then
		-- Prefer the Player-instance signature; fall back to the userId one.
		local ok = pcall(function() blockUtil:BlockPlayerAsync(target) end)
		if not ok then
			ok = pcall(function() blockUtil:BlockPlayerAsync(target.UserId) end)
		end
		if ok then return "silent" end
	end
	if USE_PROMPT_FALLBACK and promptBlock(target) then
		return "prompt"
	end
	return nil
end

--// ------------------------ friend check ------------------------

-- Returns true if we must NOT block this player. Fail-safe: if we can't tell whether
-- they're a friend, we say "yes, avoid" so a friend is never blocked by accident.
local function shouldAvoid(target: Player): boolean
	if not AVOID_FRIENDS then return false end
	local friend = true
	local ok, result = pcall(function()
		return LocalPlayer:IsFriendsWith(target.UserId)
	end)
	if ok then
		friend = result and true or false
	end
	return friend
end

--// ------------------------ pick + block ------------------------

local function pickTarget(): Player?
	local blockUtil = findBlockModule() -- may be nil; only used to skip already-blocked players
	local candidates = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(candidates, p)
		end
	end
	-- Fisher-Yates shuffle so the random pick is unbiased.
	for i = #candidates, 2, -1 do
		local j = math.random(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	-- First candidate that is not a friend and not already blocked wins. Checking one
	-- at a time keeps the (yielding, web-backed) friend check to a minimum.
	for _, p in ipairs(candidates) do
		if not shouldAvoid(p) and not isAlreadyBlocked(blockUtil, p.UserId) then
			return p
		end
	end
	return nil
end

local debugReport: () -> () -- forward declaration; defined below

local function blockRandom(): boolean
	if MAX_BLOCKS > 0 and state.blocks >= MAX_BLOCKS then
		notify("Auto Blocker", ("Block limit reached (%d). Skipping block."):format(MAX_BLOCKS))
		return false
	end

	local target = pickTarget()
	if not target then
		notify("Auto Blocker", "No blockable non-friend here - skipping.")
		return false
	end

	local method = doBlock(target)
	if method == "silent" then
		state.blocks += 1
		saveState()
		notify("Auto Blocker", ("Blocked %s  (total %d)"):format(target.Name, state.blocks))
		return true
	elseif method == "prompt" then
		-- Native prompt path. If we can auto-fire the confirm, the dialog closes itself
		-- (blocked, no tap). Otherwise you'll see the dialog to tap once.
		state.blocks += 1
		saveState()
		local canHide = AUTO_ACCEPT_PROMPT and canAutoAccept
		notify("Auto Blocker", canHide
			and ("Blocking %s..."):format(target.Name)
			or ("Tap Block to block %s"):format(target.Name), 5)
		-- Print what's available so we can see why it's on the prompt path.
		pcall(debugReport)
		return true
	end

	notify("Auto Blocker", ("Couldn't block %s (no block method on this client)."):format(target.Name), 6)
	pcall(debugReport)
	return false
end

-- Prints what's available on this client so you can tell what the executor supports.
function debugReport()
	local function line(s) print("[AutoBlocker] " .. s) end
	line("---- diagnostics ----")
	line("getloadedmodules: " .. tostring(type(getloadedmodules) == "function"))
	if type(getloadedmodules) == "function" then
		local ok, mods = pcall(getloadedmodules)
		local total, core, withBlock = 0, 0, 0
		if ok and type(mods) == "table" then
			for _, m in ipairs(mods) do
				total += 1
				if isCoreModule(m) then
					core += 1
					if hasBlockMethod(tryRequire(m)) then withBlock += 1 end
				end
			end
		end
		line(("loaded modules: %d  (core: %d, with BlockPlayerAsync: %d)"):format(total, core, withBlock))
	end
	local rg = CoreGui:FindFirstChild("RobloxGui")
	line("RobloxGui present: " .. tostring(rg ~= nil))
	line("RobloxGui.Modules present: " .. tostring(rg and rg:FindFirstChild("Modules") ~= nil))
	line("silent block module found: " .. tostring(findBlockModule() ~= nil))
	line("prompt fallback enabled: " .. tostring(USE_PROMPT_FALLBACK))
	line("getconnections: " .. tostring(type(getconnections) == "function"))
	line("firesignal: " .. tostring(hasFireSignal))
	line("VirtualInputManager: " .. tostring(VirtualInputManager ~= nil))
	line("virtual-click enabled: " .. tostring(canVirtualClick))
	line("can auto-accept prompt: " .. tostring(canAutoAccept))
	line("total blocks recorded: " .. tostring(state.blocks))
	line("---------------------")
end

--// ------------------------ server hop ------------------------

-- Queue this exact script to run again after the teleport, so hops chain by themselves.
local function queueSelf()
	if not AUTO_CHAIN or SELF_URL == "" then return end
	local q = queue_on_teleport
		or queueonteleport
		or (syn and syn.queue_on_teleport)
		or (fluxus and fluxus.queue_on_teleport)
	if type(q) ~= "function" then return end
	pcall(q, ('loadstring(game:HttpGet(%q))()'):format(SELF_URL))
end

-- Collect unvisited public servers (with room), then pick one at random.
local function findFreshServer(): string?
	local placeId = game.PlaceId
	local currentJob = game.JobId
	local pool = {}
	local cursor = ""

	for _ = 1, 6 do
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
		if cursor ~= "" then
			url = url .. "&cursor=" .. cursor
		end
		local body = httpGet(url)
		if not body then break end

		local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
		if not ok or type(data) ~= "table" or type(data.data) ~= "table" then break end

		for _, s in ipairs(data.data) do
			local id = s.id
			local playing = tonumber(s.playing) or 0
			local maxPlayers = tonumber(s.maxPlayers) or 0
			if type(id) == "string"
				and id ~= currentJob
				and not state.visited[id]
				and playing < maxPlayers then
				table.insert(pool, id)
			end
		end

		if #pool >= 40 then break end
		cursor = data.nextPageCursor
		if type(cursor) ~= "string" or cursor == "" then break end
	end

	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

local function serverHop()
	local placeId = game.PlaceId
	local currentJob = game.JobId

	local target = findFreshServer()

	if not target then
		-- Everything's been visited (or we can't list servers). Reset the memory so we
		-- don't get stuck, then fall back to fresh matchmaking on the same place.
		state.visited = {}
		if currentJob ~= "" then state.visited[currentJob] = true end
		saveState()
		notify("Auto Blocker", "No fresh server found - reshuffling via matchmaking.")
		queueSelf()
		pcall(function() TeleportService:Teleport(placeId, LocalPlayer) end)
		return
	end

	state.visited[target] = true
	saveState()
	queueSelf()
	notify("Auto Blocker", "Hopping to a fresh server...")
	pcall(function() TeleportService:TeleportToPlaceInstance(placeId, target, LocalPlayer) end)
end

--// ------------------------ readiness (for auto-execute) ------------------------

-- Auto-execute injects before the client is ready. Wait for the game to load and for
-- LocalPlayer to exist (reassigning the upvalue every function shares), so friend checks
-- and the block prompt actually work.
local function waitUntilReady(): boolean
	if not game:IsLoaded() then
		pcall(function() game.Loaded:Wait() end)
	end
	local deadline = os.clock() + READY_TIMEOUT
	while not Players.LocalPlayer and os.clock() < deadline do
		task.wait(0.1)
	end
	LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then return false end
	pcall(function() LocalPlayer:WaitForChild("PlayerGui", 10) end)
	return true
end

-- Wait until there's at least one other player to block (they stream in after you join).
local function waitForOtherPlayers(timeout: number): boolean
	local deadline = os.clock() + timeout
	repeat
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then return true end
		end
		task.wait(0.25)
	until os.clock() > deadline
	return false
end

--// ------------------------ main ------------------------

loadState()
if game.JobId ~= "" then
	state.visited[game.JobId] = true
	saveState()
end

-- Manual controls, in case you want to fire a block / hop yourself.
_G.AutoBlocker = {
	blockNow = function() task.spawn(blockRandom) end,
	hop = function() task.spawn(serverHop) end,
	blockAndHop = function()
		task.spawn(function()
			blockRandom()
			task.wait(HOP_DELAY)
			serverHop()
		end)
	end,
	debug = debugReport,
	state = state,
}

task.spawn(function()
	if not waitUntilReady() then
		notify("Auto Blocker", "Gave up waiting for the game to load.")
		return
	end
	if BLOCK_ON_JOIN then
		if BLOCK_DELAY > 0 then task.wait(BLOCK_DELAY) end
		waitForOtherPlayers(PLAYER_TIMEOUT)
		blockRandom()
	end
	if HOP_AFTER_BLOCK then
		task.wait(HOP_DELAY)
		serverHop()
	end
end)
