# Dely Booster Test 67

A LocalScript speed booster for Roblox with a Minecraft **redstone**-themed
panel - a deepslate slab with pixel bevels, a lever toggle, and a redstone-dust
border that powers on (glows red) only while the booster is enabled.

## Install

Put `SpeedBooster.lua` in **StarterPlayer > StarterPlayerScripts** as a `LocalScript`
(or run it from any client-side script runner).

## Panel

- **Normal Speed box** - speed used when you're not carrying anything.
- **Carry Speed box** - speed used while carrying a brainrot.
- Both clamped to 0–1000; type a number and press Enter.
- **Lever** - flip it to toggle the boost; the lamp, knob and border light up
  red ("powered").
- **Auto Left / Auto Right** - walk the two fixed base waypoints (`AP_L1/AP_L2`,
  `AP_R1/AP_R2`) and flip off when the route finishes. They drive the same
  `LinearVelocity` plane mover as the boost instead of writing
  `AssemblyLinearVelocity`, so they don't trip the same detection. Only one runs
  at a time.
- **Speed Counter** - a Minecraft-style slide switch (stone track + redstone-block
  knob that lights up and slides right when on). Turns the head readout on/off,
  independent of the boost.
- The active speed row's label lights red so you can see the live mode.
- The panel is draggable, and its position is remembered.

## Mobile + PC

Works with both touch and mouse (toggles use `Activated`, dragging handles
`Touch`). The panel auto-sizes: ~30% bigger and more tappable on phones
(`IS_MOBILE`), normal on PC, and clamped down to fit small screens - driven by a
single `panelScale` `UIScale` that also re-fits on rotation / window resize.

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
saved **normal speed, carry speed, boost on/off, speed-counter on/off, and panel
position**. No save button - it just remembers.

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
