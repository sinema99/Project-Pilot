# Pipe hall

**2026-09-30.** A dark industrial chasm built from a reference painting: giant pipes, steel
catwalks, caged lamps, cables overhead. Built as a generated scene, placed where the user circled
in the editor.

## What it is

`scenes/pipe_hall.tscn` is one node with `scripts/pipe_hall.gd` (`PipeHall`, `@tool`). The script
generates everything in `_ready()` and adds every child **without an `owner`**, the way
`jump_grid.gd` does, so `trial.tscn` stores one instanced node and a transform. `PipeHall` in
`trial.tscn` sits at world (-99, 0, 84): just past the jump grid slab's +Z edge (z = 25), in the
middle of its X range. Moving the hall is dragging that node.

Local space: origin at the centre of the floor, walking surface y = 0 (the slab's height), hall
96 x 56 x 46 m, door in the -Z wall, a 32 m causeway from the door to the slab.

## The parts

- **Solid:** floor, walls, roof, causeway, catwalk A (y 14, long central span), catwalk B (y 7,
  west), platform C (y 20, east), three ramps (floor to B, B to A, A to C), the big floor pipe
  (r 5, run across its top), two elbows (left r 4.2, right r 3.6), two slim risers for wall-running,
  two support columns. Pipe colliders are one cylinder per segment of the swept path.
- **Dressing, no collider:** railings, toe plates, braces, wall ribs, seam bands, bolt flanges (one
  MultiMesh), ceiling girders, 18 bundles of sagging cables, the sealed blast door at the east end.
- **Grind rail:** one `Rail` from platform C down across the hall to catwalk A (real `Rail` node,
  cyan blockout tube: it is the route marker).
- **Light:** ~20 warm omni lamps (no shadows), five cool spotlights with shadows and a faint
  additive shaft each. A `ReflectionProbe` over the hall replaces the scene's sky ambient with a
  dark blue, which is what turns a pale room into a cavern.
- **Look:** `cel_ground.tres` duplicated per colour. Cold blue steel, yellow rails, amber lamps.

## Not done

- The painting's mottled rust and peeling paint: flat cel colours only.
- Volumetric fog: the Environment is global and the fog settings belong to the whole scene.
- Hand-placed clutter. The hall is big pieces and repetition.

## Verification

`tests/test_pipe_hall.gd`: causeway meets the slab at y = 0, the three decks are solid, the rail
joins the `rails` group, nothing generated is owned, a rebuild does not stack colliders.
`tests/_probe_hall_shot.gd` (windowed) saves screenshots from five vantage points.
