# Spec: pilot9's dash FOV kick

> **Status:** specced, built and played 2026-09-26, as written - no departures. The user:
> "feels good." Shipping numbers unchanged. See docs/worklog/2026-09-26.md.
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd` only. No rebuild, no bake,
> no animation change, no new setting row.

## The ask

"A quick FOV increase when pilot dashes ... nothing snappy and jarring but something smooth.
Something that makes you feel like you're moving faster than you are." Both the ground dash and
the air dash get it - the user's call, 2026-09-26.

## The rule

**A dash widens the lens by `dash_fov_boost` degrees, fast in and slow out, on top of whatever
the lens is already doing.**

- **In:** eases open over `dash_fov_rise_time` (0.12 s) from the launch.
- **Hold:** stays open for the rest of the dash.
- **Out:** the moment the dash ends - on its timer, blocked by a wall, or cut by a freeze - it
  eases shut over `dash_fov_release_time` (0.6 s).
- **Stacks on the sprint boost** rather than replacing it. A dash out of a sprint goes
  base + 10 + 10; he always comes *out* of a dash sprint-toggled (see `_end_dash()`), so the
  sprint's +10 is usually still there when the kick has bled away.

The asymmetry is the whole design. The dash is 0.25 s long, so the in has to be quick or the
lens is still opening when he reappears. The out is where the smoothness lives, and it runs
well past the dash on purpose: he is back at sprint speed but the lens is still coming down,
and that trailing half-second is the "faster than you are" read.

## The shape

Both halves are `smoothstep`, not a lerp-at-a-rate. The sprint FOV's `lerpf` at a rate is
fastest at its *start*, which here would put the sharpest pull of the whole close exactly on
the frame he reappears - the one moment the ask says must not be jarring. `smoothstep` is
zero-slope at both ends, so the close starts gently and lands gently.

The envelope is a pure function of three things - how long since launch, whether he is still
dashing, and how long since the dash ended - plus the level it was at when the dash ended:

```
dashing:   k = smoothstep(0, 1, elapsed / rise_time)
released:  k = k_at_release * (1 - smoothstep(0, 1, since_release / release_time))
lens:      fov = sprint_eased_fov + k * dash_fov_boost      (then the ceiling, below)
```

`k_at_release` is what makes a **blocked dash** smooth: a dash stopped by a wall at 0.05 s
ends with the lens only partly open, and the close starts from there instead of snapping up to
full and back down.

**A second dash mid-release** restarts the rise from the *current* `k`, not from 0 - otherwise
the lens would drop to base and jump open again. Rare: the 1.5 s cooldown outlasts the 0.6 s
release, so only a ground dash followed by an air dash on the charge can hit it.

## The sprint FOV has to stop owning `camera_3d.fov`

Today `_handle_camera_fov()` lerps **`camera_3d.fov` toward its target from wherever the
camera currently is**. Add a kick on top of that and the next frame's sprint lerp reads the
kicked value as its starting point and pulls it back down at the sprint's rate - two
envelopes fighting over one number, and the release would not be the release.

So the sprint's eased value moves into its own variable, `_sprint_fov`, which the existing
lerp steps exactly as it steps `camera_3d.fov` today. The camera is then *written*, never
read back:

```
_sprint_fov = lerpf(_sprint_fov, base_fov + sprint_boost_or_0, rate)
camera_3d.fov = minf(_sprint_fov + kick, ceiling)      # ceiling applies only to the kick
```

Nothing changes for the sprint - same gate, same rate, same off switch - and the sprint FOV
tests must still pass without being edited. That is the regression check for this seam.

## The ceiling

`Settings.fov` goes up to 110. At 110, sprint (+10) plus dash (+10) is 130 - fisheye. So the
**kick** is clamped so the lens never passes `dash_fov_ceiling` (115). It only ever limits the
kick: the sprint and the player's own FOV setting are never pulled down by it, and a player
already above 115 from sprint alone just gets no kick.

At the default 75 the ceiling never engages (75 + 10 + 10 = 95).

## Ground and air

Both, identically, with no extra code. The kick reads `is_dashing` and nothing else, and the
ground dash, the air dash and the dash off a rail all set it the same way in `_start_dash()`.

## CAMERA MOTION off switches it off

The kick is a camera move of exactly the kind the CAMERA MOTION row exists for - rapid wide-angle
kicks are a common motion-sickness complaint. With the row off, `k` is forced to 0 and the
envelope's clocks are reset, so switching it back on mid-dash does not pop a half-open lens in.

The **sprint** FOV is left alone by that row, as it is today. It predates the row, it is slow,
and changing what an existing row does is a separate decision.

## Where it runs

Inside `_handle_camera_fov()`, which is already first in `_physics_process()` and above every
early return - so the release keeps easing through a mantle or a freeze, exactly the reason the
sprint FOV sits there. It reads `is_dashing` one physics frame late (`_handle_dash()` runs
later in the step): 16 ms on a 120 ms rise, not visible.

Physics delta, not real time. The camera lag uses real time in `_process()`, but it is a
position blend on a drawn-frame callback; the FOV already lives in the physics step and moving
it would be its own change.

## Not synced to the camera lag

Asked; decided against. The camera lag (`camera_dash_lag_delay + camera_dash_lag_time`, 0.35 s
from launch) is done before the kick's release (0.25 + 0.6 = 0.85 s) is. That is deliberate -
the shot is back on him while the lens is still settling, which reads as speed carrying past
the dash rather than as two effects ending together on one beat. **The play should judge it.**
If it reads as two separate effects, the fix is to shorten `dash_fov_release_time`.

## The dials

| Export | Starts at | What it is |
|---|---|---|
| `dash_fov_boost` | `10.0` | Degrees added at full kick. `0.0` is the off switch. |
| `dash_fov_rise_time` | `0.12` | Seconds from launch to full kick. |
| `dash_fov_release_time` | `0.6` | Seconds from the dash's end back to no kick. |
| `dash_fov_ceiling` | `115.0` | The lens the kick will not push past. |

All four in the existing `Camera` export group, beside `sprint_fov_boost`.

## Decisions

| | Taken | Over |
|---|---|---|
| Shape | `smoothstep` in, `smoothstep` out, by time | A lerp at a rate, which is steepest on the frame he reappears. |
| Asymmetry | 0.12 s in, 0.6 s out | Symmetric - either too slow to open inside a 0.25 s dash, or too quick to close to feel smooth. |
| Stacking | Additive over the sprint boost | Replacing it, which drops the lens on a dash from a sprint - the most common dash. |
| Ownership | `_sprint_fov` held separately; the camera is write-only | Adding onto `camera_3d.fov` in place, where the sprint lerp would pull the kick back down. |
| Scope | Ground and air alike | Ground only. The user's call. |
| Accessibility | Gated by CAMERA MOTION | Always on, or a new row of its own. |
| Lag sync | Independent | Tied to the camera lag's window. Flagged for the play. |

## Risks to watch on the play

1. **Too much with the sprint.** 95 degrees on a sprint-dash at the default FOV may read as a
   warp rather than a push. `dash_fov_boost` down to 6-8 is the first turn.
2. **The release reads as a second event** (see *Not synced to the camera lag*).
3. **The streak's pen weight.** `_streak_bundle()` converts pixel weight to metres through
   `camera_3d.fov`, so the manga speed lines get slightly finer on screen while the lens is
   open. Probably invisible; if the lines look thinner on a dash, this is why.
4. **First person.** The kick applies there too, since it is the lens. More intense up close;
   only a play tells.

## What this does not do

- **No change to the dash itself** - speed, time, cooldown, streak, lag all untouched.
- **No speed-proportional FOV.** The same reason the sprint FOV gives: the dash is a discrete
  event and the lens can be too.
- **No change to the sprint FOV's behaviour,** only to where its eased value is stored.
- **Nothing for Setsuna or the mech camera.**

## Test coverage

`tests/test_pilot9_dash_fov.gd`, mostly against the pure envelope function:

- at launch `k` is 0; at `rise_time` it is 1; it holds at 1 while dashing
- after the end it reaches 0 at exactly `release_time`, and is eased (zero slope) at both ends
  of the release
- a blocked dash ending at partial `k` releases from that value, never above it
- a re-dash mid-release rises from the current `k`, not from 0
- `dash_fov_boost = 0` is a working off switch
- the ceiling limits the kick only, and never pulls a lens already above it down
- CAMERA MOTION off forces the kick to 0
- on the rig: a dash from a sprint lands on `base + sprint + dash`, and ends back on
  `base + sprint`
- an air dash kicks the same as a ground dash
- `tests/test_pilot9_sprint_fov.gd` passes unedited
