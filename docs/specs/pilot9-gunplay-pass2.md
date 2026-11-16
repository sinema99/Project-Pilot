# pilot9 gunplay pass 2 (2026-11-15)

Grounded and weighty (DayZ / Tarkov, third person). Builds on `pilot9-gunplay.md`. No sound this pass.

## Camera
- Hip camera untouched; drawing a gun never moves it.
- RMB: shoulder 0.8 m, arm 1.1 m (absolute, never longer than the normal arm), FOV cut as before.
- Shoulder swap: 0.5 s smoothstep (was an exponential ease), the destination side's wall clearance probed from the start.

## Pose
- Hip hold (`hold_rotations` / `idle_rotations`) untouched.
- `HeldItem.aim_rotations`: the arm pose at full aim, blended in by `aim_blend` over the hip pose; muzzle follows camera pitch.
- Reload: `GunReload` drives arm rotations + code props (mag / speedloader / brass) over the reload time; the aim pose drops while it runs and returns after.

## Recoil + bloom (real, mild)
- Per shot: camera pitch kick (revolver 2.2 deg, rifle 1.6), random yaw +-0.35 deg; 70% recovers over ~0.4 s, 30% stays until the player pulls down.
- Bloom (cone half-angle deg) +0.35 per shot, decays 1.2 deg/s; hip adds base 1.2 deg and kick x1.6. Aimed base 0.1 deg.
- Shot direction = camera forward spread inside the bloom cone.

## Feedback (pixelated)
Muzzle flash + 2-frame light, camera shake per shot (separate from recoil), fast moving tracer, world impact puff/sparks/fading hole (20 s), dummy flinch + push + red flash (kill bigger), hit-marker X, rifle casings.

## Reload
Revolver 2.0 s, rifle 2.5 s; tactical (rounds left) x0.8; empty fire press auto-reloads (`auto_reload`, on). Rifle empty adds a rack. Reload ring replaces the crosshair.

## Crosshair
Hip = one pixel block dot; aim = pixel ring (3 px blocks, radius = bloom); reload = ring fills clockwise; hit = block X. Reserve stays unlimited.
