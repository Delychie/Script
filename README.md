# Dely Booster Test 67

A LocalScript speed booster for Roblox with a Minecraft **redstone**-themed
panel — a deepslate slab with pixel bevels, a lever toggle, and a redstone-dust
border that powers on (glows red) only while the booster is enabled.

## Install

Put `SpeedBooster.lua` in **StarterPlayer > StarterPlayerScripts** as a `LocalScript`
(or run it from any client-side script runner).

## Panel

- **Normal Speed box** — speed used when you're not carrying anything.
- **Carry Speed box** — speed used while carrying a brainrot.
- Both clamped to 0–1000; type a number and press Enter.
- **Lever** — flip it to toggle the boost; the lamp, knob and border light up
  red ("powered").
- **Speed Counter** — a Minecraft-style slide switch (stone track + redstone-block
  knob that lights up and slides right when on). Turns the head readout on/off,
  independent of the boost.
- The active speed row's label lights red so you can see the live mode.
- The panel is draggable, and its position is remembered.

## Auto-save

Settings persist across rejoins automatically (executor filesystem — needs
`writefile`/`readfile`/`isfile`; silently no-ops without them). Whenever you
change a value it writes `dely_booster_test67.json`, and on load it applies the
saved **normal speed, carry speed, boost on/off, speed-counter on/off, and panel
position**. No save button — it just remembers.

The blocky look uses `Enum.Font.Arcade` (the closest built-in to Minecraftia)
and 2px pixel bevels — light top/left, dark bottom/right — on the slab and
buttons, inset (pressed-in) on the speed slots and the sunken inner body. Swap
in a real Minecraftia font asset later if you want it pixel-perfect.

### Custom images

The panel uses uploaded Minecraft textures, set at the top of the script:

- `LEVER_ON_IMAGE` — lever **up** (enabled)
- `LEVER_OFF_IMAGE` — lever **down** (disabled)
- `DUST_IMAGE` — redstone-dust indicator in the header; it's tinted every frame,
  so it sits dim red when off and pulses bright red while the booster is powered.

Blank out `LEVER_ON_IMAGE` to fall back to the drawn (native) lever.

## Animations

All spring/`Back`-eased for a clean, snappy feel:

- **Panel** grows in on load.
- **Lever** does a squash-and-pop snap when it flips.
- **Switch-on** flashes the whole redstone circuit (border, dust, separator)
  bright for a moment, plus a tiny panel "thunk".
- **Speed slots** pop and warm up when focused; the live slot pops on every
  pick-up / drop.
- **Rows** lighten on hover.

## Normal vs Carry speed

The mover picks a speed automatically based on whether you're holding a
brainrot:

- `isCarryingBrainrot()` returns `true` when the player's `Stealing` attribute
  is set, or when `Humanoid.WalkSpeed` drops below `CARRY_WALKSPEED_MAX` (25)
  while still above 0 — which is how the game marks the carry state.
- Each frame the loop detects pick-up / drop transitions, flips between
  `getNormalSpeed()` and `getCarrySpeed()`, and lights the active speed row's
  label. No input from you is needed — walk into a steal and it switches, drop
  it and it switches back.

## Head counter (Speed Counter toggle)

Toggle the **Speed Counter** switch and a `BillboardGui` floats above your head
showing your real horizontal speed in studs/sec — measured from
`HumanoidRootPart.AssemblyLinearVelocity` with the Y component dropped, so
falling never inflates it. It's independent of the boost, uses the Arcade font,
and is client-side so no other player sees it.

- **Color logic (del-hub style):** the number sits white, and on a sharp
  acceleration it punches bigger and flashes — bright red on a big spike
  (Δ > 18), light red on a smaller one (Δ > 6) — then eases back to white.
- **Overlay:** it scans your character for any other `BillboardGui` (nametags,
  other speed counters, custom text) and parks itself just above the highest one
  (re-checked ~3×/sec), with `AlwaysOnTop` so it renders over them. If nothing
  else is up there it sits at `COUNTER_BASE_Y` (2.6 studs).

## How it moves the character

No `HumanoidRootPart.Velocity` writes anywhere.

1. An `Attachment` is created on the `HumanoidRootPart`.
2. A `LinearVelocity` is bound to it with `VelocityConstraintMode = Plane`,
   `PrimaryTangentAxis = (1, 0, 0)` and `SecondaryTangentAxis = (0, 0, 1)` —
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
