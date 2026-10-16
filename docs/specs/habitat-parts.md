# Habitat part library

**2026-09-30.** The habitat's building blocks, each standing alone and laid out on a flat plane
next to the map so they can be copied into levels. The habitat itself (`habitat.gd`) is untouched.

- `scripts/habitat_part.gd` (`HabitatPart`, extends `Habitat`, `@tool`): one piece, chosen by the
  `kind` dropdown (changing it on a placed instance swaps the piece). The catalogue is `PARTS`;
  `layout()` places them. 39 parts in 8 categories. Every part stands on y = 0 at its habitat
  height (walkway deck 16, bridge 12..20, concourse 5) so pieces that met in the map still meet.
  Tower has `tower_height` (default 70, the map's is 164). Plants and backdrop are visual-only.
- `scenes/habitat_parts/<kind>.tscn`: one scene per part, drag into a level.
- `scripts/habitat_parts.gd` + `scenes/habitat_parts.tscn`: the library. Parts are real owned
  instances (move/copy/delete them in the scene tree); the floor, headings and name labels are
  generated. The floor has a pit under `water_tile`. Placed in `trial.tscn` at world (200, -16, 300),
  just past the habitat's side backdrop, at the habitat's ground height.
- Left out: the vault (one 520 m half-cylinder, not a piece) and the far park/hub ring.
- Differences from the map: causeway supports and the white dome are solid here.
- `tests/_gen_parts_library.gd` regenerates the scenes and overwrites any rearranging; afterwards
  strip the redundant `script =`/`kind =` lines it writes on the library's instances.
- Tests: `tests/test_habitat_parts.gd`. Screenshots: `tests/_probe_parts_shot.gd`.
