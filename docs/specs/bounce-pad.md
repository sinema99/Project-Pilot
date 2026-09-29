# bounce pad

**2026-09-20.** Three lime blockout boxes on the flat slab east of the jump grid's pillar
field. Land on one and it launches you through the same arc a floor jump already gives you.
No button, no charge, just contact.

## The problem

Everything the jump grid teaches is a measurement: this gap is 9 m, this ledge wants a double
jump. None of it is a verb the map itself performs on you. A bounce pad is the first piece of
geometry in the game that acts on the player rather than being measured by them, and it is
built as a companion to the ruler for exactly that reason - the open slab to the side of the
pillar field has been empty since `docs/specs/pilot9-jump-grid-platform.md` shipped it, and
this is the first thing to stand on it.

## What it is

`scripts/bounce_pad.gd` - `BouncePad`, a `@tool` box extending
`res://scripts/blockout_box.gd`, exactly the shape `interact_button.gd` and `sliding_door.gd`
already use: **path extends**, not `extends BlockoutBox`, because `blockout-boxes.md`'s global
class names go stale on the first run after a pull and a cross-file name reference turns that
run into a parse error rather than a rescan.

Three instances sit in `scenes/trial.tscn` under a new `BouncePads` node, 15 m apart, on the
open slab past the single-jump lanes' far edge and well clear of the pillar field and the
wall-run corridor row (both of which live in negative-Z, while the pads sit at Z = 10). They
are **not** children of `JumpGrid` - `jump_grid.gd::_clear()` frees every child it has on every
rebuild, owned or not, so anything hand-placed under it would vanish the next time the ruler
regenerates. `BouncePads` is a sibling of `JumpGrid` instead, at plain world coordinates.

Each pad is a plain `StaticBody3D` box, 2×2×2, coloured lime - a colour the blockout palette
had not used. `blockout-boxes.md` assigns warm to what you clear, cyan to what you grab, grey
to the instrument and teal to a blockout box; bounce is a new verb and gets a new colour rather
than borrowing one of those and lying about what it does.

## The launch

**`velocity.y = body.jump_velocity`, not a constant this file invents.** pilot9.gd already
derives `jump_velocity` from `jump_height` and `jump_time_to_apex` - see the note on that
property - and reusing it rather than picking a bounce height of its own is what keeps the
promise literal: a pilot9 retuned to jump higher bounces higher on the same pad, with nothing
here to update. `is_jumping` is set too, so the pad's launch reads to the AnimationTree exactly
like the floor jump it borrows the number from.

**Duck-typed on `velocity` and `jump_velocity`, not a class check.** `bounce(body)` only asks
whether the body carries those two properties - the same argument `interact_button.gd`'s
`activate()` duck-type makes, generalised from a method to a pair of properties. Nothing here
imports or names `pilot9.gd`.

**Not `_take_floor_jump()`.** That function also stands him up out of a crouch, ends a slide
and clears his coyote window - all of it *floor jump* behaviour that has nothing to do with
landing on a pad mid-air. Calling it would also mean reaching across a `_`-prefixed boundary
nothing else in the project crosses. Setting the two public properties gets the one thing the
spec actually promises - the same arc - without any of that.

## Detecting a landing

**A thin `Area3D` straddling the pad's own top face**, generated in `_ready()` without an
`owner`, exactly like `InteractButton`'s `Reach` and the jump grid's own geometry - what the
`.tscn` stores is the box's four inherited properties and no volume, so a duplicated pad
rebuilds its own trigger rather than carrying a stale one.

`LANDING_DEPTH` (0.3 m) is a compromise between two failures: an area flush with the surface
can sit exactly on the boundary and miss a landing that touches it (a floating-point wash), and
a deep one lets something already standing on the pad re-trigger without ever leaving. Straddling
the face rather than floating above it means the frame contact happens is the frame the trigger
overlaps, full stop.

**`body_entered`, not a per-frame check.** A launch sends the body up and out of the thin volume
immediately, so the next bounce only fires once it has actually left and come back down - no
debounce timer needed, because the geometry already enforces it.

**`accepts(body)` filters by `player` group membership**, the same call `InteractButton` makes
and for the same reason: `project.godot` has no `[layer_names]`, so every `StaticBody3D` on the
map - including the pad's own collider - shares layer 1 with the trigger, and the group check is
what stops a pad reacting to scenery sliding past it.

## The wobble

Cosmetic, and it never touches physics: `_apply_wobble()` scales only the child `MeshInstance3D`
pad-local frame, on landing. A decaying cosine squashes the mesh flat and wide on contact,
overshoots into a stretch on the way back, and settles to `Vector3.ONE` over `BOUNCE_ANIM_TIME`
(0.32 s) - driven from `_physics_process` so it starts on the same frame the launch does, not a
frame late off a `Tween`'s idle callback.

It only scales the *mesh*, never the box's own `scale`, which `blockout_box.gd` requires stay
`Vector3.ONE` - `shaders/metre_grid.gdshader` is a world-space triplanar grid and a scaled node's
normals stop being unit length, at which point its metre lines stop being metres. The collider
never moves either: what the wobble buys is a springy pop on the surface you are looking at,
never a change to what you are standing on.

## What this is not

Not tunable per pad yet. `LANDING_DEPTH`, `BOUNCE_ANIM_TIME` and `BOUNCE_SQUASH_AMOUNT` are
consts rather than `@export`s - every pad in the map is meant to feel identical, the way every
door in the map rises at the same rate. The day a pad needs its own bounce height is the day
this grows a `bounce_scale` export the way `sliding_door.gd` grew `open_distance`.

Not wired to the jump grid's own dials. `jump_velocity` is read off *whatever body lands on it*,
so a pad launches Setsuna at her own arc if she is ever added to the `player` group and never
launches anyone off a number pilot9.gd does not itself own.

## Known Gaps

- **Placement is by hand, not derived.** Unlike the jump grid ruler, nothing computes where the
  open slab actually is - the three positions in `trial.tscn` were worked out from
  `jump_grid.gd`'s own build-space math once, by hand, and will drift out of the empty area if
  the platform's layout constants ever move. They are ordinary `BlockoutBox`es, though, so
  dragging them back into the clear is a normal editor edit, not a script change.
- **No sound, no particle burst.** The wobble is the only feedback; a landing thump and a puff
  of dust are a follow-up pass, not part of this one.
- **A pad under EXIA does nothing.** `pilot9.gd::enter_vehicle()` disables his collision shape
  while aboard, so there is no body for the trigger to see - the same gap `button-door.md`
  already documents for buttons.
