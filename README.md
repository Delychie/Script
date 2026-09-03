# Dely Booster Test 67

A LocalScript speed booster for Roblox with a Minecraft **redstone**-themed
panel - a deepslate slab with pixel bevels, a lever toggle, and a redstone-dust
border that powers on (glows red) only while the booster is enabled.

## Install

Put `SpeedBooster.lua` in **StarterPlayer > StarterPlayerScripts** as a `LocalScript`
(or run it from any client-side script runner).

## Panel

The panel is a small hub: a title bar up top (redstone dust + `DELY BOOSTER TEST 67`)
and three tabs below it that swap the content pane with a little pop animation:

- **MOVE** - Normal Speed, Carry Speed, Enable (lever), Inf Jump.
- **AUTO** - Auto Left / Auto Right buttons, Auto Grab.
- **PLAYER** - Anti Die, Anti AFK, Speed Counter, Instant Reset.
- **MISC** - FPS Unlock, Rejoin Server, Discord Tag, and the link.

- **Normal Speed box** - speed used when you're not carrying anything.
- **Carry Speed box** - speed used while carrying a brainrot.
- Both clamped to 0–1000; type a number and press Enter.
- **Lever** - flip it to toggle the boost; the lamp, knob and border light up
  red ("powered").
- **Auto Left / Auto Right** - two big side-by-side buttons that walk the fixed
  base waypoints (`AP_L1/AP_L2`, `AP_R1/AP_R2`) and switch off when the route
  finishes. They drive the same `LinearVelocity` plane mover as the boost instead
  of writing `AssemblyLinearVelocity`, so they don't trip the same detection. Only
  one runs at a time; the active side lights crimson.
- **Auto Grab** - half-autograb steal loop. Finds the nearest "Steal" prompt on
  another base within reach, grabs the prompt's own hold/trigger connections
  (`getconnections`) and fires them, so the steal goes through the game's normal
  path. Executor-only. Turning it on slides a **steal bar** up from the bottom of
  the screen (Back-eased appear animation); the bar fills crimson to scarlet as a
  steal holds and flashes "STOLEN" when it lands, then hides when you switch Auto
  Grab off.
- **Inf Jump** - jump again any time you press jump, even mid-air. It uses the
  same `LinearVelocity` idea as the boost: a Line-mode constraint pinned to the
  world Y axis that pulses an upward `LineVelocity` for a split second on each
  `JumpRequest`, instead of `Humanoid:ChangeState` or writing
  `AssemblyLinearVelocity`, so it doesn't trip the same detection. Works on
  keyboard (Space) and the mobile jump button.
- **Anti Die** - keeps your own character alive: tops your `Humanoid.Health` back
  to `MaxHealth` each frame, disables the `Dead` humanoid state and leaves your
  joints intact (`BreakJointsOnDeath = false`) while it's on. Reapplies itself on
  respawn, and the setting persists across rejoins. Only touches your own
  character.
- **Instant Reset** - a flat full-width button that fires the game's `RE/...`
  reset remote (captured by hooking `FireServer`) with the reset GUID, spamming
  until you die. Executor-only.
- **Anti AFK** - keeps you from getting kicked for idling. On `Player.Idled` it
  nudges the camera through `VirtualUser`, same as the del hub anti-afk. Affects
  only your own session.
- **FPS Unlock** - raises your client frame-rate cap via `setfpscap` (executor
  function) while on, back to 60 when off.
- **Rejoin Server** - a flat button that teleports you back into the same server
  instance (`TeleportService:TeleportToPlaceInstance`) for a clean reset.
- **Speed Counter** - a Minecraft-style slide switch (stone track + redstone-block
  knob that lights up and slides right when on). Turns the head readout on/off,
  independent of the boost.
- The active speed row's label lights red so you can see the live mode.
- The panel is draggable, and its position is remembered.
- **Toggle button** - a small draggable redstone button floats at the top of the
  screen; tap it to hide or show the whole panel (it scales/springs in and out),
  drag it to move it. Same idea as the del hub open/close button.

## Mobile + PC

Works with both touch and mouse (buttons/toggles use `Activated`, dragging
handles `Touch`). The panel auto-sizes: a touch nudge bigger on phones
(`IS_MOBILE`), normal on PC, and clamped down to fit small screens - driven by a
single `panelScale` `UIScale` that also re-fits on rotation / window resize.
Every button also plays a click sound on press.

## Performance

The cosmetic loops are light and idle-aware: when the boost is off and nothing
is animating, the border/dust loop applies its off-state once and then does
nothing each frame. The head-counter number is only rewritten when it changes,
and the "float above other head text" scan runs a few times a second, not every
frame.

## Auto-save

Settings persist across rejoins automatically (executor filesystem - needs
`writefile`/`readfile`/`isfile`; silently no-ops without them). Whenever you
change a value it writes `dely_booster_test67.json`, and on load it applies the
saved **normal speed, carry speed, boost on/off, speed-counter on/off, anti-die
on/off, inf-jump on/off, anti-afk on/off, fps-unlock on/off, discord-tag on/off,
and panel position**. No save button - it just remembers.

The look uses `Enum.Font.Arcade` (the closest built-in to Minecraftia) with
rounded corners (`UICorner`) throughout and soft edge strokes - light rims on
raised pieces, dark rims on the slots for depth. The title sits inside the dark
panel body just below the red accent line. Swap in a
real Minecraftia font asset later if you want it pixel-perfect.

### Custom images

The panel uses uploaded Minecraft textures, set at the top of the script:

- `LEVER_ON_IMAGE` - lever **up** (enabled)
- `LEVER_OFF_IMAGE` - lever **down** (disabled)
- `DUST_IMAGE` - redstone-dust indicator in the header; it's tinted every frame,
  so it sits dim red when off and pulses bright red while the booster is powered.

Blank out `LEVER_ON_IMAGE` to fall back to the drawn (native) lever.

## Animations

All spring/`Back`-eased for a clean, snappy feel:

- **Panel** grows in on load; the **redstone dust** and the **lever** then do a
  smooth damped shake as it powers up (the panel itself no longer rotates).
- **Border** is a `UIStroke` that overflows the panel edge. Off, it's a still
  **reddish-black**. When you power on, the gradient (reddish-black → crimson →
  red → scarlet, endpoints matched) **whirls in fast and fades up**, then eases
  into a steady flow around the border, breathing slightly.
- **Lever** does a squash-and-pop snap when it flips.
- **Switch-on** also flashes the dust bright for a moment, plus a tiny panel
  "thunk".
- **Speed slots** pop and warm up when focused; the live slot pops on every
  pick-up / drop.
- **Rows** lighten on hover.

## Normal vs Carry speed

The mover picks a speed automatically based on whether you're holding a
brainrot:

- `isCarryingBrainrot()` returns `true` when the player's `Stealing` attribute
  is set, or when `Humanoid.WalkSpeed` drops below `CARRY_WALKSPEED_MAX` (25)
  while still above 0 - which is how the game marks the carry state.
- Each frame the loop detects pick-up / drop transitions, flips between
  `getNormalSpeed()` and `getCarrySpeed()`, and lights the active speed row's
  label. No input from you is needed - walk into a steal and it switches, drop
  it and it switches back.

## Discord tag (head)

The **Discord Tag** toggle (MISC tab, on by default) puts a `discord.gg/delhub`
`BillboardGui` above your head. It uses the same overlay scan as the speed
counter but with top priority: it parks itself above every other head tag
(nametags **and** the speed counter), so it always sits on top. The counter's
own scan ignores the discord tag, which keeps the stack stable (nametags <
speed counter < discord tag) instead of the two leapfrogging each other. It's
client-side, so only you see it. The setting persists across rejoins.

## Head counter (Speed Counter toggle)

Toggle the **Speed Counter** switch and a `BillboardGui` floats above your head
showing your real horizontal speed in studs/sec - measured from
`HumanoidRootPart.AssemblyLinearVelocity` with the Y component dropped, so
falling never inflates it. It's independent of the boost, uses the Arcade font,
and is client-side so no other player sees it.

- **Color logic (del-hub style):** the number sits white, and on a sharp
  acceleration it punches bigger and flashes - bright red on a big spike
  (Δ > 18), light red on a smaller one (Δ > 6) - then eases back to white.
- **Overlay:** it scans your character for any other `BillboardGui` (nametags,
  other speed counters, custom text) and parks itself just above the highest one
  (re-checked ~3×/sec), with `AlwaysOnTop` so it renders over them. If nothing
  else is up there it sits at `COUNTER_BASE_Y` (2.6 studs).

## How it moves the character

No `HumanoidRootPart.Velocity` writes anywhere.

1. An `Attachment` is created on the `HumanoidRootPart`.
2. A `LinearVelocity` is bound to it with `VelocityConstraintMode = Plane`,
   `PrimaryTangentAxis = (1, 0, 0)` and `SecondaryTangentAxis = (0, 0, 1)` -
   the world XZ plane. A plane constraint only solves inside its own plane, so
   the Y axis never receives force and gravity, jumping and falling are unaffected.
3. Each `Heartbeat`, `Humanoid.MoveDirection` is read and written to the
   constraint as:

   ```lua
   local spd = getActiveSpeed() -- Carry Speed while carrying, else Normal Speed
   velocity.PlaneVelocity = Vector2.new(moveDirection.X * spd, moveDirection.Z * spd)
   ```

4. When `MoveDirection` is zero (no input), the constraint is disabled so the
   Humanoid stops normally and outside forces still apply. It re-enables the
   moment there is input again.

The mover is rebuilt on every respawn via `CharacterAdded`, and the panel
survives respawns (`ResetOnSpawn = false`).

---

# Auto Blocker (server hop)

`AutoBlocker.lua` is a separate client-side script for people who keep getting
matched back into the **same server** when they hop. Every time you join a server it
blocks **one random player who is not your friend**, then (optionally) teleports you
into a fresh server you haven't visited yet. Roblox matchmaking avoids putting you in
servers full of people you've blocked, so a growing block list is what actually breaks
the "same server again" loop.

**Friends are never blocked.** If the friend check for a candidate can't complete for
any reason, that candidate is skipped, so a friend can't be blocked by accident.
Blocking is a normal Roblox feature - the other person isn't notified or reported and
nothing happens to their account; you just stop seeing and being matched with them.
Nothing targets a specific person; the pick is random.

## Install

Run `AutoBlocker.lua` from a client-side script runner (executor). It uses executor
functions for the server-list fetch, the "remember visited servers" file, and
auto-chaining across hops; each of those degrades gracefully (no-op) when the
function isn't available.

## What it does on each run

1. Waits `BLOCK_DELAY` seconds for players to load.
2. Picks a random player who is **not you, not a friend, and not already blocked**, and
   blocks them. Newer Roblox clients no longer keep a `BlockingUtility` module at a
   fixed path, so the blocker is found by behaviour: it scans Roblox's own loaded
   modules (`getloadedmodules`, restricted to `CoreGui`/`CorePackages` so game code is
   never touched) for one exposing `BlockPlayerAsync`, then tries the known
   `BlockingUtility` paths, then a `PlayerDropDown:CreateBlockingUtility()`, then a
   descendant search. If none exist on your client it falls back to the native block
   prompt (`SetCore "PromptBlockPlayer"`), which always works but needs one tap.
3. If `HOP_AFTER_BLOCK` is on, lists the game's public servers, drops the ones you've
   already visited and the full ones, and `TeleportToPlaceInstance`s you into a random
   remaining one. Visited server ids are remembered in `dely_autoblocker.json` so it
   keeps finding new ones. If it runs out (or can't list servers) it clears the memory
   and falls back to normal matchmaking (`TeleportService:Teleport`).

## Config (top of the file)

- `BLOCK_ON_JOIN` - block a random non-friend when the script starts (default on).
- `HOP_AFTER_BLOCK` - server-hop after blocking (default on). Turn off if you hop
  yourself and only want the blocker.
- `AVOID_FRIENDS` - never block friends (leave on).
- `AUTO_CHAIN` + `SELF_URL` - to make hops chain by themselves, set `SELF_URL` to the
  raw URL you host this script at; the script `queue_on_teleport`s a loader so it
  re-runs on arrival. Left blank, it still blocks + hops once per run - use your
  executor's auto-execute to repeat.
- `BLOCK_DELAY` / `HOP_DELAY` - timing before blocking / before hopping.
- `MAX_BLOCKS` - stop blocking after N total (0 = unlimited); hopping still continues.
- `USE_PROMPT_FALLBACK` - if no silent block module is found, use the native block
  prompt (one tap). Turn off to only ever block silently.
- `NOTIFY` - Roblox toast notifications for each action.
- `STATE_FILE` - the file used to remember visited servers + total block count.

## Manual controls

While it's loaded, `_G.AutoBlocker` exposes `blockNow()`, `hop()`, `blockAndHop()`, and
`debug()`. Run `_G.AutoBlocker.debug()` to print (to the console) exactly what blocking
methods your executor/client exposes - handy if a block ever fails to land.
