# pilot9 jump grid

**2026-09-11.** The jump is now specified in whole numbers so a gap in the map can be built
to a measurement instead of to a feeling.

## The problem

Every number in the jump was an accident of something else. `jump_height` was 1.84 m because
that is what a 6.0 m/s launch happened to reach under Godot's stock 9.8 gravity;
`jump_time_to_apex` was 0.61 s for the same reason. Airtime came out at 1.22 s, so the three
ground speeds cleared 3.05 / 6.10 / 9.76 m. Nothing to build to: laying out a 6 m gap and
asking whether a running jump makes it meant doing arithmetic on numbers nobody chose.

## The grid

| | speed | gap cleared |
|---|---|---|
| walk | 2.5 m/s | **3 m** |
| run | 5.0 m/s | **6 m** |
| sprint | 7.5 m/s | **9 m** |

- `jump_height` **3.0 m** (was 1.84)
- `jump_time_to_apex` **0.60 s** (was 0.61)
- airtime **1.2 s** — `jump_air_time`, derived
- `sprint_speed` **7.5 m/s** (was 8.0)

Peak of a double jump: **6.0 m**.

Derived rise speed is **exactly 10.0 m/s** (was 6.03) and rise gravity 16.667 m/s^2 (was 9.89).
Same 1.2 s in the air, a third again as high — he leaves the floor considerably harder than the
jump that was played.

### Height moves on its own

Height was taken 2.0 -> 3.0 in the same session, and it cost the horizontal grid **nothing**.
Airtime is `jump_time_to_apex * (1 + 1/sqrt(fall_multiplier))` — there is no height term in it,
by construction. So the vertical and horizontal halves of this grid are independent dials:
raise the height and gaps stay 3 / 6 / 9 m. `test_height_does_not_touch_the_gaps` fences it.

What height DOES move is everything he climbs, below.

## What it cost

**The sprint, 8.0 -> 7.5 m/s.** That 0.5 is what buys the 9 m: at 1.2 s of airtime, 8.0 clears
9.76 m and no rounding of the jump fixes it.

**Every vertical relationship in the map.** A mantle reaches `peak + climb_band_max`, not
`apex + band` — the probe fires every airborne frame, so he passes through every height on the
way up and on the way down. At 3.0 m that is:

| | peak | highest lip he can mantle |
|---|---|---|
| single jump | 3.0 m | **4.9 m** |
| double jump | 6.0 m | **7.9 m** |

Both went up a metre when the height did. The concrete casualty: **TrainingV's 4.2 m block used
to need a double jump and is now a single-jump mantle.** The 8.6 and 13.3 m blocks are out of
reach either way and always were — the old note in `pilot9.gd` claiming they were reachable
from the top of a double jump was wrong before this pass and is corrected.

Anything placed to be *just* out of reach needs re-checking against those two numbers.
`test_what_a_mantle_reaches` pins them.

**Terminal velocity got closer.** `max_fall_speed: 28` is now reached 23.5 m into a drop rather
than 35. The tallest block in the map is 13.3 m — a fall from the top of it arrives at about
21 m/s — so the cap is still out of play, but the margin is thinner and the guard in
`test_pilot9_movement_reset.gd` now says so in those terms.

## What holds the grid up

The numbers above are exact **only while the feel dials stay at their 2026-09-10 reset values**
(docs/specs/pilot9-movement-reset.md):

- `jump_fall_multiplier` **1.0**. A heavier fall shortens the airtime by the square root of it,
  and shortens every gap in the map with it. `jump_air_time` models this term, so the number
  stays honest — but 1.9 would turn the 6 m run gap into 5.1 m, and the geometry would need
  re-measuring, not just the controller re-tuning.
- `jump_cut` **1.0**. With it off, every jump is the full arc and a gap either makes it or does
  not. Turn it on and the grid becomes what a *held* jump clears.
- `jump_apex_speed` **0.0**. The hang lengthens the arc and has no closed form, so
  `jump_air_time` does not model it. Turn it on and the grid becomes a lower bound.

Those three are the ones to check before trusting a measurement. `jump_air_time` and
`jump_distance()` on pilot9 are the live numbers; read them rather than re-deriving by hand.

## Designing against it

A gap is `jump_air_time * horizontal speed`. Build to 3 / 6 / 9 m and the gap says out loud
which speed it demands: a 6 m gap is a run, a 7 m gap is a sprint or nothing, a 9 m gap is a
sprint exactly and punishes a player who eased off. Anything past 9 m is a double-jump gap.

Vertical is the same arithmetic: **3 m** is the ceiling of a single jump, **6 m** of a double,
and a platform at 1.9 m or under is inside the mantle band whether he cleared it or not. For
anything he is meant to *pull himself onto* rather than clear, the numbers are 4.9 and 7.9 m.

The platform that shows all of this as geometry you can stand on is
`docs/specs/pilot9-jump-grid-platform.md`.
