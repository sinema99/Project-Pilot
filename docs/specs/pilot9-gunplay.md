# pilot9 gunplay (framework pass, 2026-11-14)

Hitscan only; revolver and rifle; tested on the firing-range dummy. Everything numeric lives in `GunDef`.

- Input: RMB `aim` (hold), LMB `fire`, R reloads with a gun out (number key / R with nothing out still holsters), dash is Q. No gamepad this pass.
- Slots: 1 rifle, 2 revolver. Staff is unslotted; its reflect and tredge-torch code stays dormant.
- Guns: both single fire, 0.35 s apart. Revolver 25 dmg / 6 rounds / 2.0 s reload. Rifle 50 / 10 / 2.5 s. Reserve unlimited (`6 / ∞`).
  Empty = dry click, count red, no auto reload. A swap keeps each gun's rounds and cancels a reload.
- Shot: ray from the camera through screen centre, 200 m, no spread, mask world + dummy hitbox; calls `take_hit(damage, &"bullet", point)`.
  Hip-fire allowed. Tracer + spark only.
- Aim: shoulder 0.6 m, arm x0.7, FOV -10% revolver / -18% rifle, look x0.7, sway x0.5, eased 0.15 s. Faces camera + walk pace while aiming, and for 0.5 s after a shot.
- Disabled (gun stays drawn): slide, dash, wall-run/climb, mantle, vault, rail, carrying, tredge, riding, frozen; no aim in the air.
- HUD: circle crosshair (wide hip, tight aim, red flicker on hit) and ammo bottom right with the gun name; only while a gun is drawn.
- Built: `scripts/items/gunplay.gd`, `scripts/items/gun_def.gd`, hooks in `scripts/pilot9.gd`. Tests: `tests/test_pilot9_gunplay.gd`.
