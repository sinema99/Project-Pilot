# Spec: a complete stop clears the sprint

> **Status:** built 2026-09-10, **unplayed**.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Touches:** `scripts/pilot9.gd` only - `_update_sprint_toggle()` plus one constant and one
> member. No rebuild, no bake, no animation change, no new input action.
> **Follows:** `docs/specs/pilot9-real-controller.md`, which made `sprint` a toggle rather
> than a hold. That decision stands; this adds the one thing besides `walk` that ends it.

## Problem statement

`sprint` is a toggle (deviation 2 of the Real Controller pass, `_update_sprint_toggle()`).
Pressed once it stays on until `walk` is pressed, which in practice means **forever**: nobody
presses Alt. So the toggle gets set on the first sprint of the session and from then on
pilot9 is a character who sprints whenever the stick is pushed. The three gaits collapse into
one, and the sprint stops being something the player *does* - it is just how he moves.

The toggle was written for a good reason and that reason still holds: letting go of the
button mid-jump should not silently drop him out of a run, and a jump buffered into a slide
needs the sprint intent to outlive the button. All of that is about carrying intent **through
a move**. None of it is about carrying intent across a standstill.

## The rule

**Coming to a complete stop clears the sprint.** After a stop, the next sprint needs a fresh
press.

A complete stop is all four of:

- **on the floor** - a pilot9 in the air has not stopped, he is between things,
- **horizontal speed at or under `SPRINT_STOP_SPEED`** (0.1 m/s),
- **the stick centred** - `input_dir == Vector2.ZERO`,
- **not frozen** - see below.

It is an **edge, not a state**. The clear fires once, on the frame he arrives at rest, and is
then disarmed until he moves again. That is what keeps the obvious player habit working:
press `sprint` while standing still, *then* push the stick, and he sprints. Tested as a
state, that press would be eaten on the very next frame.

What it gives, in the order a player will meet it:

| Situation | Sprint after |
|---|---|
| Sprint, release the stick, coast to a halt, push again | **off** - press `sprint` again |
| Sprint, jump, land, keep running | **on** - he never stopped |
| Sprint, jump, let the stick go, fall straight down, land at rest | **off** - the landing is the stop |
| Sprint into a wall head-on, stick still held | **on** - the stick never asked to stop |
| Sprint, slide, stand up, keep running | **on** - a slide is never that slow |
| Sprint, slide, stand up, let go, halt | **off** - the same halt as any other |
| Press `sprint` standing still, then push the stick | **on** - the press answers the edge |
| Sprint, pause, unpause | **on** - a pause is not a stop |
| Sprint, board EXIA, get out, stand there | **off** - boarding already cleared it, and standing there would have anyway |

The wall row is the one worth arguing about, and the argument is that **the stick is the
player's request**. Pinned against a wall at 0 m/s with the stick buried he is still asking to
run; the wall stopped him, he did not stop. Turn away and the run is there. Let go and it is
gone - by the row above it, on that same frame.

The freeze row falls out of `_update_sprint_toggle()`'s existing early return, but it needs
one extra line to hold: `handle_frozen_movement()` zeroes both `velocity` and `input_dir`, so
the first unfrozen frame looks exactly like a stop. The freeze therefore **disarms** the edge
on its way past, and the toggle comes back off a pause untouched - which is what
`_update_sprint_toggle()`'s docstring already promises.

## What changes

### `scripts/pilot9.gd`

One constant, one member, two lines inside `_update_sprint_toggle()`, and the edge itself in a
function of its own:

```gdscript
const SPRINT_STOP_SPEED := 0.1

var _sprint_stop_armed: bool = false

func _update_sprint_toggle() -> void:
	if frozen:
		_sprint_stop_armed = false      # a pause is not a stop
		return
	_update_sprint_stop(is_on_floor())
	if Input.is_action_just_pressed("sprint"):
		sprint_toggled = not sprint_toggled
	elif Input.is_action_just_pressed("walk"):
		sprint_toggled = false

func _update_sprint_stop(on_floor: bool) -> void:
	if not (on_floor and input_dir == Vector2.ZERO and _horizontal_speed() <= SPRINT_STOP_SPEED):
		_sprint_stop_armed = true
		return
	if _sprint_stop_armed:
		_sprint_stop_armed = false
		sprint_toggled = false
```

The stop test sits **above** the press so a press landing on the stop frame wins. That
ordering is the standing-still-then-pressing case, and it is the only reason the two halves
are not the other way round.

`on_floor` is **passed in rather than read**, for one reason: outside the tree `is_on_floor()`
is false and cannot be faked, so a self-contained `_update_sprint_toggle()` would put the
entire rule out of reach of a `--script` run. `_update_sprint_toggle()` is the only caller and
it passes `is_on_floor()`.

`velocity` and `input_dir` are both **last frame's** here - `_update_sprint_toggle()` runs at
the top of `_physics_process()`, before `_handle_movement_input()`. That is correct rather
than merely tolerable: the stop being detected is the one `move_and_slide()` actually
produced, not one predicted from this frame's stick.

Nothing else reads `_sprint_stop_armed`. `sprint_toggled` gains one writer and keeps its old
three: the press flip, the `walk` clear, and `_end_verbs_for_boarding()`, which already dropped
the sprint intent on the way into EXIA.

## Decisions

| | Taken | Over |
|---|---|---|
| What ends a sprint | A complete stop | A timer, or `sprint` going back to a hold. A hold undoes the jump and slide reasons the toggle exists for. |
| Stop as edge or state | **Edge**, re-armed by movement | A state test, which eats a `sprint` press made while standing still - the commonest way a player starts a run. |
| Stick held into a wall | Sprint **survives** | Clearing on speed alone. The stick is the request; the wall is not the player. |
| Mid-air at 0 m/s | Sprint **survives** | Clearing in the air, which fights the whole point of the toggle. |
| Speed threshold | `0.1` m/s, its own constant | `SPEED_EPSILON` (0.001), which a slope's residual velocity clears without him going anywhere. |
| Freeze | **Disarms** the edge | Letting the unfreeze read as a stop, contradicting the docstring's own promise. |
| A dial to turn it off | **None** | An export nobody would ever move. `SPRINT_STOP_SPEED` is the only number here. |

## Risks

1. **It is a habit change.** Anyone used to the current build has a character who sprints by
   default; after this he sprints by asking. That is the point, but the first minute will
   feel like the sprint broke.
2. **The threshold is a guess.** 0.1 m/s is far under a crouch (1.6) and well over the
   residue `move_and_slide()` leaves on a standable slope, but only play says whether a gentle
   grade creeps him along at 0.05 forever with the sprint quietly still on.
3. **`crouch` at a standstill clears it too** - crouched and idle passes all four tests. That
   reads right (he stopped) but it is a second way to lose the toggle without touching
   `sprint` or `walk`, and it is worth watching for.

## What this does not do

- **No change to `walk`**, which still clears the toggle on press.
- **No change to the slide, the jump, the mantle, the crouch, the FOV or the momentum.**
  `is_sprinting` is computed exactly as before; only the intent behind it expires.
- **No change to EXIA/mech mounting.** He simply comes out of it stopped, and the rule then
  applies to him like it does to any other stop.
- **Nothing for Setsuna** - `scripts/player.gd` is untouched.

## Test coverage

`tests/test_pilot9_sprint_stop.gd`:

- a stop with the toggle on **clears it**, and only once he has moved first
- a second stopped frame does **not** clear again - the edge is spent
- the stick held with the speed at zero (the wall) **keeps** the toggle, and re-arms
- speed above the threshold **keeps** the toggle, and re-arms
- airborne at zero speed with no stick **keeps** the toggle, and re-arms
- the threshold itself: 0.09 m/s clears, 0.2 does not
- `frozen` neither clears the toggle nor lets the unfreeze read as a stop
- the ordering inside `_update_sprint_toggle()` - the stop above the press - as a source
  assertion, the way `test_pilot9_sprint_fov.gd` asserts placement, because `Input` cannot be
  driven from a `--script` run
- `walk` and `sprint` are still the function's only other writers of `sprint_toggled`

The tests drive `_update_sprint_stop()` directly on an instanced pilot9 with `velocity`,
`input_dir` and `_sprint_stop_armed` set by hand, and `_update_sprint_toggle()` for the frozen
case (which returns before it touches `Input`).

Whether the re-press *feels* like the right amount of friction is QA.
