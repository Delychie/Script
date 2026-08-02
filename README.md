# Speed Booster

A LocalScript speed booster for Roblox with a small on-screen panel.

## Install

Put `SpeedBooster.lua` in **StarterPlayer > StarterPlayerScripts** as a `LocalScript`
(or run it from any client-side script runner).

## Panel

- **Speed box** — type a number, press Enter. Clamped to 0–1000.
- **Presets** — 16 / 32 / 60 / 100 / 200.
- **ON / OFF button** — toggles the boost. `RightShift` does the same.
- The panel is draggable.

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
