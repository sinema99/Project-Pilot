# Knight boss - body

Status: built 2026-11-09.

The first boss's body: an armoured, robed knight from a reference drawing the user sent (an
Instagram post, artist therestlessbrain / panelperday; the red swords in it are not part of this).
**Body only**: no AI, attacks, health or effects. His fight gets its own grill once the user has
seen him.

## Decisions (grill 2026-11-09, all recommendations taken except Q9)

1. **Godot code, no Blender.** Every part is built by `scripts/boss/knight_body.gd` at load.
2. **Robe = 4 split panels skinned in code.** An `ArrayMesh` with bone weights bound to a `Skin`:
   the top of each panel is weighted to `Hips`, blending down into the nearest thigh, then shin, so
   the panels part when the legs move. No physics cloth (the poncho was 6-8 ms/frame and scrapped).
3. **pilot9's own meshes are removed**; the whole knight is built on his skeleton.
4. **A boss** (not a playable pilot, not a prop).
5. **This pass is the body only.**
6. **In the Boss Arena, frozen in the drawing's pose**, hovering ~1 m up (lowest point of the
   sabatons 1 m over the floor), at `BossAnchor`, facing the spawn. The pose is bone rotations
   in code (no clip, no bob). **F6** (arena only) toggles to pilot9's `idle.res` to check the
   skinning. F6 is also Tredge's mode key, but only in Ichi.
7. **1.5x pilot9** (~2.7 m).
8. **Drawing colours through the RETRO cel/ink path.** pilot9's cel material duplicated per part
   (`material_override` on every part), the shadow tone leaning taupe-brown via `shadow_tint`.
9. **Hands: both the same rigid half-open claw** (user picked the simpler option), one mesh per
   `Hand` bone. pilot9 has no finger bones.
10. **Detail:** spikes as real cones (~8 per pauldron, a ridge on the hood, a few on the forearms),
    the chest as overlapping curved bands, the teardrop slots as flat dark decals.
11. **Head:** narrow hood-helm rising to a point that leans back, spike ridge, cream mask plate
    with an inked crack mark, no eyes, no glow.
12. **Lower body:** robe to mid-shin, flared, torn zigzag hem, brown inner face; slim shin plates;
    long pointed sabatons.
13. **Name: Knight** (`KnightBody`, node `KnightBoss`).

Correction found while building: the drawing faces the viewer, so the reaching arm (image left)
is his **right** arm and the low hand is his **left**. The grill summary had it the other way;
the build matches the drawing.

## Rig facts

pilot9.glb's `GeneralSkeleton`: 25 humanoid bones (BoneMap names: Hips, Spine, Chest, UpperChest,
Neck, Head, Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes, plus
`mixamorig_*_End` leaves). Rest = T-pose, 1.81 m, faces +Z, his left = +X. Hips 1.06, knees 0.50,
ankles 0.03 (tiny feet), shoulders 1.52, hands +-0.93 on X, head bone 1.64, top 1.81.

## Build

- `KnightBody` (Node3D): instances pilot9.glb, frees its meshes, builds one skinned
  `MeshInstance3D` per material on its skeleton. Parts are modelled in the skeleton's rest space;
  the skin's binds are the bones' inverse global rests, one per bone in bone order.
- Materials: armour (sage), robe outer (sage), robe inner (brown), under-cloth (taupe: sleeves,
  thighs), mask (cream), sash (near-black), decals (dark, no ink pass).
- Pose: a table of model-space rotations per bone, applied relative to the parent
  (`local = rest_local * G^-1 q G`).
- `BossArena` places the `KnightBoss` node at `BossAnchor`, lifted so the posed sabaton tips sit
  `hover` (1 m) over the floor, turned to face the spawn.

## Checks

`tests/test_knight_body.gd`: every mesh under the skeleton is the knight's own (no pilot9 mesh),
each is skinned to the skeleton with a bind per bone, every part has a `material_override`, the
robe really blends (vertices with both a hip and a leg weight), the pose moves the bones, F6 idle
toggles, and the arena puts him over the anchor at the hover height. Look judged from probe shots
(`tests/_probe_knight_shot.gd`, front / side / back) against the drawing.

## Built (2026-11-09)

Tuned from probe shots. Colours: armour (0.64, 0.71, 0.62), robe (0.62, 0.67, 0.59), inner
(0.47, 0.39, 0.33), cloth (0.5, 0.52, 0.46), mask (0.97, 0.95, 0.84), sash (0.14, 0.13, 0.13).
`shadow_tone` 0.66 (pilot9's 0.45 went near-black) and `shade_tint` (0.68, 0.5, 0.4, 0.8); the mask
tints only 0.4. The arena sun is behind him as seen from the spawn, so the player mostly sees his
shadow side - judge colours there. Round 1 fixes: mask shrunk (it read as a face), spikes cut to
6 per pauldron and made stubbier (they read as fur), chest teardrops replaced by wavy ink lines on
the band edges (they read as tears), ink lines on the pauldron lame rims, hood point leaned back.

## Round 2: look pass (grill 2026-11-09, every recommendation taken)

The user: "doesn't look great but not a bad start, bring it closer to the reference". Six decisions:

1. **His own key light.** `KeyLight` (DirectionalLight3D, child of `KnightBody`) lights render layer
   `KnightBody.LIGHT_LAYER` (19) only; every part sits on that layer alone, and `BossArena` takes the
   layer out of the sun's cull mask (`KnightBody.exclude_from`), so the sun never lights him twice.
   It comes from his upper front right (the drawing's image left, `key_from`), casts shadows on him
   only (`shadow_caster_mask`), `SKY_MODE_LIGHT_ONLY`. Colours to match: cool mint lit, mauve-brown
   shadow in big shapes.
2. **Head:** a rounded helm ~25% smaller with a short point leaning back, low between the pauldrons;
   the visor a narrow cream beak plate toward his right (`VISOR_YAW`), crack kept; ridge spikes gone.
3. **Robe:** covers the legs (only the sabaton tips show), hem ~2.5x shoulder width, a frozen sweep to
   his left (`SWEEP`, `SWEEP_LEFT`), 8 pleats as 16 flat faces (sharp creases the key light paints
   light/dark), 5 big ragged hem points (`HEM_POINTS`), a wider darker sash. The hips keep at least
   half of every robe vertex now, so the wide hem does not swing with the legs.
4. **Armour:** pauldrons as 3 stacked lames that drape (weights blend Shoulder -> UpperArm outward, so
   the dropped left arm's pauldron hangs over it), ~16 tiny rivet spikes and 6 small slots each; chest
   as 4 rows of overlapping pointed scale plates whose lower edges sweep down to the sides, inked;
   claws 1.5x longer and thinner.
5. **Ink:** outline 1.5x (`ink_scale`: CEL reads the outline pass's `ink_width`, RETRO multiplies its
   own by the pass's `ink_scale` meta in `RetroLook.ink_chain`); ink on every plate edge (lame rims,
   helm rim, vambrace cuffs, chest plates) and down every robe crease. No hatching.
6. **Pose:** frozen, no bob. Reaching right arm flung out near level, left hand at the belly, head
   dipped and turned toward the reaching hand.

**Correction found while building:** the grill said the body leans to his LEFT. In the drawing his
top goes to his RIGHT (image left; his left shoulder rides high) while the robe sweeps to his left:
that makes the drawing's diagonal. The build matches the drawing (Hips/Spine/Chest roll toward his right).

### Built (2026-11-09)

Tuned from probe shots (front, quarter, left, back, head, plus the new `knight_player.png` from the
spawn side). Colours: armour (0.6, 0.71, 0.63), robe (0.62, 0.73, 0.64), mask (0.86, 0.82, 0.66);
`shadow_tone` 0.46 with `shade_tint` (0.82, 0.52, 0.6, 1.0). The tint has to be strong: the arena's
blue ambient fills his shadow side and pulls a weak tint back to olive. Robe inside and under-cloth
use `cloth_shade_tint` (alpha 0.35) or their brown goes red. The key light comes from the front, so
from behind he is all shadow tone (brown); judge him from the spawn side.
