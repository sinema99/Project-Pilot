# Descent shot: tundra trees

2026-10-16. Grilled with the user, then built the same day. This adds sparse northern spruce to the
descent shot (`scenes/cutscene_descent.tscn`, docs/specs/cutscene-descent.md). It is not a forest:
it's tree lines along creeks with open snow between them, and it should look realistic. The trees
use the project's cel style.

Facts that shaped it: the camera stands 1.7 m up on flat snow (FOV 40, horizon at sketch y 545), so
anything 300 m or more away sits in a thin band just under the horizon. A 15 m spruce is about 95 px
tall at 150 m, 30 px at 500 m and 8 px at 2 km (sketch px, 847 high).

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Bands | **Three.** Close lone spruces 60-200 m, mid tree lines 300 m - 1.5 km, far clumps 1.5-5 km |
| 2 | Close placement | **2-3 on the left** (sketch x ~120-380, under the storm wall, near the 320 m wreck) and **1 on the right** (x ~1450-1650, inside the pillar). The middle, x ~700-1300, stays clear for the city and the trail's Finish. Asymmetric on purpose |
| 3 | Close tree | **A procedural tundra spruce built in code** (no Blender asset). Slender pencil silhouette, 12-18 m tall and 2-3.5 m across at the base. 6-10 irregular drooping tiers with uneven spacing, some thin on one side, a clumpy spire top, and bare trunk at the foot on some trees. Seeded, so no two match. Shaded with the shot's cel material (`cel_ground.tres` base) |
| 4 | Colour | **Near-black spruce green** (about `#1f2e2a`) with **snow on top of each tier**: a pale cap on each branch skirt's upper face, heaviest on the close trees and lighter on the mid ones. The undersides stay green, which matters because the low camera looks up at them |
| 5 | Mid tree lines | **5-6 creek-line ribbons**, each 80-400 m long and 1-4 trees deep, at mixed angles (some recede toward the city). Ragged tapering ends, gaps along them, plus a few strays and pairs between. 150-250 trees using a cheaper version of the close spruce. A ribbon never covers more than a wreck's lower third |
| 6 | Far clumps | **Low 3D mounds with a scalloped spiky top**: a mass of overlapping tree tips that reads as a lump of spruce. They're **forced 2-tone** (lit green and shadow green, hard split by the sun's direction) with no snow, paint or scatter. They carry the ribbon pattern outward, thinning toward the city, with a few patches among the sprawl's outskirts. Fog pales them like the city |
| 7 | Ink | **Close trees only.** Mid ribbons and far clumps get no ink, because tier creases at 30 px or less would scribble black |
| 8 | Motion | **Only the close trees**: a whole-tree lean from the base, **0-0.4°** downwind (tip about 10 cm), on a slow sine with a 4-6 s period. Each tree has its own phase, and it's driven from the shot clock (`apply(t)`), so scrubbing gives the same result every time. Everything else is static |

Defaults (not asked): placements are tables in `DescentShot` (sketch x and distance, like
`FIELD_WRECKS`), with a seed export. The trees are generated with no owner, like DescentLand, and have
no collision, so the storm's roof bake ignores them and the snow falls through. The lightning flash
lights the close and mid trees like everything else; there's no special rim.

Not in it: snow wells around trunks, wind reacting to gusts (the eye has none), and trees in other
shots.

## Built

Built 2026-10-16 in `scripts/cutscene/descent_trees.gd` (`DescentTrees`, the `Trees` node under
`Descent`, below `Land`) and `shaders/cutscene/tree_clump.gdshader`. The placement tables are
`TREE_LONE`, `TREE_RIBBONS` and `TREE_FAR_LINES` in `scripts/cutscene/descent.gd`, and
`DescentShot.apply(t)` drives `trees.apply(t)`. Tuned from probe shots (`tests/_probe_descent_shot.gd`).
Tests are in `tests/test_descent_trees.gd`.

- **Close:** 4 trees at 95-175 m (12.5-17.5 m tall), x 115 / 185 / 385 on the left and 1560 on the
  right. Each is its own mesh with 2 surfaces (green + tier snow, both inked) and leans
  `0.4 * (0.5 + 0.5 sin)` deg about `UP x wind` (the Storm's `wind_direction`), with a period of 4-6 s.
- **Mid:** the first pass spaced slots 8-11 m apart, and it read as a **picket fence** of lone spires
  at the horizon. Each ribbon now breaks into **spruce islands**: slots every ~4.5 m, kept only where
  two sines along the line agree, with trees 2.5-4 m apart across. You get tight dark clumps with
  snow between them, which reads as a stand. About 180 trees plus 8 strays. Placement skips any tree
  that would stand in front of a wreck and reach above its lower third (a screen-box check).
- **Far:** each clump is a run of overlapping five-sided pyramids (tips 9-17 m), with the gaps
  between clumps growing with distance. The shader is unshaded, and the lit/shadow split comes
  from the Sun node's direction. The storm's depth fog pales the clumps like the city, but they
  don't take the lightning flash.
- Seed: `tree_seed` 23. Tunables: `sway_degrees`, `sway_period_min/max`, `mid_spacing`,
  `far_spacing`.

## Revision 1 (2026-10-16)

The user saw it and said the trees looked too uniform, and the far ones needed to be a little darker.

| # | Question | Answer |
|---|---|---|
| 9 | Far darkness | The **far clumps are darker**: lit (0.1, 0.155, 0.14) and shadow (0.045, 0.07, 0.065), about half the old values. The fog still pales them with distance, but they hold more |
| 10 | Variety | **Mixed sizes and thicknesses.** Width is a share of height: 35% pencil (0.055-0.08), 45% ordinary (0.09-0.12) and 20% full and bushy (0.13-0.19). Mid heights are `lerp(7, 17, taper)` times 0.6-1.25, and 15% are saplings at 0.25-0.45x. Tier counts run 4-8. Close heights are now 19 / 10.5 / 13 / 21 m. Far tips are 6-20 m, with width following height. This replaces row 3's "2-3.5 m across" |
