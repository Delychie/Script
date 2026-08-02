# Dely Booster Test 67

A LocalScript speed booster for Roblox with a small on-screen panel.

## Install

Put `SpeedBooster.lua` in **StarterPlayer > StarterPlayerScripts** as a `LocalScript`
(or run it from any client-side script runner).

## Panel

- **Speed box** — type a number, press Enter. Clamped to 0–1000.
- **Presets** — 16 / 32 / 60 / 100 / 200.
- **ON / OFF button** — toggles the boost. `RightShift` does the same.
- The panel is draggable.

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
   velocity.PlaneVelocity = Vector2.new(moveDirection.X * speed, moveDirection.Z * speed)
   ```

4. When `MoveDirection` is zero (no input), the constraint is disabled so the
   Humanoid stops normally and outside forces still apply. It re-enables the
   moment there is input again.

The mover is rebuilt on every respawn via `CharacterAdded`, and the panel
survives respawns (`ResetOnSpawn = false`).
