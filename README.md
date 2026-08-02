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
- **Presets** — 16 / 32 / 60 / 100 / 200 cobblestone buttons (set the Normal speed).
- **Lever** — flip it to toggle the boost; the lamp, knob and border light up
  red ("powered"). `RightShift` toggles it too.
- The readout at the bottom shows the live mode (`Normal` / `Carrying`).
- The panel is draggable.

The blocky look uses `Enum.Font.Arcade` (the closest built-in to Minecraftia)
and 2px pixel bevels — light top/left, dark bottom/right — on the slab and
buttons, inset (pressed-in) on the speed slots and the sunken inner body. Swap
in a real Minecraftia font asset later if you want it pixel-perfect.

### Custom lever image

Uploaded your own redstone switch? Paste the asset id into `LEVER_ON_IMAGE` (and
optionally `LEVER_OFF_IMAGE`) at the top of the script. When `LEVER_ON_IMAGE` is
set, the panel hides the drawn lever and shows your image instead, swapping it on
toggle. Leave both blank to keep the native drawn lever.

## Normal vs Carry speed

The mover picks a speed automatically based on whether you're holding a
brainrot:

- `isCarryingBrainrot()` returns `true` when the player's `Stealing` attribute
  is set, or when `Humanoid.WalkSpeed` drops below `CARRY_WALKSPEED_MAX` (25)
  while still above 0 — which is how the game marks the carry state.
- Each frame the loop detects pick-up / drop transitions, flips between
  `getNormalSpeed()` and `getCarrySpeed()`, and updates the panel's mode
  readout. No input from you is needed — walk into a steal and it switches,
  drop it and it switches back.

## Head counter

While the boost is ON, a `BillboardGui` floats above your head showing your
real horizontal speed in studs/sec — measured from
`HumanoidRootPart.AssemblyLinearVelocity` with the Y component dropped, so
falling never inflates it. It turns green while the constraint is actively
pushing and grey when you are coasting, and hides entirely when the boost is
OFF. It is created client-side, so no other player sees it.

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
