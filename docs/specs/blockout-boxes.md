# blockout boxes

**2026-09-11.** Boxes you can select, duplicate and resize in the Godot editor, laid out next
to the jump grid ruler and measured against it.

## The problem

`docs/specs/pilot9-jump-grid-platform.md` built a ruler you can stand next to: nine gap lanes,
ten pillars, every one of them generated from pilot9's exports. It answers "what does 9 m look
like from a takeoff edge". It cannot answer the next question, which is "does *this* jump, the
one I am actually putting in the map, feel good" — because there is nothing on that platform
you are allowed to move.

That is deliberate and it stays. Every box the ruler generates is added **without an `owner`**,
so none of it is serialised into `scenes/jump_grid.tscn`: a rebuild cannot leave stale geometry
behind, and the platform is always whatever `pilot9.tscn` currently says it is. The price is
that the ruler is untouchable. Select a lane in the editor and there is no node there to
select.

So the editable geometry is **new geometry**, standing beside the ruler rather than carved out
of it. The instrument keeps telling the truth; the map is separate data.

## What it is

Three pieces, and only the first two are load-bearing:

- `scripts/blockout_box.gd` — `BlockoutBox`, a `@tool StaticBody3D` with a `size` export. It
  regenerates its own mesh and collider from that one number, both to the same `Vector3`.
- `scripts/blockout.gd` — `Blockout`, the `@tool Node3D` the boxes hang off, with an **Add box**
  tool button that drops one in front of the editor camera and selects it.
- `addons/blockout/` — an editor plugin drawing five drag handles on the selected box. Pure
  sugar. Disable it and everything below still works through the scale gizmo and the inspector.

A `Blockout` node sits in `scenes/trial.tscn` at the world origin, a sibling of `JumpGrid`.
Directly in that scene and **not** instanced from a scene of its own, because an instanced
scene's children are not editable from the parent — and editing a box while unable to see the
ruler next to it defeats the whole point.

## The interactions

| | |
|---|---|
| select | click it in the viewport, like any mesh |
| duplicate | **Ctrl+D** — nothing custom; it is a normal node in a normal scene |
| move | the standard move gizmo. Turn on the editor's snap (magnet, 0.5 m) |
| resize | drag a face handle, or use the scale gizmo, or type a `size` in the inspector |
| delete | Delete |

All three resize routes end up writing the same `size` property, which is the point.

### Nothing is ever *scaled*

`size` changes the `BoxMesh` and the `BoxShape3D`; the node's `scale` stays exactly 1. This is
the same rule `scripts/jump_grid.gd` follows and it is not tidiness: `shaders/metre_grid.gdshader`
is a **world-space triplanar** grid, and a scaled node's normals come out non-unit and the
metre lines stop being metres. A box that no longer counts itself correctly is the same silent
lie the ruler exists to prevent.

The scale gizmo is still allowed, because it is the tool a person's hands already know. The
box watches its own `scale` and, **on mouse release**, folds it into `size` and snaps back to
1. On release and not per frame: the editor computes a drag from the transform it captured
when the drag began, so a node that rewrites its own scale mid-drag grows exponentially under
the cursor. Waiting for the button is one line and it cannot glitch.

### The origin is the footprint, on the floor

A box spans `y ∈ [0, size.y]` in its own local space — origin at the centre of its base, not
at the centre of the box. Put the node at 12 m and the box *stands* at 12 m.

This matches the two conventions already in the project: pilot9's body origin is at his soles
(`scenes/pilot9.tscn`), and the jump grid platform's origin is the start strip's walking
surface. Raising a box's height grows it upward from the ground it was placed on, which is
what a person means by "make it taller", and it means an inspector `position` can be read
straight off against a pillar's label.

The cost, stated plainly: there is no bottom-face handle. Five handles, not six — ±X, ±Z and
the top. The base is where you put it, and to move the base you move the node. A sixth handle
would also have landed exactly on top of the move gizmo's origin.

### Face handles move one face

Dragging the +X handle moves the +X face and leaves the −X face planted, adjusting `size` and
`position` together. Growing about the centre is the wrong default for level geometry: a box
aligned to something on one side should stay aligned to it.

Handle drags snap to the box's own `snap` (default **0.5 m**), with **Ctrl** held to drag free —
the same modifier the editor's own snapping uses. Snap is per-box and exported, so a box that
needs to sit at 0.1 m increments can say so without changing the others.

## Colour, and why these are obviously not the ruler

Blockout boxes carry the same `metre_grid` shader — they count themselves in metres, which is
the entire reason to build a map against a ruler — but in a distinct **teal**, against the
ruler's warm/cyan/grey palette. Warm is what you clear, cyan is what you grab, grey is the
instrument, teal is yours. One glance tells you which of the two things you are looking at.

Each box carries a billboard label reading its size, `4 x 1 x 6`, in the same style as the
ruler's lane captions. Off with `show_size_label` for a screenshot.

Unshaded and shadow-casting off, matching the ruler: `trial.tscn`'s `ApplyCelGround` targets
only `../TrainingV` and `../Mission1`, so blockout geometry stays outside the cel pipeline for
free. It is a dev instrument and should look like one.

## What persists

The generated mesh, collider and label are added **without an `owner`**, exactly like the
ruler's. What gets written into `scenes/trial.tscn` is one node per box carrying `size`,
`transform`, `tint` and `snap` — four properties and no geometry. A box rebuilds from those on
load, a duplicate rebuilds its own children rather than inheriting a copy, and there is no way
for stale geometry to accumulate in the scene file.

## What the test fences

`tests/test_blockout.gd`, headless.

- **Mesh and collider are the same box.** The thing you look at and the thing you land on
  cannot drift apart — the same invariant `tests/test_pilot9_jump_grid_platform.gd` reads the
  ruler's collision shapes for.
- **The origin is the base.** A box's collider spans 0 to `size.y`, never `-size.y/2` upward.
  Get this backwards and every box in every map sits half a box into the floor.
- **Scale is folded into size, never left on the node.** Bake a scale and `size` has it while
  `scale` is back to `Vector3.ONE`, or the metre grid quietly stops measuring metres.
- **Nothing generated carries an owner**, so nothing generated reaches the `.tscn`.
- **A duplicate is a box, not two boxes.** `duplicate()` gives one mesh and one collider at the
  right size, since duplicating is the main thing this is for.
- **The plugin scripts load.** Nothing else in the suite compiles the addon, and a parse error
  in a gizmo is invisible until the day you open the editor.

## What this is not

Not a level editor. There is no in-game edit mode, no save format of its own, no prefab
library, no ramps or cylinders — a box and its three dimensions. Anything past that is a map
tool, and the useful thing to learn first is whether building a real gap against the ruler is
enough to make a jump feel right.

## As built

Three places where the build had to decide something the spec above left open.

**The project's first editor plugin.** `project.godot` gains an `[editor_plugins]` section
enabling `res://addons/blockout/plugin.cfg`. `addons/real-controller` was vendored script and
never a plugin, so nothing was there before. `tests/test_blockout.gd` asserts the section says
so: an addon that is present and not enabled looks exactly like an addon that is broken.

**A new box lands on what the editor camera is pointed at, or eight metres out.** `add_box()`
fires a ray down the editor camera's forward and stands the box on the first surface it hits.
The editor does not step physics, so that query can come back empty even with the ruler's
colliders right there — in which case the box appears eight metres in front of the camera,
snapped, and you drag it down. Either way it arrives where you are looking, which is the point:
the ruler is parked ninety metres from world zero and a box dropped at the origin is a trip
across the map before every edit.

**The global class names are declared and never referenced.** `BlockoutBox` and `Blockout` are
registered so the boxes read as themselves in the scene tree and the Create Node dialog, but
`scripts/blockout.gd`, the gizmo and the test all reach the script through `preload` instead.
Godot's global class cache is stale exactly once — on the first run after pulling this, before
the editor has rescanned — and a cross-file reference to the name would make that run a parse
error rather than a rescan.
