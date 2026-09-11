# button and door

**2026-09-11.** A button you press and a door that slides up out of the way, built as two
scripts on two blockout boxes so the pair can be duplicated across a map with Ctrl+D and
nothing to re-wire.

## The problem

`docs/specs/blockout-boxes.md` gave the map boxes you can select, resize and duplicate. Every
one of them is inert. There is no way to build a gate, and therefore no way to blockout a room
whose shape changes — which is most of what a level does.

The requirement is not "a door". It is **a door you can paste**. One button and one door is a
morning's work in any engine; the thing worth designing is the pair surviving a duplicate
without a designer re-wiring a NodePath every time, because a mechanic that costs two minutes
of fiddling per copy is a mechanic that gets used three times and then avoided.

## What it is

```
Blockout
└── DoorButton1          Node3D, no script - the handle you grab and Ctrl+D
    ├── Button           BlockoutBox + interact_button.gd,  target = ^"../Door"
    │   └── Area3D       generated at runtime, no owner
    └── Door             BlockoutBox + sliding_door.gd
```

Walk into the button's reach, a prompt reads `[F] OPEN`, press it: the door rises by its own
height at 3 m/s and stays up. The button goes dark and dead.

- `scripts/interact_button.gd` — `InteractButton`, a `@tool` box that watches an Area3D and
  calls `activate()` on whatever `target` points at.
- `scripts/sliding_door.gd` — `SlidingDoor`, a `@tool` box with `activate()` and four states.
- `scripts/ui/interaction_prompt.gd` + `scenes/ui/interaction_prompt.tscn` — one prompt row,
  shared by every button in the scene.

Both box scripts use **path extends** — `extends "res://scripts/blockout_box.gd"` — rather
than naming `BlockoutBox`. blockout-boxes.md declares the global class names and never
references them, because Godot's global class cache is stale exactly once, on the first run
after somebody pulls, and a cross-file name reference turns that run into a parse error rather
than a rescan. Path extends holds the same line while still inheriting the whole box.

Both are `@tool`. `@tool` is per-script and **not inherited**: a door script without it would
leave `_ready()` unrun in the editor, and the box would never build its mesh or collider —
you would be looking at an empty spot where the door should be. Their `_ready()` therefore
also runs in-editor, so the Area3D generation and `_physics_process` carry
`Engine.is_editor_hint()` guards.

## Why a wrapper, and not a scene

The obvious answer to "I want to paste this" is `door_button.tscn`. It is the wrong one here
for the reason blockout-boxes.md already gave for the `Blockout` node itself: an instanced
scene's children are not editable from the parent. A door is a wall sized to plug one specific
gap — resizing it is the *main* thing you do to it — and an instance would put Editable
Children between you and the face handles on every copy.

So the unit is a plain `Node3D` holding two loose boxes. Ctrl+D on the wrapper copies
everything and the boxes stay as editable as any other box in the scene.

### The naming rule that makes paste work

Godot uniquifies node names **among siblings only**. Two wrappers can each hold a child called
`Door`; duplicating `DoorButton1` gives `DoorButton2` whose children are still `Button` and
`Door`, verbatim.

That is the entire trick, and it only works if the names *inside* the wrapper are generic.
`interact_button.gd` declares `@export var target: NodePath = ^"../Door"` and a pasted copy
resolves it to its own door with no editing.

Name them `button1` / `door1` instead and the first pair works and every paste silently
misbehaves: the copy is `door2`, the copied button still says `../door1`, and pressing it opens
the original door somewhere else in the map. **Identity goes on the wrapper** —
`DoorButton1`, `GateToUpperLedge` — never on the children.

## The door

**Travel defaults to the door's own `size.y`.** A box's origin is the centre of its base and it
spans `y ∈ [0, size.y]`, so rising by exactly `size.y` puts its base where its top was and the
gap is fully clear, by construction, at any size. Drag the face handles until the door plugs
the hole and the travel has already followed. `open_distance` overrides it when nonzero.

An explicit default would mean two numbers to keep in sync per door, with a failure mode — a
door that opens 80% — that looks completely fine in the editor and blocks the player.

**`open_speed` is metres per second (3.0), not a duration.** With travel derived from `size.y`,
a fixed duration would make a 6 m door rise twice as fast as a 3 m one. A fixed rate means
every door in the game rises at the same speed and takes as long as it is tall. That matters
here specifically: pilot9 has a slide, and *can I get under that* is a skill a player can only
learn if the rate is a constant. Per-door-size rates make it unlearnable.

**Linear, no easing**, for the same reason — an eased rise has no single rate to internalise.
If the stop at the top reads cheap once it is being played, a short ease-out over the last few
centimetres is a one-line tuning change and belongs in the pass after the first playtest.

**`CLOSED` is wherever you left the node**, captured in `_ready()`. You place the door plugging
the gap; open is derived from that. No coordinate is ever typed.

### It stays a StaticBody3D

`BlockoutBox extends StaticBody3D`, and a `StaticBody3D` whose `position` is written each frame
teleports rather than sweeps. Godot's answer is `AnimatableBody3D`, which a `CharacterBody3D`
stands on and is carried by — but it is a *sibling* of `StaticBody3D`, not a descendant, so it
cannot be reached by inheriting from `blockout_box.gd`.

Getting it would mean either hand-building the door's mesh and collider (losing `size`, the
face handles, the metre grid and the label — undoing the entire reason these are boxes), or
copying `blockout_box.gd` wholesale into a `door_box.gd`. The second is worse than it sounds:
it duplicates `_bake_scale()`, the single subtlest function in the blockout system, and the day
one copy is fixed the other will not be remembered.

So it stays static, with two consequences accepted outright:

- **A player standing on top of a rising door is not carried up.** They hang, then fall.
- **A player wedged against a moving face is not pushed**, but intersected and depenetrated by
  their own next `move_and_slide()`.

Both are inert *for this motion*, because the door retracts **upward, away from the player's
path**. Nobody is pressed against the face it travels along. "Player on top" needs a door with
a walkable top face and no lintel above it, which is a door you would notice building.

**This is the constraint that keeps the door one-shot** — see below.

**Moved in `_physics_process`, not a `Tween`.** A Tween runs on the idle frame, so the
collider's position and the physics step drift by up to a frame, and pilot9 already reads
`is_on_floor()` and `get_floor_normal()` one frame late in several places. Integrating in the
physics step costs nothing and keeps the collider honest.

### One-shot, with the states written anyway

Press once, opens, stays open. The button goes dead and stops prompting — a prompt offering an
action that does nothing is worse than no prompt.

It is built as `CLOSED / OPENING / OPEN / CLOSING` with an exported
`auto_close_after: float = 0.0` (0 means never), because the states cost nothing to write now
and everything to retrofit: a door that can close is a door that can be interrupted mid-travel,
and *that* is the fiddly case, not the closing. `CLOSING → OPENING` reverses from wherever the
door is rather than snapping or finishing first.

**The default stays never-closes for a physics reason, not a design one.** A closing door
reverses the argument above — it descends along the exact path the player is standing in,
does not sweep, and does not push, so pilot9 is intersected and then shoved somewhere he did
not choose. Setting `auto_close_after` nonzero is the day `AnimatableBody3D` comes back onto
the table, and that should be a visible trigger rather than a surprise.

## The button

**An Area3D, generated in `_ready()` without an `owner`**, exactly like the box's own mesh and
collider and the ruler's geometry. What the `.tscn` stores is a button's four box properties
and no volume; a duplicate rebuilds its own, and stale volumes cannot accumulate.

**Sized from the button's own `size`, inflated by `reach` (1.5 m) on every axis.** Resize the
button and the reach follows — the same derivation that makes the door's travel work.

The cost, plainly: a runtime-generated volume is **invisible in the editor**. You place a
button and cannot see how close you must stand. Derived-from-the-visible-box plus one number is
predictable enough to live with, and *Debug → Visible Collision Shapes* shows it in a running
game. An editor gizmo would mean growing `addons/blockout/`, which its own spec calls "pure
sugar", for a mechanic that is not blockout.

**It accepts bodies by `player` group membership, not by duck-typing.** This deviates from
`mech.gd`, deliberately. `mech.gd` tests `has_method("enter_vehicle")` because it is about to
*call* that method — the duck-type and the contract are the same object. The button calls
nothing on the player, so duck-typing would mean inventing a marker method purely to be looked
for. `get_first_node_in_group(&"player")` is the convention `docs/specs/ui-shell.md` already
established and `scripts/ui/tabs/tab_abilities.gd` already uses.

The filter is load-bearing, not cosmetic: `project.godot` has no `[layer_names]` section, so
every body in the project is on layer 1 and the Area3D reports **every `StaticBody3D` it
overlaps** — including the blockout box the button is mounted on. Without the group check the
button would be tracking scenery.

**Consequence: Setsuna does not press buttons.** Only `pilot9.tscn`'s `Character` carries the
group. Adding it to `player.tscn` is one line if it is ever wanted; nothing instances her in
`trial.tscn`.

**Piloting EXIA past a button does nothing, for free.** `pilot9.gd::enter_vehicle()` sets
`collision_shape.disabled = true`, so while he is aboard there is no body to detect, the prompt
never arms, and there is nothing to press. No guard was written for this.

**What it calls is duck-typed**: `if node.has_method("activate"): node.activate()`.
`interact_button.gd` never names `sliding_door.gd`. That is not ceremony — it means the button
drives a lift, a bridge or a light written later with no edit to the button, and it dodges the
stale-class-cache problem the same way everything else here does.

**A single `NodePath`, not an array.** *Many buttons → one door* already works: point both at
the same `Door`, which is the common case (a switch either side of a gate). *One button → many
doors* is rarer, and an `Array[NodePath]` costs the clean single-path default that makes paste
work. If it is ever needed the honest fix is a third script — a relay node with `activate()`
that forwards to a list — which composes with both files and changes neither.

**An unresolvable `target` pushes a warning once on `_ready()` and the button is inert** — no
prompt, no crash. A misconfigured paste should be visible in the editor output and dead in the
game, not a null dereference mid-playtest.

## Input

A new `interact` action: **F**, **E**, and gamepad **Y** (button_index 3).

`F` because that is what `mech.gd` already uses and hands should not relearn it. `E` because it
is what a player reaching for an interact key tries first — it collides with `tab_next` only
nominally, since the shell pauses the tree and nothing in the world is listening when a menu is
up. The pad binding matters most: `mech.gd`'s `F` is a raw `event.keycode == KEY_F` with **no
joypad event at all**, so EXIA is currently unboardable on a controller, and a copy-pasteable
door mechanic that is keyboard-only is one that has to be revisited the first time a pad is
picked up.

This is the project's first *movement-adjacent* InputMap action; `ui-shell.md` lists migrating
the rest as out of scope and that stays true.

### Both handlers consume

`interact` includes `F`, so a button placed inside EXIA's 9 m interaction box would otherwise
fire both: the door opens *and* pilot9 climbs in. Neither script consumed the event.

Both now call `get_viewport().set_input_as_handled()`, so exactly one thing happens. That is
the whole of the guarantee — `_unhandled_input` runs in reverse scene-tree order, so "first"
means "lower in the tree", which is not a rule a level designer can reason about. It ensures
one action, not a predictable one. See Known Gaps.

## The prompt

**One `InteractionPrompt` per scene, found by group, auto-created if absent.**

The tempting design is a `CanvasLayer` inside the wrapper, copied from `mech.tscn` — fully
self-contained, pastes perfectly. It is the trap, precisely because of the requirement. Paste
two buttons within sight of each other — a door with a switch on each side, an obvious thing to
build — and two `CenterContainer`s anchored to the identical screen position draw over each
other. That is not an edge case; it is the second thing anybody builds with this.

Putting it on the `UI` autoload was the other candidate and was rejected: that autoload is a
**screen stack** whose pure `resolve()` is asserted precisely because it is the part that can
be silently wrong, and bolting an unrelated world-space HUD concern onto the one object in the
project with a clean single responsibility muddies it. (`ui-shell.md`'s "No new HUD" is
superseded either way — there is now something to draw.)

So: a group lookup, the same shape and the same null discipline as ui-shell.md's `&"player"`.
**The first button that looks for the prompt and finds none instantiates one onto the scene
root without an `owner`** — the same trick the boxes and the ruler already use. Paste a door
into any scene and the UI arrives with it, with nothing serialised and nothing to remember.

**Nearest button wins** when several are in range, re-evaluated as the player moves. "Last
entered" is cheaper and produces a prompt that is stale the moment you walk past something.

**The keycap reads its key from the InputMap**, not a hardcoded `"F"`, so rebinding `interact`
cannot leave it lying.

**The text is `"OPEN"`.** One word, uppercase, matching `mech.gd`'s `"PILOT"` / `"EXIT"` and
ui-shell.md's *"chrome shouts, prose does not"*. Not "OPEN DOOR" — the door is right there. Not
"PRESS TO OPEN" — the keycap says that.

## Colour

A pressed button goes **dark teal**: `COLOUR_BLOCKOUT` at roughly 45% value,
`Color(0.11, 0.28, 0.26)`, exported as `pressed_tint`.

blockout-boxes.md assigns every colour a job — *warm is what you clear, cyan is what you grab,
grey is the instrument, teal is yours* — and all four slots are taken. Warm would read as ruler
geometry ("clear this"), which is exactly wrong for a spent switch; grey would make it look
like part of the jump grid; a new hue costs the one-glance property the palette exists for.

Same hue at lower value reads as *this object, spent* rather than *a different kind of object*,
claims no slot, and matches ui-shell.md's own convention where 45% already means locked or
inactive. Scanning a room, bright teal is live and dark teal is used, with no legend to learn.

**Applied as a `base_color` shader parameter on the material already there, never by writing
`tint`.** `tint`'s setter calls `_rebuild()`, which `remove_child` + `queue_free`s the `Mesh`,
`Shape` and `SizeLabel` and builds three fresh ones. Destroying a collider from inside a signal
that fired during physics flushing is how you get *"Can't change this state while flushing
queries"*, and even where it is safe it is a lot of node churn for a colour. `tint` keeps
meaning "what this box is"; the runtime state change is a paint job on top.

No press animation on pilot9 — he has no interact clip, boarding EXIA is a cut for the same
reason, and inventing one is a Blender trip rather than a code change.

## What the test fences

`tests/test_door_button.gd`, headless.

A `--script` run does not step the physics server, so `Area3D.body_entered` never fires. That
shapes one design decision rather than being worked around: the two things that could be
silently wrong are written as directly-callable functions — `accepts(body) -> bool` and
`advance(delta) -> void` — both one-liners wrapping what would otherwise be buried in a signal
handler and `_physics_process`, and no worse to read for it.

Ranked by how silently each fails:

1. **The default target is `^"../Door"`.** The paste-survival property, and the point of the
   feature. Regress it and every pasted door still *works* — it just opens the wrong door
   somewhere else, which you find by playing rather than by testing.
2. **Travel defaults to `size.y`; `open_distance` overrides when nonzero.**
3. **The door stops exactly at `closed_y + travel`** and does not overshoot on a large `delta`.
   A hitch on a loading frame must not launch a door through the ceiling.
4. **The rise is 3.0 m/s**, stepped a known number of times.
5. **`CLOSED` is captured from the authored transform**, so a door placed at y=12 opens to
   12 + travel.
6. **One-shot latches**: a second `activate()` changes nothing and the button reports spent.
7. **`activate()` is duck-typed** — a bare stub with one gets called; a node without one is
   ignored rather than erroring.
8. **`accepts()` is true for a `player`-group body and false otherwise** — what stops the
   button tracking the scenery it is mounted on.
9. **Nothing generated carries an `owner`** — the Area3D and the auto-created prompt both. The
   same assertion `test_blockout.gd` makes, for the same reason.
10. **`interact` exists in `project.godot` with a key *and* a joypad event**, so a future
    InputMap edit cannot quietly drop the pad.

Not tested: that `mech.gd` consumes the event. Headless input dispatch with no viewport is a
fight, and the assertion would end up testing Godot rather than this code.

## What this is not

Not a trigger system. There is no event graph, no conditions, no sequencing, no "open when all
three are pressed", no save state — a button, a thing with `activate()`, and a NodePath between
them. A relay node composes the one-to-many case out of what is here; anything past that is a
logic editor, and the useful thing to learn first is whether a pasteable gate is enough to
blockout a room that changes shape.

Not a lift, not a hinged door, not a pressure plate. The Area3D is the same node a plate would
need and `press_to_activate: bool` is the `if` that would branch it, but nothing here is built
for one.

## Known Gaps

- **A button inside EXIA's 9 m interaction box draws two prompts**, because `mech.gd` keeps its
  own inside `mech.tscn` at the same bottom-centre anchor. One `interact` press is consumed by
  whichever of the two sits lower in the scene tree. **Don't put buttons next to the mech.**
  The real fix is migrating `mech.gd` onto `InteractionPrompt` and deleting `mech.tscn`'s `UI`
  CanvasLayer — deliberately deferred, because `mech.gd::_update_prompt()` is entangled with
  four timers and called from seven places across a tuned climb, and rewriting it inside a door
  feature is how you end up debugging EXIA's boarding animation on a day meant for doors. It is
  its own task.
- **Which handler wins the consumed press is scene-tree order**, which is not designer-legible.
  A real answer is an interaction-priority pass and a different spec.
- **The reach volume is invisible in the editor.**
- **A door that closes is not safe yet** — see the StaticBody3D section. `auto_close_after`
  exists and defaults to 0.
- **Setsuna cannot press buttons**, not being in the `player` group.
- **Doors and buttons carry the box's floating size label** (`4 x 1 x 6`) and sit outside the
  cel pipeline, because they are blockout boxes. This mechanic gets an art pass later rather
  than never; `show_size_label` turns the label off per box for a screenshot.
