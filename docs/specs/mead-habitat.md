# Mead habitat

**2026-09-30.** The inside of a space-station cylinder, built from a Syd Mead painting the user
gave (white ribbed vault, brown tower, lake, rock bridge, terraces, hydroponic rows, a control cab).
A blockout to judge the look before the user models the real thing in Blender. Generated, like the
pipe hall, and placed where it cannot touch anything.

## Decisions (grilled 2026-09-30)

- **Playable map with a vista.** Looking like the painting beats everything; no route is designed,
  the user decides how the player uses it. Every visible structure is solid.
- **Framed from the cab.** `CabVantage` (a `Marker3D`) is the spot where the composition lines up;
  probe screenshots were compared against the painting from there.
- **Two zones.** Playable: x +-100, z -130..135, colliders. Backdrop: out to z = -1100, never solid.
- **Bright and pale, real ceiling.** A ribbed half-cylinder vault overhead (no collider, unshaded,
  no shadow), a `ReflectionProbe` swapping the scene's blue sky ambient for warm off-white.
- **Water has no collider**, over a solid lakebed 6.5 m down. No respawn, no kill plane.
- **Stylised blockout plants.** Blob-canopy trees, cypress cones, palms, cabbage and corn rows. All
  MultiMesh, none solid.
- **No people.** The leaf emblem, the green walkway edge, the banners and the stripe fan stay.
- **The tower and the rock bridge into it are in the playable zone.**

## What it is

`scenes/habitat.tscn` is one node with `scripts/habitat.gd` (`Habitat`, `@tool`). The script
generates everything in `_ready()` with no `owner`, so `trial.tscn` stores one instanced node and a
transform. Placed at world (330, -16, 0), turned so local +Z points at world -X: the node sits
`DECK_Y` (16) below the floor so the cab walkway lands at world y = 0, and a 160 m causeway runs
from the cab back toward the main area (its end stops about 40 m short of the existing floor: the
gap is the user's to bridge). Move the map by dragging the node.

Local space: ground y = 0, walkway y = 16, the painting seen looking down -Z.

## The parts

- **Cab and walkway:** dark deck with green edge lines, white pier and low walls, the cab (roof,
  four pillars, side glass, slanted consoles, leaf emblem). Cab vantage z = 114, eye 1.7 m over the deck.
- **Fields:** left, six V-shaped hydroponic beds (white slopes at 18 degrees, dark grated channel,
  about 6k cabbages); right, a soil block of corn (about 8k stalks). A white retaining wall between
  the corn and the pier.
- **Left wing:** long white building with a dark window band, white belts and a rounded end, on pillars.
- **Concourse:** a 142 m deck across the middle distance with rails, machinery and pipes under it,
  and a lower service deck on the right.
- **Lake:** flat water plane (`shaders/habitat_water.gdshader`: unshaded, sky sheen at grazing angles,
  hard-edged ripples, a glare patch around the tower), banks, an island with a lone tree, a peninsula
  with a sandy point, a white ramp from the bank out to the tower's foot.
- **Left terraces:** six cream rakes tilted 12 degrees, climbing to the left, green strips, cypress.
- **Bridge:** a dark rock slab (y 12..20) from a cream cliff on the left into the tower's left face,
  broken underside, hanging green, trees on top.
- **Tower:** brown column (20 x 16, top y 156) with a paler inset panel, a pale waterfall down its
  left face, and a flared base: two quarter-round sweeps (front and right, radius 26) with trimesh
  colliders. A 6.5 m white tube leaves the tower's right face and runs away out of the playable zone.
- **Backdrop:** far ground with green patches, a park with a pond and white bridge, scattered white
  blocks, terraced hillsides climbing both sides (cream rakes, green strips), a stadium bowl on the
  right, domes, far trees, a hub ring at the far end, all through MultiMesh.
- **Vault:** half cylinder, radius 260, nine panel bands (slate at the edges, cream/white between)
  with thin seam lines, vertex-coloured, fading to haze with distance. It is open at the far end, so
  the normal sky shows through as the painting's bright opening.

## Built

Departures from the plan: DECK_Y went 12 -> 26 -> 16 and the concourse, wing and service deck were
lowered to match, because from a low deck the concourse and hedge hid the lake entirely. The bridge
and tower were moved 36 m back (z -58) for the same reason, and the tower moved from x 56 to x 40
so it sits about 13 degrees right of centre, where it is in the painting. The one-sided tower flare
uses a plain lit material, since the cel shader's outline pass inks a single-sided ribbon solid
black. A `ReflectionProbe` ambient was added (not in the original list) because the scene's cool sky
ambient greyed every white.

## Not done

- Any person, or any motion (no moving crowd, no flowing water beyond the shader).
- The painting's paint texture, glass reflections, the cab's transparent front.
- A real connection to the existing world: the causeway ends short of it.
- Shadows past 80 m (the scene's Sun limit): far geometry is unshadowed.
- Collision on the backdrop and on the vault, deliberately.

## Verification

`tests/test_habitat.gd`: the cab deck is solid at `DECK_Y` under the vantage, in the cab and at the
causeway's end; the vantage marker is at eye height; the water has no physics body and the lake bed
is solid with nothing solid at the water line; the bridge slab meets the tower and the tower is solid
to the vault; plants are batched and never add a collider; nothing generated is owned; a rebuild does
not stack colliders. `tests/_probe_habitat_shot.gd` (windowed) saves screenshots from the cab and
five other vantage points. Not yet played.

## Editing the map in the editor (2026-09-30)

The map is split into 13 sections (`Habitat.SECTIONS`: Ground, Lake, WalkwayAndCab, Fields,
LeftBuilding, Concourse, LeftTerraces, Bridge, Tower, Plants, Details, Backdrop, Vault). Each is a
real `Node3D` child stored in `scenes/habitat.tscn`; the generated geometry and colliders are built
under it, so dragging/rotating a section moves them with it. Unticking a section's visibility
removes it (auto rebuild). Open `habitat.tscn` itself to edit: moves save into it for every
instance. Sections are whole pieces, not individual trees/boxes; for finer control use the part
library (`habitat-parts.md`). The scatter seed and build order are unchanged.
