# pilot9 rifle (2026-11-14)

**Rev 4 (2026-11-15, aim only, carry untouched):** the aim pose is now a shouldered rifle after the user's reference photo, and the aim camera is the over-the-shoulder framing of their second screenshot. (1) Bladed stance: new `HeldItem.aim_twist_deg` (rifle only: Spine -15, Chest -15, UpperChest -10, Neck +12, Head +22; NEGATIVE yaw turns his right shoulder back), applied by `ArmPoseModifier.apply_twist` on top of the animation, scaled by `aim_pose`, so hips and legs keep facing the camera and strafing is unchanged. (2) Arm poses re-solved WITH the twist on by `tests/_probe_solve_aim.gd`: grip level with the shoulder 0.40 m ahead and 0.10 m toward the chest, barrel within ~5-10 cm of the eye line, elbows hung; the three pitches are solved independently, so the blend between them may wobble a little. Barrel still converges on the crosshair target. (3) Camera, ALL guns: `AIM_SHOULDER_OFFSET` 0.8 -> 1.0, `AIM_ARM_LENGTH` 1.1 -> 1.25, FOV cut rifle 18% -> 28%, revolver 10% -> 20%. The agreed start was arm 0.8, but settled it fills the frame (head ~45% of frame height against ~22% in the reference); the extra zoom comes from the FOV cut, so the arm went FURTHER out. The revolver's aim arms were not re-solved (no twist for it). Probe-shot only, not played. The probe `_probe_gunplay_pose.gd` now waits 140 frames before the aim shot (the camera is a spring; 30 frames showed a half-settled view).

**Rev 3 (2026-11-15, supersedes the code-built model in rev 1 and rev 2):** the user rejected both code-built rifles and modelled it in Blender: `assets/rifle.glb` (from Documents/rifle.glb; muzzle -X, stock +X, up +Y, 4 materials). `rifle_model.gd` now works like the revolver's: fits the GLB to 1.5 m, grip_point (15.5, 15.4, 0) and muzzle_point in GLB units, repaints every surface with the pilot cel material in its own Blender colour. A re-export over assets/rifle.glb lands without code changes. Chest carry kept; 2026-11-15 after the first in-game look ("hold it closer to his body"): grip pulled in to (0.06, -0.28, 0.14) from the right shoulder (was z 0.30), left fist on the front of the receiver 0.30 m ahead of the grip; both fists land within 1 mm. Barrel angle unchanged. **Then (same day, user: "the gun needs to rotate like 90 degrees, facing to the left"):** the barrel now points straight across his chest to his LEFT (yaw 90, still 35 deg down), not forward. Grip at (0.20, -0.28, 0.20) from the right shoulder, left fist 0.45 m down the barrel; both fists within 1 mm. Not played since.

**Rev 2 (same day, supersedes the model, size and hold below):** the first pass read as a plain marksman rifle and the sprint carry looked bad. Rebuilt after the real reference (three ArtStation "Marks 110" views): about 1.5 m, fat 9 cm barrel with a flat muzzle disc and clamp collar, tan sheet-metal receiver and handguard shell with dark cutout windows, boxy scope with twin front rods and a big round eyepiece, chunky magazine with a red base plate, skeletal black stock, rail rod and folded bipod, cable loops; four flat cel tones (tan, gunmetal, black, red), ~1,500-2,500 tris. Footprint 6x2. Hold: ONE two-handed chest carry at every ground speed (`hold_rotations` == `idle_rotations`), muzzle 35 deg down and 25 deg across toward his left, right hand on the grip at lower chest, left fist on the handguard 0.30 m ahead of the grip (reach limit; further is out of arm length), stock tucked at the right armpit (clips into the coat a little, accepted). Arm override still off in the air, wall-run, wall-climb, climb, rail and slide. Poses solved by `tests/_probe_rifle_shot.gd` (tunables at its top); left fist lands within ~5 cm. Probe-shot only, not played.


Grilled, then built the same day. Reference: ArtStation "Marks 110" (artwork WdXeK3).

## Decisions
- Held prop only: no firing, ammo, recoil or scope view.
- Replaces the staff as weapon 1 (default loadout, `starting_item`, `weapon_slots[0]`). The staff stays
  an item but is not slotted, so there is no reflect/parry until it is equipped. The reflect code is untouched.
- Item: `rifle_weapon.tres` (6x2, weapon slot) -> `rifle.tres` (HeldItem) -> `scenes/items/rifle.tscn`.
- Model: `scripts/items/rifle_model.gd`, built in code from boxes and 8-sided tubes, about 1.3 m,
  300-500 tris, no textures. Flat cel colours: tan (handguard, stock, grip), gunmetal (barrel,
  receiver, scope, brake), near-black (magazine, bipod). No wear, no cables or brackets.
- Item frame matches the revolver: origin at the pistol grip, -Z down the barrel, +Y up.
- Hold: two-handed low-ready carry on the ground (`idle_rotations`, both arms); sprint blends to a
  one-handed side carry with the left arm hanging (`hold_rotations`). `hold_at_any_speed`.
  Arm override is off in the air, wall-run, wall-climb, climb and rail (holder list) and in a slide
  (`hold_off_states`). Off means the rifle stays in his right hand and follows the clip.
- Holster: it just disappears for now. The materialize effect is later.

## How it is built
- `ItemHolder.ARM_BONES` now lists the left arm after the right (right four stay first; `equip_anim.gd`
  slices the first four). Staff and revolver only set the right arm.
- The arm poses come from `tests/_probe_rifle_shot.gd`: a two-bone solve per arm, applied to the
  skeleton, fist measured, target corrected, 10 rounds. The rig's bone rest offsets are not along +Y, so an
  open-loop solve misses by 0.1-0.2 m. Tunables are at the top of the probe; paste its printed
  dictionaries into `rifle.tres`.
- Save version 2: an older save's staff on weapon 1 becomes the rifle and the staff goes into the grid.

## Known consequences
- The Ichi blizzard torch needs the staff slotted (`staff_slot()`); with the rifle on 1 there is none.
- Not played yet. Hold pose judged from probe shots only.
