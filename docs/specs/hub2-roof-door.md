# hub2 roof hangar door (snow + daylight)

2026-11-14. Grilled with the user (7 questions). Specced only, NOT built (user: "spec, dont build").
Builds on [hub2.md](hub2.md), [hub2-storage.md](hub2-storage.md), [hub2-ps1-mood.md](hub2-ps1-mood.md).

Ask: open a gap in the roof over the spawn shaft so soft snow and sunlight come in (concept ref: snowy
industrial hall, light shafts through a roof opening, snow piled on ledges). Snow on the bridges and
ledges that sit in the open under the opening. User correction mid-grill: it is a **hangar door left
open, not a collapse** - nothing is destroyed.

## Facts (measured 2026-11-14, world space, Map scale 0.6)

- Shaft D runs x -12..12, z +80..-180. Spawn floor y 29. Shaft bottom y -94 (A below it further south).
- D's roof is flat at **y 58.1** over the whole run z +40..-160 (down-rays via `tests/_probe_hub2_rays.gd`).
- Low bridges cross D at y ~18-22 (around z -40 and z -90). The high E corridor crossing is at y ~51-57,
  only a few metres under the roof.
- Current sun: warm (1, 0.9, 0.78), energy 0.7, ~40 deg elevation from +X. Sky is the stepped dusk
  gradient from the PS1 mood pass. Environment is `resources/hub2_environment.tres` (cold blue ambient).

## Decisions

1. **Opening:** above D, **z -20 to -100**, full shaft width plus a few metres into the roof on each side.
   Both low bridges and the E crossing sit under it; from spawn the light starts ~100 m ahead.
2. **Real hole:** the roof mesh AND its collision are cut there; sky shows through.
3. **Door:** two sliding roof leaves (~40 m each) parted lengthwise along the shaft, parked over solid
   roof at each end, **stuck ~90 % open** (each leaf still overhangs ~10 %, clear gap ~65 m) - lost power
   mid-cycle. Heavy steel frame round the opening, rails along both long edges, drive gear housings,
   a dead amber beacon at each frame corner. Static, clean edges, no debris, nothing broken. Code-built
   PS1 props in the storage-dressing style (same rust/wear palette).
4. **Out of reach:** no roof-top area. Check jump/climb reach from the E crossing to the frame/leaves;
   if reachable, add an invisible stop-only layer at roof height (same approach as the boss arena's
   stop wall layer). Leaves and frame are solid.
5. **Light:** cold white winter daylight **through the opening only**. Steep (~65 deg) beams as faked
   PS1 light cards, landing on the bridges and the lower west wall. The rest of hub2 keeps its dark
   sodium/blue mood; the opening is the brightest thing in the map. Not volumetric fog.
6. **Sky in the gap:** pale stepped overcast (flat grey-white bands) with a soft sun-glow patch the
   beams line up with. The dusk sky stays everywhere else (e.g. over A).
7. **Falling snow:** soft and slow, ~1.2 m/s, gentle sway, no gusts. Column shaped like the opening
   with a few metres of spill past the edges. Falls past the bridges down to y -94 and fades into the
   dark. Medium density, ~4-6k mostly small flakes plus a few bigger near ones. Flakes inside the beams
   lit bright, outside dim grey. Visual only, no lens snow.
8. **Snow cover:** upward-facing surfaces with open sky above through the opening: bridges, open
   ledges, prop/pipe/crane tops in the column, door tracks and frame lip, shaft floor. Decided by a
   top-down open-sky map baked once at load (reuse Ichi's roof-map shelter technique, see
   `scripts/rendering/storm.gd` / `docs/specs/ichi-snowstorm.md` "Snow shelter"); soft fade at the
   border matching the spill. Look = white cover in the surface shader with a broken, uneven edge,
   old rust/grime through thin spots, PLUS low code-built mounds (~10-25 cm) along bridge edges, ledge
   lips, wall bases, door tracks.
9. **Gameplay:** none - no footprints, no slipping, no effect on movement. **No toggle** (map content,
   like the industrial pass).

## Notes for the build

- hub2's surfaces use `shaders/hub2_wear.gdshader` + `shaders/hub2_ps1.gdshaderinc`; the cover goes there
  (sampled from the open-sky map), and pools/fog are added as EMISSION - the daylight patch should agree.
- Cutting the roof: hub2.glb is 2 meshes with baked wear (`assets/hub2_wear/`). Either cut the roof
  triangles in the bake path or mask them in code at load; collision must be cut too. Re-bake after.
- Opening probe-shot from spawn, from a bridge, looking up, and looking down the shaft.
- Perf: measure with `tests/_probe_hub2_perf.gd` (held camera), not a moving probe.

## Rev 1 (2026-11-15): soft light + edge dusting

Grilled with the user (6 questions) after they saw hard lines in the light. Built same day.

1. **Light stays faked cards, made soft.** `shaders/hub2_roof_beam.gdshader`: every card samples one
   light field (lit where the sun ray reaches the roof inside the gap, edges feathered 3.5 m across /
   6 m along, fade in under the roof, eased out by the ~51 m reach to the west wall). Cards fade where
   they meet walls (depth) and when seen edge-on. Three slice families (cross-sections every 3 m,
   slant sheets every 3 m, level slices every 5 m), all cut bigger than the light.
2. **Soft static rays** inside the glow: streaks constant along each sun ray, no motion.
3. **Reach unchanged (~50 m).** 4. **Brightness matched to the old look**, same cold tint.
5. **Edge dusting** on every drop edge looking into the open shaft along the gap, thinning to nothing
   ~15 m past the gap's ends and with depth (35 % left 150 m down).
6. **Patchy strip, 30-75 cm, shader only**, specks further in; hazard-stripe decals follow the same
   rule so the paint reads through. No geometry, no collision change, no toggle.

Build notes: the baked convex-edge data also flags flush seams between map pieces (false X lines on
walkways), and a top-down first-hit map misses walkways under overhangs (they are open to the shaft
sideways). So `Hub2RoofDoor.bake_edges()` casts every floor level down each 0.3 m column (up to 4),
marks a lip where the neighbour has no floor within 1 m below and a sideways ray finds no wall, and
stamps distances per level (~0.4 s, spread over frames after load). The shader matches the point's
level per texel, so a drop's low side never bleeds into the lip. Probe: `tests/_probe_hub2_roof_light.gd`.
Perf: the beam slices cost a few fps in the shaft views (probe fps is noisy run to run).
