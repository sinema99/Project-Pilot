# hub2 crane control room (room B east wall)

2026-11-15. Grilled with the user (7 questions). Specced only, NOT built (user: "spec, dont build").
Builds on [hub2.md](hub2.md), [hub2-storage.md](hub2-storage.md), [hub2-industrial.md](hub2-industrial.md),
[interaction-panel.md](interaction-panel.md).

**BUILT 2026-11-15** (user: "build this"): see "Built" at the end.

Ask: turn the long box hanging off B's east wall into a crane control room: PS1 low-poly computer
panels for the cranes and other equipment, the window polys modelled in Blender turned to glass, and a
door in the hallway (the room's only entrance) that opens with F. Everything goes INSIDE the room, on
its floor and walls - never on the box's roof. The crane runway that currently clips through the room
floor must go.

## Facts (from assets/hub2.glb, world space, Map scale 0.6)

- The room is the box called "B balcony" in [hub2-final-pass.md](hub2-final-pass.md): mesh `Cylinder.005`
  (one surface, no materials). Interior **x -72.4..-61.8, z -83.1..-22.3, floor y 43.56, ceiling 50.8**
  (61 m long, ~10 m deep, 7.2 m tall). Interior faces point inward.
- West side is the slanted nose: lower slant x -69.9 (floor) -> -72.4 (y 47.2), upper slant back to
  -69.9 at the ceiling. Normals (0.83, +/-0.56, 0).
- **Windows = 6 inset quads** on the slants (the Blender selection), inner edges at x -72.1 / -70.1,
  each slant split into z **-82.7..-44.7** (38 m), **-44.0..-36.6** (7.4 m), **-35.9..-22.7** (13.2 m).
  Lower panes y 43.9..46.9, upper panes y 47.5..50.5. Find the pane tris by position + normal at build
  time (inside x -72.2..-70.0 and the z ranges above), not by index.
- **Only entrance:** a gap in the east wall (x -61.8) at **z -44.3..-36.2, 8 m wide x 7.2 m tall**,
  a 3.4 m stub (x -61.8..-58.4), then E's south cross corridor running east to x -20.3 at the same
  floor height.
- **Clipping crane:** `BridgeCrane1` in `tools/gen_hub2_dressing.gd` `_room_b()` sits at x -87.5 with
  span 42, so its east runway is at **x -66.5, rail top y 43.78** (20 cm above the room floor), running
  z -144.5..39.5 straight through the room, columns every 23 m underneath. That is the blue bar on the
  room floor and the red rail on the box in the user's screenshots.

## Decisions

1. **Whole room, zoned** (61 m), south to north:
   1. **Equipment bay, z -83..-70:** 6 server/relay racks along the east wall (blinking LEDs), a breaker
      panel, cable trays overhead feeding the desks.
   2. **Main crane desk, z -70..-46**, behind the 38 m pane: one long tilted operator console along the
      windows, two stations (one per crane). Each: 3 CRT monitors, joystick pair, button grid, raised
      operator chair, "CRANE 1" / "CRANE 2" plate.
   3. **Entrance, z -46..-34:** walk-in path kept clear; locker pair + fire extinguisher by the door.
   4. **Supervisor area, z -34..-22:** lit yard-map wall board (block grid of B with crane positions),
      comms desk (radio rack + handset), supervisor desk (one monitor, papers), filing cabinet.
   5. Overhead fluorescent strips, mostly dead, 2-3 still lit.
   Everything stands on the y 43.56 floor or hangs on the inner walls/ceiling. Nothing on the roof.
   Layout proposed in question 7; the user answered "spec, dont build" - treat it as accepted, adjust
   if they say otherwise.
2. **Crane fix:** `BridgeCrane1` span **42 -> 26 m**, centre kept at x -87.5, so its east runway moves
   to **x -74.5**, just outside the window nose (operators look down onto the rail they run). Fix the
   column obstacle AABBs (they follow `c[1]`), the hook/spreader positions if they depend on span,
   then regenerate + re-bake B's dressing so containers re-pack around the moved columns.
3. **Glass:** cut the 6 pane quads out of the map mesh AND its `Hub2Wear` bake, put a separate glass mesh
   in their place. Intact (no cracks), dirty PS1 glass: flat cold green-grey tint ~30% opacity,
   height-based grime (dirtier at the bottom edge) + a few streaks in 15-bit dither, one hard fake
   reflection band. Same look from both sides. **Collision stays solid** (no walking out).
4. **Door:** a `Hub2Piece` BULKHEAD fills the 8 x 7.2 m opening at the corridor end of the stub
   (**x -58.4**), so the stub becomes a small entry inside the room. PS1 steel panels, hazard trim round
   the door, a small window strip above it. One person door **1.8 x 2.6 m**.
5. **Door behaviour:** new **`Hub2Door.Type.SLIDE`**: single leaf slides sideways into the bulkhead in
   ~0.8 s with a small jolt at each end. Same rules as the other types: F toggles via the shared
   InteractionPrompt (OPEN / CLOSE), stays where left, starts closed, AnimatableBody3D pushes.
   Keypad box beside it: light red when shut, green when open. No lock, no power puzzle, no auto-close.
6. **Consoles: powered, visual only.** Emergency power: screens glow dim amber/green with drawn low-res
   content (crane status, yard grid, scrolling text), blinking LEDs, one screen flashing an alarm. No
   interaction, no crane driving (possible later grill). Screen glow lights the desks a little; the room
   reads as the one lit box on the wall from the yard.
7. **Style:** code-built PS1 low poly in the existing prop kit (PropKit / Hub2Piece / PropMeshCache,
   same rust/wear palette); screens/boards drawn in code like `hub2_decal_atlas.gd`.

## Build notes

- Live in the scene vs baked: follow the dressing pipeline (`gen_hub2_dressing.gd` -> `bake_hub2_dressing.gd`);
  doors stay live Hub2Door nodes (the bake already copies them).
- Re-run `tools/bake_hub2_wear.gd` after cutting the panes (its decals must not land on glass).
- Check `tests/test_hub2.gd`; add: no crane geometry inside the room AABB, 6 glass panes present,
  pane collision solid, SLIDE door toggles on interact. Probe shots: from inside toward the yard, from
  the yard up at the box, the door from the corridor. Windowed probes: set `Inventory.persist = false`.

## Built (2026-11-15)

- **Crane:** `tools/gen_hub2_dressing.gd` BridgeCrane1 span 42 -> 26 (east runway x -74.5); room B regenerated and
  `tools/bake_hub2_dressing.gd` re-run. (The generator reshuffles B's random scatter a little.)
- **`Hub2ControlRoom`** (`scripts/props/hub2_control_room.gd`, node `ControlRoom` in `scenes/hub2.tscn`, after Hub2Wear,
  all built in code, nothing saved): cuts the pane triangles out of the map's visual meshes + decals at runtime
  (`pane_row()`: |normal.x| > 0.7, bbox inside the two y bands) and builds `Glass` from exactly those triangles
  (`shaders/hub2_glass.gdshader`, casts shadow so the room stays dim). Collision untouched = solid.
- Furniture in one PropKit mesh + box colliders: 6 racks + breaker panel + cable trays (south), 22 m console with 2
  stations (3 CRTs, joystick pair, button grid, levers, hanging CRANE 1 / 2 plates) + 2 raised chairs + yard / power /
  alarm (blinking) screens, lockers + extinguisher + hazard strip at the entrance, yard-map board, supervisor and comms
  desks, filing cabinet, 9 ceiling strips (3 lit, one flickers). Screens are drawn images (`Hub2ControlRoomScreens`) on
  `shaders/hub2_screen.gdshader` (scanlines, blink, flicker). 7 dim omni lights, no shadows; screen / strip pools go into
  `Hub2LampPools.fixed`.
- **Door:** steel bulkhead at x -58.4 with hazard trim, window strip, "CRANE CONTROL" sign; `Hub2Door.Type.SLIDE`
  (new): 2.1 x 2.7 leaf slides 0.8 s toward -Z with a jolt, F toggles, red / green keypad lamp on both faces.
- Tests in `tests/test_hub2.gd` (runway outside the box, panes gone from visuals but still in collision, door slides,
  furnished). Probe: `tests/_probe_control_room.gd`. test_hub2_dressing.gd has 17 failures that were already there
  (hand-placed D_* groups / doors missing from the source scene since the final pass was reverted).
- Not played. Pipe router was not re-run after the crane move.
