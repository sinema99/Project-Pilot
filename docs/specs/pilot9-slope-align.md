# Spec: slope alignment for pilot9

> **Status:** written 2026-09-11, built the same day. Not yet played - the look is unjudged.
> **Scene:** `scenes/pilot9.tscn`. **Scripts:** `scripts/pilot9.gd`, `scripts/pilot9_animation.gd`.
> **Sibling:** `docs/specs/pilot9-slope-momentum.md` - that one is what a slope does to his
> *speed*; this is what it does to his *pose*. They share nothing but the floor normal.
> **Precedent:** Setsuna already has half of this - `scripts/player.gd::_slope_pitch()`.

## Problem statement

`screenshots/shot_2026-09-11_14-00-32.png` and `..._14-00-35.png`: pilot9 on the test map's
long ramp, bolt upright, feet on a grade of roughly 35 degrees. EXIA next to him is on the
same ground and reads as *on* it; pilot9 reads as a statue someone slid down a hill. He has
no slope pose at all - `_handle_character_rotation()` writes `character.rotation.y` and
nothing has ever touched the mesh's pitch or roll.

The user's ask, verbatim: *"i want to make it so pilot gets rotated to be parallel with the
slope."*

## The rule

**On the floor, the mesh's up axis eases toward the floor normal. The capsule stays
vertical.**

This is the same trade `player.gd` makes for Setsuna and it is made for the same reason: the
`CharacterBody3D` is a collision capsule, and tipping it changes what he can walk into, what
the mantle probes hit, and how `move_and_slide()` resolves a wall. Nothing about the physics
moves. The `character` child - the mesh, already the node that carries his facing - is the
only thing that tilts. It is a lie told to the camera, and it is the whole feature.

### Two axes, not one

Setsuna's version is pitch only: nose down going downhill, nose up going up, nothing when she
walks across a grade. That covers the screenshots exactly, and it is *not* what "parallel with
the slope" says. A body whose up axis is the floor normal also **rolls** when the ground falls
away to one side, and that is the case pitch alone leaves upright - crossing a ramp sideways,
which a parkour route does constantly.

So this builds the general version and puts a weight on each axis:

- `slope_align_pitch` (0..1, default **1.0**) - lean along the heading.
- `slope_align_roll` (0..1, default **1.0**) - lean across it.

At `1.0 / 1.0` he is literally parallel with the slope. At `1.0 / 0.0` he is Setsuna: pitch
only, dead vertical seen from behind. At `0.0 / 0.0` the feature is off and this spec costs
nothing. The user tunes it on play; the reason it is a pair of floats rather than a bool is
that the honest answer to "should a biped roll on a hillside?" is "some, probably not all",
and that answer is a number.

### The arithmetic

One static function, `_slope_align_angles(yaw, floor_normal, pitch_weight, roll_weight) ->
Vector2`, returning `(pitch, roll)` in radians for `character.rotation.x` and `.z`.

Take the floor normal into the body's own yaw frame (`n.rotated(Vector3.UP, -yaw)`) and the
two angles fall straight out of the Euler **YXZ** identity Godot already uses for
`Node3D.rotation`:

```
n_body = (-sin(roll), cos(roll) * cos(pitch), cos(roll) * sin(pitch))

pitch = atan2(n_body.z, n_body.y)
roll  = asin(-n_body.x)
```

Exact, not an approximation - at weight 1.0 on both axes the resulting basis maps local `+Y`
onto the floor normal to within float noise, and a test asserts that round trip rather than
the two angles separately.

The YXZ order is what makes this safe to write as three independent Euler components:
`rotation.y` is applied *outermost*, so **the heading stays exactly what
`_handle_character_rotation()` set** no matter what pitch and roll do. Nothing in the
turn-to-face rule, the slide's welded heading or the mantle's snapped facing has to know this
exists.

Sign conventions, the only part worth checking by hand - a flip here leans him *into* the hill
and reads as a broken clip rather than as a wrong sign:

- Positive `rotation.x` is **nose-down**, and downhill is where the normal leans, so
  `n_body.z > 0` going downhill gives a positive pitch. Same convention and same sign as
  `player.gd::_slope_pitch()`, deliberately - the two characters should not disagree about
  which way down is.
- `character`'s local `+X` points to pilot9's **left** (the 180-degree basis on the node, the
  same fact `pilot9_animation.gd::_travel_blend()` documents), so ground falling away to his
  left puts the normal at `n_body.x > 0`, gives a negative roll, and tips his head toward the
  downhill side. Correct: parallel to the ground, not braced against it.

### Deadzone, easing and release

- **3-degree deadzone per axis** (`SLOPE_ALIGN_DEADZONE`), applied before the weights. A
  collision mesh throws sub-degree normal changes across nominally flat floor, and without
  this he twitches while standing still. Same value and same reason as Setsuna's. It is the
  last argument of the static function rather than a constant read inside it, because it is
  the one part of this that is deliberately *not* exact - the round-trip test turns it off to
  assert the alignment, and a separate test brackets the default. Nothing in the game passes it.
- **Eased, not snapped**, at `slope_align_speed` (default 10.0, kept equal to
  `rotation_speed`) so cresting a ramp sweeps the way a turn does.
- **Released to level** the moment he is airborne or mantling, on the same ease. An airborne
  body has no grade to lie along, `get_floor_normal()` is stale the frame `is_on_floor()` goes
  false, and a mantle is a scripted path over an edge that already owns his pose.

### Where it runs

`_align_model_to_slope(delta)` is the **tail** of `_physics_process()`, after
`move_and_slide()`, because `get_floor_normal()` is that call's output and reading it earlier
is reading last frame's grade.

That costs a small restructure: the mantle and frozen paths currently `return` early, and this
has to run on those frames too - to *level* him through a mantle, and to keep tilting him
while frozen on a slope, since a freeze is not a reason to stand up straight. The two early
returns become an `if / elif / else` with a single tail call. Nothing about what those
branches do changes, and the comment explaining why the mantle skips `move_and_slide()` stays
exactly where it is.

`exit_vehicle()` zeroes `rotation.x` and `.z` next to the `rotation.y` it already writes: he
is placed, not walked, and a tilt carried in from the ramp he boarded on would be wrong for
wherever EXIA parked.

## What this breaks, and the fix

`pilot9_animation.gd::_travel_blend()` feeds the locomotion blend spaces travel direction *in
body space*, and it reads `player.character.transform.basis` to do it. The moment that basis
carries a pitch, `b.x` and `b.z` tip out of horizontal, the dot products against a horizontal
`direction` shrink by `cos(pitch)`, and running straight up a 35-degree ramp asks the blend
space for 0.8 of forward - a run that drifts toward a walk on every hill, for no reason a
player could ever guess at.

The fix is one line: build a **yaw-only** basis, `Basis(Vector3.UP, player.character.rotation.y)`.
Identical to today's value whenever pitch and roll are zero, immune to them when they are not,
and `rotation.y` is still the exact heading for the YXZ reason above. `test_pilot9_climb.gd`
already builds its expectations this way, so the form is not new to the repo.

## Tests

`tests/test_pilot9_slope_align.gd`, headless, all but one against the static function - the
same shape and the same reason as `test_pilot9_slope_momentum.gd`: `is_on_floor()` cannot be
made true without a physics world, so a pure function taking a floor normal is the only
version of this arithmetic that can be tested before it is in the user's hands.

- Flat ground, and a zero normal (what `get_floor_normal()` hands back airborne), give zero on
  both axes.
- Facing downhill gives a positive pitch and no roll; facing uphill, a negative pitch. These
  are the sign regressions.
- Facing across the grade gives no pitch and a roll toward the downhill side, from both sides.
- The same normal at four yaws trades pitch for roll continuously - i.e. the yaw frame really
  is applied, and the function is not quietly world-space.
- **Round trip:** at weights 1.0, `Basis.from_euler(Vector3(pitch, yaw, roll))` (YXZ) maps
  `Vector3.UP` onto the floor normal, for a scatter of normals and yaws. This is the test that
  says "parallel with the slope" rather than "leans about right".
- Weights scale their own axis and nothing else; 0.0 on an axis pins it to 0.0.
- A 2-degree grade is inside the deadzone and reads flat; a 4-degree one does not.
- `_travel_blend()` still returns `(0, 1)` for straight-ahead travel with a pitch and a roll
  on the mesh - the regression for the bug above.

**What automated checks cannot establish:** whether 1.0 roll is too much roll, whether the
ease rate reads as weight or as lag, and whether his downhill foot floating clear of the
ground on a steep grade is visible in play. Those are the user's on play.

## Not in this pass

- **Foot IK.** A rigid tilt pivots the whole mesh about his root, so on a steep grade one foot
  sinks and the other floats. The real fix is two-bone IK per foot against a raycast, which is
  its own feature and earns its keep on stairs and ledges as much as on slopes. If the
  floating foot is what reads worst on play, that is the follow-up - not a smaller roll weight.
- **Tilting into acceleration.** Leaning into a hard turn or a stop is the same node and the
  same ease, and it would compose with this additively. Deliberately separate: one source of
  lean at a time, so the dial that is wrong is obvious.
- **EXIA.** The mech has the same problem and four legs' worth of reasons the fix is different.
  Out of scope.
