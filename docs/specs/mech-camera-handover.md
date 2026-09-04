# Spec: The camera handover, in and out of EXIA

## Problem Statement

Climbing into EXIA is a cut. `mech.gd::_enter_mech()` sets `camera.current = true` and the
picture is replaced on that frame: Setsuna's over-the-shoulder view is gone and a 12 m third
person shot of a mech is there instead, from whatever angle the mech's camera happened to be
left at.

Getting out is the same cut in reverse, plus a third problem of its own: `ExitPoint` puts
Setsuna 3.5 m off EXIA's right flank, which is a spot chosen to be somewhere rather than to be
anywhere in particular.

Two things are wrong with the entry, and they are separate problems with separate fixes.

**The cut has no travel in it.** There is nothing to tell the player that the new view is the
same place seen from further out - it reads as a scene change rather than as the pilot's view
widening into the machine's. `docs/specs/exia-pilot.md` called this out when it was written:
"No seat, no mount animation, no camera transition ... this is explicitly the placeholder
version." This spec is the transition it deferred.

**The angle is inherited, not chosen.** `camera_yaw` is a field on the mech that is only ever
written by mouse motion, so it holds whatever the last piloting session ended on - and on the
very first entry it holds 0.0, which is a compass bearing and has nothing to do with where the
mech is pointing. Walk round the back of EXIA and press F and the camera is in its chest,
looking at the pilot. Which shot you get depends on a variable the player cannot see.

## What ships

### 1. Entering always starts behind the mech

`_enter_mech()` sets the camera's orbit outright rather than inheriting it:

- **Yaw** is put directly behind the machine, looking along its nose. `yaw_behind(mech_yaw)` is
  the one line of trigonometry involved, and it has to agree with `facing_for()`: the camera
  looks along its pivot's -Z and the mech's nose is its +Z, so "behind" is half a turn round
  from the body's own yaw. The two are asserted against each other in the tests, the same way
  `facing_for` is asserted against the heading the mech turns towards.
- **Pitch** is reset to `ENTRY_PITCH`, a shallow look-down, so the framing on entry is the same
  every time instead of resuming wherever the last session left the mouse.

This holds however the pilot walked up: from the front, from the side, from behind. The first
frame of piloting always shows the mech's back and the ground it is about to walk over, which is
also the frame in which W means "away from camera".

### 2. The cut becomes a pan, both ways

A dedicated `HandoverCamera` on the mech flies the picture from one view to the other over
`HANDOVER_TIME`. The same flight runs in both directions - out of the pilot's view and into the
mech's on the way in, and back the other way on the way out:

- It starts on the **viewport's current camera**, read the instant before the handover - not on
  either camera by node path. The mech does not need to know what a pilot's camera rig looks
  like, and reading the viewport is also what makes a pan interrupted by a second press of F
  take over from wherever the first flight had got to, rather than snapping back to its start.
- It ends on the **destination camera's live transform, re-read every frame**, so the pan lands
  exactly where that camera is rather than where it was when F was pressed. This matters in both
  directions: on the way in `MECH_launch` walks EXIA 0.96 m forward under root motion while the
  pan is running and the pilot may already be turning with the mouse, and on the way out Setsuna
  has her body back and can walk off mid-pan. A destination captured up front would be stale by
  the time the pan reached it, and the handover would end on the small jump this feature exists
  to remove.
- The ease is `handover_ease()`, smoothstep, so the camera leaves and arrives with no velocity
  at either end. A linear pan starts and stops with a visible jolt at exactly the two moments the
  player is looking for the join.
- FOV is interpolated alongside the transform, and near/far are copied off the destination
  camera, so a future change to either camera's lens does not make the pan pop.

The handover camera is `top_level`, so the mech walking forward underneath it does not drag it -
its transform is written in world space every frame and nothing else may touch it.

Control is **not** frozen during the pan, in either direction. The launch plays, the mouse still
steers, a player who hammers W drives off mid-pan, and a player who gets straight back out mid-pan
gets a new pan starting from where the old one stood. The pan simply chases the camera it is
handing over to. A transition that takes the controls away for the best part of a second to show
off a camera move is worse than the cut it replaced.

### 3. Getting out ejects her from the back

`ExitPoint` was 3.5 m off EXIA's right flank. It moves to **2.5 m straight out of the back**, on
the mech's own -Z, so it turns with the machine: whichever way EXIA is facing when the pilot lets
go, she lands directly behind it. That clears the body collider (1.9 m deep, so 1.55 m of daylight
between her and the hull) without putting her out of arm's reach, and it puts her the right side
of a mech whose power-down walks it 1.26 m *forward* - the machine steps away from her as it
crouches rather than over her.

`exit_vehicle()` takes the facing the vehicle wants her pointed in, and EXIA hands her its own
yaw, so she lands **facing the mech she just climbed out of**. Her camera goes behind her by the
same rule as the entry, at `EXIT_PITCH`, and for the same reason: her `camera_yaw` is still
holding the heading she walked up on, which is an arbitrary angle by the time she gets out.

Those two choices are what make the exit pan trivial, and they are the reason it was deferred
rather than built with the entry. Behind the mech and facing it, her camera and the mech's are on
**the same axis**, with the mech camera further back and higher: the flight is a straight dolly
in and down with nothing between the two views. From the old flank position it would have swept
through EXIA's body and needed a path chosen for it.

She also lands inside the interaction box, so the `F pilot` prompt re-arms as soon as her collider
comes back - getting out and getting straight back in stays one keypress each.

## Constants

| Constant | Value | Why |
|---|---|---|
| `HANDOVER_TIME` | 0.6 s | Long enough to read as a move, short enough not to be a cutscene. Sits inside `MECH_launch`'s 1.0 s, so the pan is over before the boot-up is. |
| `ENTRY_PITCH` | -0.15 rad | ~8.6 degrees of look-down: the mech is 8.4 m tall and the pivot is at 7.9 m, so a level camera stares at its shoulders. |
| `EXIT_PITCH` | 0.0 | Level, which is where Setsuna's camera sits at the start of the game. Getting out ends on her ordinary framing, not a special one. |
| `ExitPoint` | (0, 0, -3.6) | Straight out of the back, 2.1 m clear of the hull. It is a marker in `mech.tscn` rather than a constant, so it can be dragged in the editor. |

Both are dial-in numbers. Neither can be judged headlessly.

## Testing

Automated coverage is the two pure functions and the wiring that fails silently:

- `yaw_behind()` against `facing_for()` - the camera's look direction is the mech's nose, for
  every heading. This is the assertion that catches a sin/cos swap, which would leave the camera
  on the mech's flank on entry.
- `yaw_behind()` stays wrapped into [-PI, PI], so `camera_yaw` cannot drift a turn per entry.
- `handover_ease()` - 0 at the start, 1 at the end, clamped past the end, monotonic, and flat at
  both ends. Plus a zero duration handing back 1.0, since it divides by the window.
- The scene carries `HandoverCamera`, it is `top_level`, and it is not `current` - a
  handover camera left current in the scene file would own the viewport from the first frame.
- `ExitPoint` is on the mech's own -Z, outside the body collider and only a few feet out, and the
  facing EXIA hands her points her back at itself - asserted as the direction from the marker to
  the mech, at several mech headings, so it survives the marker being dragged sideways.
- `player.gd` and `mech.gd` agree on `yaw_behind()`. The rule is written down in both rigs, and
  the exit lands wrong if they ever drift apart.
- `exit_vehicle()` still takes the facing yaw. The handshake is duck-typed through
  `has_method()`, so an arity change is a runtime failure in the one frame nobody tests by hand.

The pan itself - whether 0.6 s is right in both directions, whether the entry pitch frames the
mech well, whether 2.5 m is the distance an ejection should throw her, whether the join at either
end is invisible - is a play session.
