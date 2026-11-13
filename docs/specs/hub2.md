# hub2 map

2026-11-13. Grilled with the user, then built the same day.

- `assets/hub2.glb` is `Documents/HUB2.glb` (2 meshes, no materials; imported through `scripts/map_import.gd`, so every mesh is solid).
- `scenes/hub2.tscn`: pilot9 only (no mech, no speeder, no switcher, no test fixtures), trial's AIRFRAME look rigs, `MissionMap` root. Run it with F6; `trial.tscn` stays the main scene.
- Spawn: a `spawn` Node3D added under `Map` at (158, 98.2, -67), on the platform block at the end of the corridor beside the big cylinder, facing -X (the corridor). A `spawn` empty in the .glb would override it (rename or delete this one then).
- Falling: kill height -30, back on the spawn. No checkpoints.
- Scale gotcha: the glb's `Cylinder.005` node is scaled 11 x 32 x 11, so the big structure is ~1 km across and 850 m tall. The platform surfaces are 20-60 m blocks.
- Tests: `tests/test_hub2.gd`. Throwaway probes: `tests/_probe_hub2_survey.gd` (windowed, top-down/oblique shots + pixel pick), `tests/_probe_hub2_rays.gd` (down-rays for surface heights).
