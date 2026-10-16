# Habitat routes

**2026-09-30.** A traversal layer for the Mead habitat: a main route (the spine) from the causeway to
the tower's summit, with branches, dead ends and open areas, so the vista becomes a map to run. The
user cannot edit the habitat in the editor, so Claude builds it. Not yet built.

## Decisions (grilled 2026-09-30)

- **One spine with branches.** Causeway end → cab → concourse → rock bridge → tower base → exterior
  climb → summit platform. Branches come off it and rejoin or end in payoff spots.
- **A new `Routes` section** in `habitat.tscn`, generated like the other sections and separate from
  them, so it can be unticked to see the original map. Existing geometry is edited only where a route
  must physically attach.
- **The 40 m gap between the causeway and the main floor is out of scope.** The user bridges it.
- **Diegetic look, one accent.** Pipes and gantries for rails, bulkheads and housings for wall-runs,
  covered gantries for hallways, catwalks and balconies for platforms, all in the existing palette.
  Every runnable surface carries one shared accent: the green edge line already on the walkway.
- **Three open areas:** the concourse deck, the lake peninsula and island, and a plaza on top of the
  rock bridge before the tower. Each gets railings, low walls and vault-height blocks, not bare flats.
- **Tower climb is an exterior spiral** of wall-runs, rails and mantle ledges. The tower stays solid
  and its silhouette unchanged. The white tube on its right face is a mid-height rail.
- **Four stages, rest ledges.** A wide solid ledge about every 40 m. No respawn, no checkpoint, no
  kill plane: a fall costs at most one stage.
- **About six payoff branches**, each a payoff spot showing one mechanic (an overlook at a rail's end,
  a wall-run alcove topping out on a balcony over the lake, a sealed hallway with a vault at the far
  end). No pickups. Two off the concourse, one at the lake, one on the bridge approach, two on the tower.
- **Graded difficulty.** Early spine and open areas: every gap at most ~70% of the player's limit with
  wide landings. The tower tightens stage by stage. The dead-end branches are the hardest routes.

## What it is

`Routes` joins `Habitat.SECTIONS` as a `Node3D` child stored in `habitat.tscn`, built under it in the
same no-`owner` way as the rest. Each route piece is a small record: mechanic (`rail`, `wallrun`,
`vault`, `mantle`, `jump`, `walk`), start and end, gap, and difficulty grade. The generator builds the
geometry and colliders from the records and the audit reads the same records, so the two cannot drift.
Rails join the `rails` group and are `Path3D` rails the existing grind code accepts (gears 15/20 m/s).

The player's limits (jump height, double-jump reach, wall-run length and duration, dash distance,
vault depth ~0.7 m, mantle reach) are read from `pilot9.gd` and its resource at build time, not
hardcoded in this spec.

## Not in scope

- Bridging the causeway gap to the main floor.
- Collectibles, checkpoints, respawn, a kill plane, enemies.
- Hollowing the tower or any interior route.
- Changing the existing sections' look.

## Verification

1. **Geometry audit** (`tests/test_habitat_routes.gd`): every record's gap is checked against the
   measured limits, with the 70% rule for graded-easy pieces, and the tower stages are checked to
   tighten. Each rest ledge is solid, wide, and about 40 m apart. Every branch ends in a payoff spot and
   the spine reaches the summit. Nothing generated is owned, a rebuild does not stack colliders,
   and the `Routes` section can be unticked cleanly.
2. **Scripted real runs** (probe tools in the style of `tests/_probe_vault.gd`) drive the real pilot
   through the riskiest pieces: the first rail, one wall-run stretch, the first tower stage, and one
   dead-end branch. Each fails the test if the pilot does not arrive.
3. A screenshot probe from the cab vantage confirms the routes do not break the painting's framing.
4. Worklog entry when built. Not played until the user does.
