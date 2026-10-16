# Spec: Sinestro2 parked next to the pilot in Ichi

> **Status:** specced and built 2026-10-14. See docs/worklog/2026-10-14.md.
> **Scene:** `scenes/operation_ichi.tscn` (instanced by `Ichi.tscn`). **New:**
> `assets/sinestro2.glb`, `scenes/sinestro2_parked.tscn`, `scripts/parked_ship.gd`.
> **Touches:** `scripts/rendering/storm.gd` (roof bake also takes boxes).

## The ask

"put the new ship in ichi scene ... next to pilot, so it reads as, pilot just landed and got out
of his ship. first we need to turn pilot a 180 ... both animations holding on the 30th frame ...
the cockpit is open and the landing gear is down ... put the ship in a semi flat area, and make it
moveable in editor."

## Decisions (grilled 2026-10-14)

| # | Question | Answer |
|---|---|---|
| 1 | First export had no animations | Re-exported; three clips came through |
| 2 | Third clip `Action` | A third landing-gear leg: held on its last frame too |
| 3 | Scale | 1.0, Blender size (not the cutscene's 0.68) |
| 4 | Where | Beside him, on his left as the spawn camera sees it |
| 5 | Solid? | Simple box collision, so he can parkour onto it |
| 6 | Shading | Character cel look, same material as the pilot |
| 7 | Snow | The ship shelters snow (the roof bake sees it) |

## The asset

`C:\Users\panac\Documents\Sinestro2.glb` -> `assets/sinestro2.glb`, default import settings. Three
clips, each authored on its own armature, all 0.5 s (30 frames at 60 fps):

| Clip | Armature | What it does |
|---|---|---|
| `cockpit_open` | `Armature_001` | Nose cone (`Cube_027`) slides 1.06 m forward |
| `landingear` | `Armature_002` | Wings' struts (`Cube_021`) swing down to the ground |
| `Action` | `Armature_003` | Centre skid (`Cube_023`) drops |

**Gotcha:** Godot's importer gives every clip tracks for *all three* armatures (the ones the clip
does not animate hold rest). So playing the three clips one after another leaves only the last
one's pose. The hold therefore copies each clip's last key onto its own armature only - see
`ParkedShip.hold`.

Posed, the gear feet sit 1.36 m below the ship's origin; nose is +Z.

## The pilot turn

Not a rotation of the `Pilot9` root: pilot9.gd writes `character.rotation.y` as a *world* yaw and
`CameraPivot` is `top_level`, so a turned root would point his model the wrong way the first time
he moves. Instead the scene overrides the two children he actually faces with: `character` yaw 0
(was PI) and `CameraPivot` yaw PI (was 0). He and the camera now look down +Z, so his left is +X.

## Placement

The ground straight to his left is a 12-15 degree hillside (it falls ~2.2 m across the 9.9 m gear
track). The flat bit nearby is a crest ~2 m high running ahead-left. Raycast search over position
and yaw, keeping every part of the ship >= 3.5 m from the spawn: best is centre (7, 10), yaw -60
(nose angled across in front of him, three-quarter to the camera), feet within 0.27 m of each
other. Origin y = strut ground + 1.36, so the struts stand on the ground and the skid's front
sinks ~0.25 m into a bump in the snow.

It is one node, `Sinestro2` - drag or turn it in the editor and the mesh, the collision and the
snow shelter all go with it. Nothing snaps it to the ground; that is the user's to do by eye.

## Holding the pose

`scripts/parked_ship.gd` (`class_name ParkedShip`, `@tool`) on the scene root. `hold` maps clip
-> armature node; `_ready()` writes each clip's last key onto that armature's bones. `@tool` so
the editor shows the open cockpit and lowered gear too. Nothing plays; the AnimationPlayer is
left alone.

## Collision

The root is a `StaticBody3D`. Boxes, ship space, posed: body + engine, tail fin, wing, two engine
pods, keel bar, nose cone, skid. The thin angled struts get none.

## Snow shelter

The storm's roof bake only drew meshes with a `StaticBody3D` child. It now also draws every
`CollisionShape3D` with a `BoxShape3D` in the `storm_roof` group as a box. The ship's boxes are
in that group. Baked once at load, so moving the ship in the editor is fine.

## Shading

`ApplyCelPilot9` gets the ship as a second target: `pilot_cel_character.tres`,
`derive_from_surfaces`, so it keeps its Blender colours (`ship_main`, `ship_sec`, `ship_sec2`,
`ship_tre`, `cockpit`) in two cel tones with the outline, like the pilot beside it.

## Opening shot (2026-10-14)

The user moved the ship to (6.16, 3.0, 13.14) and asked for the scene to open on a screenshot of
the pilot looking at it. The earlier 180-degree child overrides had dropped out of the scene, so
the spawn was redone the same way (children, not root):

- `Pilot9` at (-3.82, 2.6, 12.57): 10 m from the ship's origin on a bearing 25 degrees off its
  nose, so he sees its front-left quarter - nose and keel running off the left of frame, fin over
  his head, the striped boom and blue pod to the right, the building far right.
- `character` yaw 1.304 rad (turned 12 degrees right of the ship's centre so it sits left of
  frame, like the reference); `CameraPivot` yaw = that + PI.
- Found by orbiting the camera round the ship at 8 bearings and matching against the user's
  screenshot. `tests/_probe_ichi_spawn_shot.gd` saves the opening frame.

If the ship is moved again, the spawn has to follow: recompute from the ship's nose
(`global_basis.z`) with the same 25 degree / 10 m / 12 degree numbers.
