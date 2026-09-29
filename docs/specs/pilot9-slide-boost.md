# Spec: the slide is a burst, not a brake

> **Status:** specified 2026-09-09, **built the same day, played 2026-09-28 - feels good**.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide.md` (the clip drives the speed),
> `docs/specs/pilot9-slide-hold.md` (the hold's constant speed) and
> `docs/specs/pilot9-slope-momentum.md` (`_slide_bonus`, the terrain term). The entry, the
> clip, the steering, the hold and every exit are unchanged. What changes is the **floor**
> under the speed the clip asks for.
> **Serves:** `docs/game-overview.md` - the parkour direction. A tech that costs speed is a
> tech nobody uses on a route.

## Problem statement

`sprint_speed` is 8.0 m/s. The slide clip travels `slide_distance` 6.46 m in
`slide_duration` 1.25 s, so `_apply_slide_velocity()` - which differentiates the baked
`slide_motion` curve and asks for nothing else on flat ground - averages **5.2 m/s** across
it. Measured frame by frame off the shipped `pilot9.tscn`: the curve peaks at **8.39 m/s**
0.1 s in, is under a sprint for the whole rest of the clip, and `_slide_hold_speed` - the
same curve sampled at the hold frame, and the speed a held slide keeps forever - is
**6.16 m/s**.

So a sprinting pilot9 who presses `crouch` **slows down by about a third**, holds that
slower speed for as long as he stays down, and pays a cooldown for it. On the flat the
slide is strictly worse than not sliding. Only a grade redeems it, and only because
`_slide_bonus` is bolted on top.

That is backwards. A slide is the move you make to *get somewhere faster* - it should read
as a burst you spend, not as a tax you pay.

## The rule

**A slide never runs slower than the sprint it came out of. It opens faster than one, and
eases back down to one over `slide_boost_time`.**

### 1. The floor, not a replacement

Nothing here touches the clip, the curve, `_slide_hold_speed`, or the bonus. A single
scalar - the **floor** - is computed each frame and the clip's own speed is raised to meet
it:

```
base = max(clip_speed_this_frame, floor)
speed = clamp(base + _slide_bonus, 0, slide_max_speed)
```

Three consequences, all of them wanted:

- Where the curve is already **above** the floor the clip drives, exactly as before. At the
  defaults, out of a full sprint, that is nowhere - the floor opens at 10.8 and the curve
  peaks at 8.39 - so a sprinting slide is floor-driven end to end, which is precisely the
  complaint being answered. It matters on the **slow** entries: a slide out of a crouch
  (`pilot9-slide-crouch.md`) sets a reference near 1.6 m/s, and there the clip drives the
  whole way and this work changes nothing at all.
- The bonus still rides on **top**, so a downhill slide is the boost *plus* the grade, and
  `slide_max_speed` is still the one ceiling.
- The bonus can still go **negative** and eat straight through the floor, which is what
  keeps `SLIDE_STALL_SPEED` reachable: a slide steered up a face still runs out of hill and
  still stands up.

### 2. The shape of the floor

```
reference = min(horizontal speed on the entry frame, sprint_speed)
floor(t)  = lerp(reference * slide_entry_boost, reference, clamp(t / slide_boost_time, 0, 1))
```

`t` is seconds since `_start_slide()` - **wall clock, not `_slide_time`**. `_slide_time`
freezes for the length of a hold, and the whole point of the second number is that a player
who is still down there after two seconds is no longer getting the burst.

At the defaults (`slide_entry_boost` 1.35, `slide_boost_time` 2.0, `sprint_speed` 8.0) a
slide out of a sprint opens at **10.8 m/s**, decays linearly, and is at **8.0 m/s** two
seconds in and forever after - so the held slide's flat speed goes from 6.16 m/s to a
sprint's 8.0, and holding one is no longer a choice to go slower. Linear rather than eased: the player is meant to be able to
feel where in the burst they are, and an exponential tail has no moment where it is over.

Two clamps in `reference` are load-bearing:

- **`min(..., sprint_speed)`** so entry speed cannot compound. Without it, a slide entered
  at 20 m/s off a ramp sets a 27 m/s floor that never decays below 20, and a chain of
  slides is a speed exploit rather than a route.
- **the entry speed itself, not `sprint_speed` flat**, so speed is never *created*. The
  automatic slide (`_should_auto_slide()`, steep ground, no press and no sprint needed)
  starts from a standstill: its reference is ~0, its floor is ~0, and gravity does the work
  it always did. A slide is allowed to preserve momentum and to front-load it. It is not
  allowed to hand out momentum that was never earned.

### 3. What the feet do

The clip's forward travel no longer matches his velocity during the burst, so the run-in
foot plant slips - up to 35% on the entry frame, decaying to nothing. This is a knowing
trade and the same one `_slide_bonus` already makes on every grade (`pilot9-slide.md`
called the curve "what keeps his feet with the floor"; the slope work broke that first and
judged it worth it). There is no TimeScale answer available: the `slide` state's clock is
the AnimationTree's own and the hold depends on it - see `pilot9-slide-hold.md`.

If it reads badly in play, `slide_entry_boost` 1.0 turns the burst off and leaves the floor
at a flat sprint, which is still the fix for the actual complaint.

## The dials

| Export | Default | What it does |
| --- | --- | --- |
| `slide_entry_boost` | 1.35 | Multiplier on the entry reference for the floor at t=0. 1.0 = no burst, floor flat at the entry speed. |
| `slide_boost_time` | 2.0 | Seconds the floor takes to ease from the boost back down to the entry speed. 0.0 = no burst. |

## Tests

`tests/test_pilot9_slide_boost.gd`, against the pure `_slide_speed_floor_at()` and against
`_apply_slide_velocity()` on an instanced pilot9:

- the floor opens at `reference * slide_entry_boost` and reaches `reference` at
  `slide_boost_time`, and stays there afterwards
- the reference is clamped to `sprint_speed` from above and is the entry speed from below
- a slide entered at a sprint is never slower than `sprint_speed` on any frame of the clip
- the floor only ever raises: no frame of a boosted slide is slower than the same frame of
  an unboosted one, and a low reference leaves the clip's frames untouched
- a slide with no reference reproduces the old speeds
- a negative bonus still eats through the floor, so the stall exit is still reachable
