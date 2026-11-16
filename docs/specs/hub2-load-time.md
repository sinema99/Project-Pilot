# hub2 load time

2026-11-14. Grilled, then built the same day. Not yet played.

Problem: ~30 s black screen starting hub2 (windowed probe: first frame 28 s). Cause was ~2,500
code-built dressing nodes (Hub2Prop / CargoContainer / Hub2PipeRun / Hub2Crane) building meshes in `_ready`.

## What was built
1. **`PropMeshCache`** (`scripts/props/prop_mesh_cache.gd`): each distinct mesh saved to
   `assets/hub2_props/*.res` on the first game run from the editor, loaded after. Wiped when the builder
   scripts change (md5 in `_version.txt`). Used by the source scene's nodes. 28 s -> 7 s.
2. **Baked dressing**: the editable tree moved to `scenes/hub2_dressing_src.tscn` (the generator's
   target now; its root is `Dressing`). `tools/bake_hub2_dressing.gd` writes `scenes/hub2_dressing.scn`:
   unique meshes merged into 12 m chunks per material, meshes used 3+ times (containers) as
   MultiMeshes per 40 m, box colliders in one StaticBody3D per 48 m, lamp pool list on the root
   (`Hub2DressingBaked.lamps`). `scenes/hub2.tscn` now instances the baked scene (4.6 KB, was 1.1 MB).
   First frame ~7 s -> ~4.9 s; the rest is the pilot, looks and first-frame shader work.

## Workflow
Edit the source scene or run `tools/gen_hub2_dressing.gd`, then run `tools/bake_hub2_dressing.gd`.
Tests (`test_hub2_dressing.gd`) read the source for props/rooms and check the baked scene's box count matches.

## Watch
- Culling is per chunk, not per prop; B yard views drew ~30% more triangles than before (others equal).
  Frame times could not be compared (GPU was busy); eyeball B and re-tune CELL / MM_CELL in the bake tool.
- Per-chunk visibility ranges are the prop's + a margin.
- Remaining load: ~3.8 s outside the dressing (Pilot9, looks, shaders). Not touched.
