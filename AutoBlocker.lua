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
local BLOCK_ON_JOIN   = true   -- block one random non-friend each time the script starts
local HOP_AFTER_BLOCK = true   -- after blocking, teleport to a fresh server automatically
local AVOID_FRIENDS   = true   -- never block friends (leave this on)
local AUTO_CHAIN      = true   -- re-run this script automatically after each hop (needs SELF_URL + queue_on_teleport)

local BLOCK_DELAY     = 2.0    -- seconds to wait after joining (let players load) before blocking
local HOP_DELAY       = 1.5    -- seconds to wait after blocking before hopping
local MAX_BLOCKS      = 0      -- stop blocking after this many total blocks (0 = no limit); hopping continues

local NOTIFY          = true   -- show Roblox toast notifications for what it's doing
local STATE_FILE      = "dely_autoblocker.json" -- remembers visited servers + total block count (executor fs)

-- To auto-chain across hops, put the RAW url this script is hosted at here (e.g. a
-- raw GitHub link ending in AutoBlocker.lua). Leave "" to disable auto-chain - the
-- script still blocks + hops once per run; use your executor's auto-execute to repeat.
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

-- The BlockingUtility ModuleScript has lived at a few paths across Roblox versions,
-- so try the known ones and then fall back to a descendant search.
local function getBlockingUtility()
	local candidates = {
		{ "RobloxGui", "Modules", "PlayerList", "BlockingUtility" },
		{ "RobloxGui", "Modules", "Common", "BlockingUtility" },
		{ "RobloxGui", "Modules", "Settings", "Resources", "BlockingUtility" },
	}
	for _, path in ipairs(candidates) do
		local node: Instance? = CoreGui
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		if node and node:IsA("ModuleScript") then
			local ok, mod = pcall(require, node)
			if ok and type(mod) == "table" then return mod end
		end
	end
	for _, d in ipairs(CoreGui:GetDescendants()) do
		if d:IsA("ModuleScript") and d.Name == "BlockingUtility" then
			local ok, mod = pcall(require, d)
			if ok and type(mod) == "table" then return mod end
		end
	end
	return nil
end

local function isAlreadyBlocked(blockUtil, userId: number): boolean
	local blocked = false
	pcall(function()
		if type(blockUtil.IsPlayerBlockedByUserId) == "function" then
			blocked = blockUtil:IsPlayerBlockedByUserId(userId) and true or false
		end
	end)
	return blocked
end

local function doBlock(blockUtil, target: Player): boolean
	-- Prefer the Player-instance signature; fall back to the userId one.
	local ok = pcall(function() blockUtil:BlockPlayerAsync(target) end)
	if not ok then
		ok = pcall(function() blockUtil:BlockPlayerAsync(target.UserId) end)
	end
	return ok
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

local function pickTarget(blockUtil): Player?
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

local function blockRandom(): boolean
	if MAX_BLOCKS > 0 and state.blocks >= MAX_BLOCKS then
		notify("Auto Blocker", ("Block limit reached (%d). Skipping block."):format(MAX_BLOCKS))
		return false
	end

	local blockUtil = getBlockingUtility()
	if not blockUtil then
		notify("Auto Blocker", "Couldn't find the block module (not an executor?).")
		return false
	end

	local target = pickTarget(blockUtil)
	if not target then
		notify("Auto Blocker", "No blockable non-friend here - skipping.")
		return false
	end

	if doBlock(blockUtil, target) then
		state.blocks += 1
		saveState()
		notify("Auto Blocker", ("Blocked %s  (total %d)"):format(target.Name, state.blocks))
		return true
	end

	notify("Auto Blocker", ("Failed to block %s."):format(target.Name))
	return false
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
	state = state,
}

task.spawn(function()
	if BLOCK_ON_JOIN then
		task.wait(BLOCK_DELAY)
		blockRandom()
	end
	if HOP_AFTER_BLOCK then
		task.wait(HOP_DELAY)
		serverHop()
	end
end)
