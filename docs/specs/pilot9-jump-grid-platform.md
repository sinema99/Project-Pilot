# pilot9 jump grid platform

**2026-09-11.** A measuring instrument for the jump grid: a platform next to the training map
built entirely out of pilot9's own numbers, so a gap in a map can be laid out against something
you have actually stood next to.

## The problem

`docs/specs/pilot9-jump-grid.md` made the jump legible — 3 / 6 / 9 m gaps, a 3 m apex, a 4.9 m
mantle ceiling. It did not make it *visible*. Knowing a sprint jump clears 9 m and knowing what
9 m looks like from a takeoff edge are different kinds of knowing, and only the second one is any
use while blocking out a map. Worse, the table gives ceilings and nothing else: it says a sprint
jump clears exactly 9 m, and says nothing about whether a *required* sprint jump should be 9, or
7, or 8.5. Every map gap so far has been a guess wrapped around a number.

This builds the ruler. It is a dev instrument, not level content.

## What it is

`scenes/jump_grid.tscn` — a bare `Node3D` whose script `scripts/jump_grid.gd` generates every box,
gap, pillar, label and tint at load. Instanced as a sibling of `TrainingV` in `scenes/trial.tscn`,
placed clear of that map's ±36.1 m footprint. Roughly **52 × 52 m**, one solid slab, everything on
it derived.

**Nothing on the platform is a literal.** The script instantiates `scenes/pilot9.tscn`, reads the
exports off it, generates against them and frees it — the same trick `tests/test_pilot9_jump_grid.gd`
uses. Retune `sprint_speed` and the lane labelled SPRINT physically moves. A hand-modelled ruler
would have been faster to build and would have started lying the first time a dial moved, silently,
which is the exact failure the jump grid spec exists to prevent.

It is `@tool`, for the reason `scripts/rendering/apply_stylized.gd` is: map layout happens in the
editor viewport, and a ruler you have to launch the game to see is a ruler you will not use.
Generated children are built without an `owner`, so they are never serialised into the `.tscn`.

## Layout

A central runway spine at pad height. Gaps jut off both sides; the pillar field sits across the far
end.

```
                  pillar field  (2 rows x 5, 12 m pitch)
      +-------------------------------------------------+
      |   1     2     3     4     4.9                    |
      |   5     6     7     7.9   8                      |
      +-------------------------------------------------+

   10m 11m 12m 13m 14m 15m 16m 17m 18m      <- double-jump side
    |   |   |   |   |   |   |   |   |
  ==================== SPINE ====================
    |   |   |   |   |   |   |   |   |
    1m  2m  3m  4m  5m  6m  7m  8m  9m       <- single-jump side
```

Nine lane positions at **4.0 m** pitch (3.0 m of lane, 1.0 m of void between). Single-jump range
runs off one side, double-jump range off the other — the split falls on the geometry, so which side
you are standing on already tells you which jump you need.

Each lane: **6.0 m** of takeoff pad off the spine, the gap, then a **5.0 m** landing pad. The
runway is for aiming, not for accelerating — `scripts/pilot9.gd` assigns
`velocity.x = direction.x * current_speed` outright, so sprint speed arrives on the frame the key
goes down and no runway length changes it.

## The numbers, and where each comes from

| marker | metres | derived from |
|---|---|---|
| walk gap | **3** | `jump_distance(walk_speed)` |
| run gap | **6** | `jump_distance(speed)` |
| sprint gap | **9** | `jump_distance(sprint_speed)` |
| double-jump gap | **18** | `jump_distance(sprint_speed) * (1 + air_jumps)` |
| single apex | **3** | `jump_height` |
| double apex | **6** | `jump_height * (1 + air_jumps)` |
| single mantle ceiling | **4.9** | `jump_height + climb_band_max` |
| double mantle ceiling | **7.9** | `jump_height * 2 + climb_band_max` |
| grab strip depth | **0.6** | `climb_probe_reach` |
| pad height | **1.5** | inside `climb_band_min..max` (0.9–1.9) |

Gaps run **1 → 18 m at every metre**. Pillar tops run **1 → 8 m at every metre, plus 4.9 and 7.9** —
ten pillars, because the two ceilings that matter most are not whole numbers.

Every height on the platform is **feet-relative**, matching pilot9's origin: his capsule is 1.9552
tall centred at 0.9776 (`scenes/pilot9.tscn`), so the body origin is at the soles. A 3 m pillar is
3 m of the same 3 m `jump_height` measures. Getting this backwards would have put the whole vertical
half of the ruler out by a body height.

## Why every metre, and not just the limits

Three boxes at 3 / 6 / 9 would be the tidy version and would answer the wrong question. A 9 m gap is
a gap he clears with *zero* margin; nobody sane puts a mandatory jump there. What a map actually
needs to know is where the comfortable distance is, and that is not a number the physics can be
asked for — it is a number you find by jumping 7, then 8, then 9, and noticing where it stops
feeling free. A ladder costs one `for` loop and answers that. Three boxes cannot.

## Pillars are isolated, deliberately

Ten free-standing pillars on a **12.0 m** grid, two rows of five, tops **1.5 × 1.5 m**.

A staircase would have been half the size and would have measured nothing: mantle 1 m, then 2 m from
there, and you have tested three 1 m steps and learned nothing about a 3 m ledge. The whole point of
the mantle ceilings is what he reaches **from the floor**, so every pillar is approached from the
floor.

12 m pitch is not arbitrary. At 1.5 m wide that leaves **10.5 m** clear edge to edge — past a sprint
jump's 9 m even with the mantle assist below, so pillar-to-pillar chaining is not merely discouraged,
it is impossible. Each pillar also carries `climb_headroom` (2 m) of clear space above its lip, or
the mantle never fires and the pillar silently measures nothing at all.

## The lips are grabbable. This is a choice, and it has a cost.

The mantle probe fires on **every airborne frame**, taking any lip 0.9–1.9 m above his feet within
0.6 m ahead. So an undershoot that falls past a landing pad's face passes straight through the grab
band on the way down and gets rescued. A failed 12 m jump reads as a cleared 12 m lane.

The lips could have been undercut past `climb_max_lip_slope` to kill this and give a clean
cleared/not-cleared reading. They are not, because **real map geometry has square ledges**, and the
number worth knowing is what a player will actually get away with, not what the arithmetic permits.

**So: a lane number is a geometric distance, not a jump distance.** "I cleared 12" means twelve
metres *with a save*, and the spec of any gap built to that reading inherits the same asterisk.

To keep this visible rather than remembered, the leading **0.6 m** of every landing pad and every
pillar top is tinted in the grab colour. Land past the strip and you cleared it outright. Land on it
and the mantle carried you. It is an approximation — the real band also depends on fall speed — but
it is on the floor in front of you, every attempt.

## Reading the surfaces

One world-space triplanar shader, `shaders/metre_grid.gdshader`, on every generated face: **1 m minor
lines, a heavier line every 5 m**, aligned to world axes so lines stay square no matter how a box is
scaled. Put it on a pillar and the pillar counts itself — a 6 m pillar is six squares tall from
across the map, no label required.

Deliberately unlit and outside the cel pipeline. This wants legibility, not art direction, and
`trial.tscn`'s `ApplyCelGround` only targets `../TrainingV`, so the exclusion is free.

Colour carries one distinction and only one:

- **Warm ramp — what you CLEAR.** walk 3, run 6, sprint 9, double 18; apexes 3 and 6.
- **Cyan — what you GRAB.** mantle ceilings 4.9 and 7.9, and every grab strip on every pad.

A billboard `Label3D` sits over each lane and pillar: `7 m` for an ordinary one, `9 m · SPRINT` or
`4.9 m · MANTLE` for a named limit, in the limit's colour with the box tinted to match. It is
unmistakably a dev tool. It should be.

## Missing, and getting back

A continuous solid slab runs under everything — `trial.tscn` has no ground plane at all today, so a
fall off TrainingV falls forever, and the ruler is not inheriting that.

Pads sit **1.5 m** over the slab. That number is chosen to land inside the climb band: miss a jump,
drop 1.5 m, walk to the pad, mantle back up from standing, retry. No jump, no walk around, no
respawn. It is the loop that runs hundreds of times a session, so it is the one worth making free.

The trade is honest and worth stating: at 1.5 m a miss barely registers as failure, which is nothing
like a missed jump over a real drop. This platform measures reach. It does not measure nerve.

## What holds it up

Same three dials as the grid itself, all parked off by the 2026-09-10 movement reset:
`jump_fall_multiplier` 1.0, `jump_cut` 1.0, `jump_apex_speed` 0.0. Turn any of them on and every
lane on the platform is mismeasured — the geometry will regenerate against the new exports, but the
*names* on it (SPRINT, DOUBLE) stop meaning what they say. `tests/test_pilot9_jump_grid.gd` already
fails loudly if any of the three moves; this platform adds no second guard for them.

**18 m is a ceiling, not a distance.** It needs the second jump on the last frame before landing. A
double jump taken at apex gives about 15.4 m. Lanes past ~15 measure your timing more than they
measure pilot9, and the spec says so rather than the platform pretending otherwise.

## What the test fences

`tests/test_pilot9_jump_grid_platform.gd`, on a generated instance, headless.

It does **not** assert that the sprint lane equals `jump_distance(sprint_speed)`. The generator reads
that export to build the lane, so the assertion is a tautology that would pass forever while the
platform rotted — the same dead test `test_pilot9_jump_grid.gd` warns about in its own header. Grid
correctness is that file's job. This file's job is that the *instrument* does not lie:

- **A label matches its geometry.** The lane labelled `7 m` measures 7 m across in the built scene,
  by AABB, not by re-running the formula. The failure this catches is a ruler that reads wrong.
- **Chaining is impossible.** Every pillar is further from its neighbours than a sprint jump plus the
  mantle assist.
- **Headroom is clear.** Every pillar has `climb_headroom` above its lip, or it is not a mantle test.
- **Runways are present.** Every lane has its takeoff pad, or the lane measures a standing jump.

The last three are the silent ones. Break any of them and the platform still looks entirely correct
while measuring something else.

## Getting to it

`Pilot9`'s transform in `scenes/trial.tscn` moves onto the spine's start strip. Spawning at 0,0,0
puts him in the middle of TrainingV, sixty-odd metres away, which is a jog before every single
measurement. It is one transform line and it goes back the moment map geometry is what is being
tested — a manual toggle, and noted here because it is the kind of thing that gets flipped and
forgotten.

`run/main_scene` stays `test_platform.tscn`. `trial.tscn` is launched deliberately.

## Designing against it

The jump grid spec says to build gaps at 3 / 6 / 9. This platform is where you find out what to build
them at *instead* — the distance that is demanded rather than the distance that is barely survivable.
Walk the ladder, find where clearing stops feeling free, and put the mandatory jump there. Put the
optional one a metre past it. Put the deliberately-impossible route past 18.

## As built

Six places where the build had to say something the spec left open or rounded. Everything
else is as written above.

**Footprint: about 56 x 84 m, not 52 x 52. — [corrected]** The 52 was a sketch. Built to the
numbers the spec actually specifies, the lane block alone is 53 m deep (20 m of single-jump
side, a 4 m spine, 29 m of double-jump side), the pillar field has to sit a clear sprint jump
past the 18 m lane, and five pillars at a 12 m pitch are 48 m wide before any margin. The
layout is exactly the one drawn in the diagram; only the estimate of how much ground it
covers was short. It changes nothing but where the slab is parked.

**The platform's origin is the start strip's walking surface**, not the centre of the slab.
That is what makes the spawn line survive: `Pilot9` in `scenes/trial.tscn` sits at the same
x/z as `JumpGrid` itself plus 0.178 m of y, so regenerating the platform against new dials
cannot leave the spawn stranded in a trench. Both are at **x = -95**, which clears
TrainingV's +/-36.1 m by about 10 m.

**Pad height is a ratio, not 1.5.** `lerp(climb_band_min, climb_band_max, 0.6)` is 1.5 m at
the shipping band and stays inside the band wherever the band goes. A literal 1.5 would have
fallen out of a narrowed band silently, and the pad you cannot mantle back onto is the one
failure that makes the whole instrument tiring to use.

**The double-jump ceilings use `1 + air_jumps`, not a literal 2.** The table above writes the
double mantle as `jump_height * 2 + climb_band_max`; at the shipping `air_jumps: 1` the two
are the same number, and this one moves if he is ever given a third jump.

**Lane labels are staggered over four heights.** At one height a row of captions 4 m apart
overlaps into a smear from anywhere down the spine. Four rungs rather than three because the
named limits fall every third lane, and a 3-rung cycle put WALK, RUN and SPRINT back on one
line - the three captions most worth being able to read.

**The test has a fifth check.** `shaders/metre_grid.gdshader` is asserted to compile and to
declare 1 m minor and 5 m major spacing. Half the instrument is the surface counting itself -
"a 6 m pillar is six squares tall, no label required" - and a shader that fails to compile
takes that away silently while every box stays exactly where it belongs.
