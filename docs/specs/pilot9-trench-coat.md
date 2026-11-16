# pilot9 trench coat

Status: grilled 2026-11-11 (12 questions, every recommendation taken), built the same day. See
"Built" at the bottom for what the probes showed and where the build left the grill.

A long brown trench coat pilot9 wears over his suit. Low-poly and faceted for the PS1 look. Reference:
the user's picture of a long open leather coat with a big collar, epaulettes and a mid-calf hem.

## Decisions

1. **The skirt moves on bone chains with springs.** 8 two-bone chains added to his skeleton in code,
   the Knight's robe pattern (docs/specs/knight-coat.md). The mesh is built once and skinned; nothing
   is rebuilt per frame and there is no cloth simulation (the poncho was 6-8 ms a frame and was
   scrapped).
2. **Worn open.** Two front panels hang apart from the collar down; his chest, belt and legs show.
3. **Full sleeves to the wrist, hands showing.** His arm pieces are hidden while the coat is on.
4. **Silhouette details only.** Big turned-up collar, lapels, epaulettes, a centre back vent, flared
   cuffs. No buttons, belt or pockets. About 300-400 triangles.
5. **Brown.** Warm mid-brown body `(0.36, 0.22, 0.12)`, darker lining `(0.16, 0.10, 0.06)`. A step
   lighter than the hat's felt so the two read apart.
6. **T toggles it** (`coat` input action). Instant, no animation. **On at boot**, never saved.
7. **Both gameplay pilots, every gameplay map** (it is built by pilot9.gd, like the hat). Never on
   the cockpit cutscene pilot or the Knight (neither is a pilot9.tscn). Hidden with him inside EXIA.
8. **Heavy leather.** Near-still at idle (1-2 cm at the hem), about 15 deg behind him in a run,
   35-45 deg in a sprint and on rails, a flare on falls, a snap on the dash, settles in about 0.4 s.
   Capped below horizontal.
9. **Awkward states.** Chain tips are kept above the floor under him and off the wall he is on
   (plane checks from what the controller already knows, no physics queries). Slide: tails lie back
   along the ground. Crouch: the skirt pools outward. Wall-run / wall climb: the wall side is held
   off the wall, the open side streams. Mantle / vault: the tails hang toward world down, so they
   drape off him. Clipping through his own legs in extreme poses is accepted.
10. **Faceted in every look.** Flat-shaded panels in AIRFRAME, RETRO and COMPOSITE alike.
11. **The dash afterimages wear it**, frozen as it was that instant. Dash frame time must not move.
12. **Budget: 0.3 ms a frame** for the spring tick with both pilots in the scene, measured by a
    probe. If it goes over, chains are cut before it ships.

Small things settled in the grill summary: the hat and coat are independent (H and T); the collar
stays below his ear fins and the hat brim; the Ichi storm's wind pushes the tails in the tredge.

## How it works

- `scripts/items/trench_coat_mesh.gd` builds the coat in his skeleton's REST pose (his rest is not
  his bind pose, so the coat is fitted to the body as the rest pose shows it:
  `tests/_probe_coat_body.gd`). One ArrayMesh, two surfaces (Leather, Lining), every triangle with
  its own three vertices and its face normal, so it shades faceted in every look.
- `scripts/items/trench_coat.gd` (`TrenchCoat`, built by `pilot9.gd::_setup_coat()`):
  - adds the chain bones (`CoatU0..7` under Hips at the waist, `CoatL0..7` under those at the knee
    row) and a Skin that binds every bone by name;
  - puts one MeshInstance3D (`TrenchCoat`) under the skeleton, so the afterimage pool, the rim
    light and every LOOK pick it up the way they pick up his body;
  - hides his arm pieces (any body mesh that is at least 95 % arm by weight) while the coat is on;
  - ticks the springs in `_physics_process`.
- **Materials.** The mesh's surface materials are plain StandardMaterial3D in the two browns (what
  AIRFRAME and Jetpack read a colour from, and what makes them bake the rest pose so the colour
  pixels ride the coat); the surface overrides are pilot9's cel material tinted the same (what
  RETRO twins). The lining has no ink.
- **Springs.** Each segment is a 2D tilt (radians, x his left, y his front) in his hips frame on a
  damped spring. The spring's rest is: world down (most of it), drag from his speed (a pendulum in
  a wind: `atan(k v^2)`, capped), a radial flare from falling, a swirl from turning, the idle sway,
  and the crouch pool. After the step, in order: the body limit (a panel may come in toward him a
  few degrees only, and a thigh or shin swinging out pushes it out), the hard cap, then the planes
  (floor, wall) on the knee row and the hem.

## Tunables

Exports on the `TrenchCoat` node (`pilot.coat`): colours, `drag`, `drag_cap_deg`, `flare_deg`,
`swirl_deg`, `gravity`, `freq`, `damping`, `idle_deg`, `inward_deg`, `cap_deg`, `crouch_pool_deg`,
`wind_speed`.

## Tests and probes

- `tests/test_pilot9_trench_coat.gd`: key, on at boot, toggle, bones, mesh (faceted, triangle
  budget, weights), arm pieces hidden, sprint trail, floor limit in a slide pose, wall limit, caps,
  ghosts, boarding, not on the cockpit pilot or the Knight.
- `tests/_probe_coat_shot.gd` (windowed): shots of each state in each look.
- `tests/_probe_coat_cost.gd`: the spring tick's cost.

## The fitted cut (2026-11-11, second pass)

Played: "looks really really good", but a little bulky, and his back came through it in a jump.
Grilled (6 questions, every recommendation taken) and built the same day.

1. **Slimmer from the hips up only.** Shoulders 29.5 -> 26.5 cm half-width (his pads reach 25),
   chest 24.3 -> 22, waist 23.5 -> 19.5; back depth 26 -> 21.5 at the chest and 24 -> 20 at the
   waist; sleeves a fifth thinner (7.5 / 6.8 / 6.2 cm), cuff 9.6 -> 8. The hip row comes in about
   2 cm to meet the waist. Knee row, hem, length and all the motion are unchanged.
2. **What the coat covers is cut out of his body while it is on.** Of his trunk pieces (torso,
   hip piece with the back pouch, neck piece, shoulder balls) only a front strip stays: chest,
   stomach and belt, 7 cm wider than the opening each side so its edge sits under the front
   panels, plus what stands inside the collar. Nothing is left to come through, which is what
   lets the back and sides sit on his outline. The front panels still clear his chest by ~2 cm.
3. **Legs stay whole.** The skirt streams and lifts, so they show. If a thigh ever comes through
   the back of the skirt, raise the back panels' push-out (`THIGH_PUSH`), do not cut the legs.
4. **Collar, lapels and epaulettes keep their size**; they move in with the shoulders.
5. T swaps the whole body back. Both pilots. Ghosts and the rim light use what he is wearing.

How: `scripts/items/trench_coat_body.gd::cut()` decides per triangle in the rest pose, by where
it sits (`covers()`) and which bones carry it, so it works on either body. `trench_coat.gd::
_cut_body()` adds one sibling MeshInstance3D per covered piece (`<piece>CoatCut`) wearing the cut
copy and hides the piece itself while the coat is on, the way the arm pieces are hidden. Siblings,
not a mesh swap: the hat and AIRFRAME already swap `mesh` on his own pieces. Cut copies are cached
per mesh; nothing runs per frame.

Probe shots (AIRFRAME and RETRO, pilot 1 and 2; idle, jump, fall, sprint, slide, mantle,
wall-run, from straight behind as well): nothing of him comes through the back. Through the open
back vent you see his legs and, above them, lining where the pouch was (accepted in the grill).

## The flat back (2026-11-11, third pass)

User: the back is way too bulky. Grilled 3. The fitted cut had fitted the back to his body with
the backpack and hip pouch still counted (~-0.20 to -0.215), although both are cut away while the
coat is on. Decisions:

- Back centre and back corners from the yoke to the waist sit on his VEST line: B -0.16 at yoke,
  shoulder, chest and waist (straight, no waist pinch); BC -0.155 (yoke corner already -0.14).
- Hips and skirt untouched (user likes them), so the step out from waist to hip is sharper.
- Collar (and its flare) untouched.

## The slim cut (2026-11-11, fourth pass)

User: needs to be way slimmer, with a red line drawn over the back probe shot (view 0, idle,
AIRFRAME). Grilled 7, every recommendation taken:

1. **Match the red line exactly.** Hourglass: fitted top, tightest at the waist row, skirt flares
   from the waist to the hem it already had (hem width and length unchanged).
2. **Collar** is a short stand ring close round the neck: foot 0.135 at the side, top 0.175 and
   ~4 cm lower (1.67 at the side, 1.677 at the back). Lapels come in to meet it.
3. **Shoulders** come in to his own shoulder line; **epaulettes** stay, 2/3 size, inside the line
   (0.15 -> 0.22, half width 0.024, depth 0.033).
4. **Sleeves** slimmer: 6.0 / 5.8 cm upper, 5.5 elbow, 5.0 forearm, cuff flare 6.5.
5. **All the way round**: each row is pinched by the same share at every column, not only the back.
6. **The red line wins over clipping**: cut more trunk rather than widen; a thigh through the
   skirt gets more leg push, not a wider waist.
7. Done = the probe shot from the user's camera with the red line laid over it, plus side /
   three-quarter / pose sheets for poke-through.

How the line was read: the drawing was aligned onto the probe shot (scale 1.0079, +4,+6 px, by
matching the background), then each red stroke was projected back through the probe camera onto
the z = 0 plane at a ladder of heights (`tests/_tmp_coat_redline.gd`). Half-widths, red vs the
coat before: shoulder row 1.50 m 0.245 vs 0.265; chest 0.226 vs 0.22; waist 0.196 vs 0.195; hip
0.95 m 0.217 vs 0.245; knee 0.295 vs 0.30; hem 0.34 vs 0.335. Chest, waist, knee and hem already
sat on the line: what read as bulk was the square yoke, the tall flared collar, the thick sleeves
and the skirt flaring from the hip instead of the waist.

Built (`trench_coat_mesh.gd` row tables): yoke side 0.25 -> 0.22 (corners 0.215 -> 0.19), shoulder
row side 0.265 -> 0.245 (corners 0.235 -> 0.215), hip row pinched ~11 % at every column.

One departure: the hip row's side is **0.23, not the line's 0.217** (corners 0.212 / 0.208). At
0.217 his upper thigh came through the side of the coat in the jump (hip flexed). That is a leg,
not trunk (narrowing the kept front strip changed nothing), and leg push only swings the skirt
along the thigh, not sideways, so it cannot clear it. 1.3 cm is ~4 px on the user's shot.

Probe shots (AIRFRAME idle + red-line overlay `coat_slim_cut.png`, before | after; RETRO idle,
run, sprint, jump, slide, wall-run, mantle, vault, fall, run-backward; AIRFRAME run, jump,
crouch): on the line, nothing of him through the coat. In the slide his knee shows under the skirt
where it lies open on the floor (skirt, not a hole).

### Way tighter (2026-11-12)

User played the slim cut: "nothing changed" - true at play distance, the red line had been within
1-4 cm of the old coat everywhere. Then: "all of it, way tighter everywhere". The red line is no
longer the target; his body is.

- **Below the waist the floor is his legs** (+-0.215 x the whole way down, z -0.11..+0.135; whole
  and never cut). The skirt is a near-straight column just outside them: hem side 0.335 -> 0.255,
  knee 0.30 -> 0.245, front and back of the skirt ~0.20 (was 0.275 / 0.345). It leans on the leg
  push in a stride. Hip side 0.24 and waist side 0.20: tighter and his thigh comes through at the
  hip in the sprint / jump (probe-shot).
- **Above the waist** his trunk is cut away, so the coat sits inside his old outline: yoke 0.195,
  shoulder row 0.215, chest 0.20, back -0.135 from yoke to waist (was -0.16).
- **The kept front strip is narrower** (`STRIP_MARGIN` 0.07 -> 0.03): with the front corners
  pulled in, his tan vest came through the left front panel at the upper chest.
- Collar foot 0.12 / top 0.155, epaulettes 0.14..0.195 (half width 0.02), lapels in to match.
- **Sleeves are back at the original size** (7.5 / 7.3 upper, 6.8 elbow, 6.2 forearm, 8.0 cuff):
  user liked the torso but the 5 cm sleeves were too skinny.

Probe shots (RETRO idle, run, sprint, jump, crouch, slide; AIRFRAME idle): nothing of him through
the coat; in the slide his knee shows where the skirt lies open (as before). `coat_slim_cut.png` is
now original | way tighter, back view. `test_coat_is_fitted` checks the new shape.

### The low top (2026-11-12)

User (red lines on a front shot): bring the top down so the red scarf shows, clipping is fine.
Everything from the chest row (1.34) up is squashed into a lower band, y' = 1.34 + (y - 1.34) *
0.638: yoke 1.506-1.522, shoulder row 1.442, collar foot ~1.525 / top 1.544-1.555, lapels and
epaulettes moved with it. Widths unchanged. The cut keeps what stands inside the collar from
1.50 up within 0.10 (`trench_coat_body.gd` COLLAR_Y 1.56 -> 1.50, COLLAR_X 0.11 -> 0.10): the scarf
shows; 0.14 also kept his vest straps and shirt collar, which stuck up beside it. A sliver of the
shirt collar can still show at the front (accepted). Shot: `coat_low_top.png` (RETRO idle sheet).

Then (same day) user: halfway between where it was and the low top. Factor 0.819 (the mean of 1
and 0.638): yoke 1.553-1.573, shoulder row 1.471, collar foot ~1.575 / top 1.602-1.616, lapels and
epaulettes with it; cut keeps the scarf from 1.53 up (COLLAR_Y 1.50 -> 1.53). The scarf shows at
the front and sides; at the back the collar now covers it. `coat_low_top.png` re-shot.

### Bare wrists (2026-11-12) - SUPERSEDED the same day by "Long sleeves" below

User: show his wrists. (A bare-shoulder version, with detached sleeves held by a strap and brass
buckle, was built and rejected the same session: shoulders stay covered, no strap, no buckle.)

- The cuff ends ~9 cm short of his hand: lower ring 0.285 -> 0.24, cuff rim 0.315 -> 0.27 down the
  forearm (radii unchanged, 6.2 / 7.8 cm). His hand starts at 0.364.
- His arm pieces are still hidden whole, but now each has a cut copy like the trunk pieces
  (`trench_coat_body.gd::cut_arm`): only what lies below `cuff rim - CUFF_TUCK` (0.02, past the
  cuff's mouth disc) along his arm is kept, so just the white end of his forearm shows. The
  upper arm, elbow pad and shoulder ball cut to nothing and get no copy.
- Test `test_wrists_show_below_the_cuff`. Probe shots (RETRO idle, run): white wrist between cuff
  and glove, shoulders covered.

### Rounded shoulders (2026-11-12)

User: "cover up the shoulders, round them into the body". The sleeve's square open top stood
beside the coat's shoulder with a notch between them. Now each sleeve starts with a closed dome
inside his shoulder: rings at -0.035 / -0.01 / 0.03 / 0.18 along the upper arm (radius 0.03 /
0.06 / 0.077 / 0.073), tip at -0.05. The head rings ride his shoulder bone up to 50 % (fading out
by 3 cm down the arm), so a hanging arm doesn't swing the dome up. +60 triangles (426). Probe
shots (RETRO idle, run): the shoulder line slopes into the sleeve from every side, no notch.

### Long sleeves (2026-11-12)

User: "bring the cuffs down so you cant even see the wrists. make the sleeves longer. only the
hands show". Replaces "Bare wrists": lower ring 0.33, cuff rim 0.36 down the forearm (was 0.315
originally, 0.27 for the bare wrists); his hand starts at 0.364. The forearm cut (`cut_arm`) is
gone again, the arm pieces are hidden whole as before. Test `test_cuff_reaches_his_hand`. Probe
shots (RETRO idle, run): only his hands come out of the sleeves; rounded shoulders unchanged.
