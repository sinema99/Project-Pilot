# Anime animation (drawn cycles + impact accents)

Status: v2 built 2026-10-21. v1 (clock-stepped poses, below under "History") was built, played and
rejected the same day: "it looks like lag, not intentional or stylized". v2 grilled 2026-10-21, 8
decisions, all recommendations taken.

## What it is

An `ANIMATION` switch, SMOOTH / ANIME (settings, graphics, under LOOK; **U** flips it in play;
**ANIME is the default**). In ANIME the character is smooth except in two places, where the pose is
held like a drawing:

- **Drawn cycles** on locomotion: walk, run and sprint (including the EXIA titan run) show 8
  drawings per cycle - contact, down, passing, up on each foot - at the real foot plants. The
  drawing rate follows his stride by itself (a walk ~7/s, a sprint ~13/s).
- **Impact accents**: a held frame on the moments something hits - landing, wall-jump kick,
  mantle grab, vault plant, rail landing, perfect reflect, and the range dummy taking a hit.

Body rotation, world position, the camera, the world, effects and everything else (idle, jumps,
falls, mantle, vault, slide, reflect spin, equip) are smooth. Only the skeleton pose is held.

## Why v1 failed (kept so it is not rebuilt)

Holding whatever pose the clip happened to be in on a clock tick is what a low frame rate looks
like, at 12 or 24. Limited animation reads as intentional because the drawings are chosen (key
poses, not in-betweens), the same drawings repeat every stride, and timing varies on purpose
(held impacts). v1 also held the whole-body rotation, which snapped his silhouette where the eye
tracks him, and restarting the hold on every move made the rhythm uneven.

## Decisions (v2 grilling)

1. Smooth everywhere except drawn cycles and accents. The clock, its F1-F4 dials, rotation
   holding and the contact-move position hold are removed.
2. Drawn cycles on Locomotion only for now; crouch, wall run, tredge etc. once the run looks right.
3. 8 drawings per cycle (`AnimeHold.drawings_per_cycle`, a multiple of 4).
4. Drawing 1 sits on a real left-foot contact, spaced evenly from there.
   **Departure in the build:** the grilling assumed one clip phase; Locomotion is three
   direction blend spaces (walk, run, sprint) over 22 clips with independent, unnormalised clip
   times, so there is no single phase to read. The contacts are found **live from the blended
   pose** instead (see "Stride tracker"), which keeps the intent - drawings on the real foot
   plants - through any blend, speed or direction.
5. Accents on impacts only (starts would put a held frame where you want instant response).
6. One exported table of `{delay, soft hold, hard hold}` per accent; the delay puts the hold on
   the impact pose instead of the cross-fade frame, the landing's hold scales with the landing's
   strength. Delays measured by tests/_probe_anime_accents.gd: the landing's deepest knee bend
   comes **0.25 s** after touchdown (1.5 m and 4 m drops alike), the vault's hand plant **0.38 s**
   in; wall kick 0.03, mantle grab 0 (hands on the lip from the entry snap), rail land 0.03 and
   perfect reflect 0 are first guesses. **Added in the build:** each accent carries a "still on"
   check asked when the hold would start (landing: still in `jump_land`; vault, mantle, rail: still
   in the move) - a 0.25 s delay otherwise froze a crouch on a player who had already run out of
   the landing.
7. Cycles only above 1.0 m/s ground speed in the Locomotion state; smooth the instant he leaves
   it; the first drawing on entry is the current pose; a running accent finishes first.
8. The dummy gets a hit accent (0.1 s, 0.15 s on a perfect reflect) on its wobble; no cycle.

## How it works

- `AnimePoseHold` (scripts/anime/anime_pose_hold.gd), the last SkeletonModifier3D on the
  skeleton, keeps itself last. Modes: LIVE (does nothing), HOLD (copy once, write back) and CYCLE
  (copy on a drawing, write back between). Skeleton3D restores the un-modified pose after each
  update, so the tree and every other modifier keep running on real time underneath.
- **Stride tracker** (`AnimeStride`, scripts/anime/anime_stride.gd, pure logic): the signal is
  `s = (left foot - right foot) . travel`, in skeleton space, from the live pose. Its peaks are
  the contacts (left foot ahead = left contact) and its zero crossings the passing poses - the
  four quarter boundaries of a cycle. A peak is called once `s` falls back by a small margin
  (about a frame late); crossings only count once `s` has left a dead band, so jitter cannot fire
  them. Between boundaries the remaining drawings of the quarter are spaced by the last quarter's
  length. No boundary for 0.4 s (a stall) takes a drawing and starts over.
- `AnimeHold` (scripts/anime/anime_hold.gd), one per character, runs late in the frame. It picks
  the mode each frame (accent > cycle > live), feeds the travel direction, and owns the accent
  table and the U key. Without a skeleton (the dummy) it holds `inner` node locals instead.

## Probes

- tests/_probe_anime_cycle.gd - holds forward / walk / sprint on the trial pilot: 2026-10-21 walk
  2.5 m/s ~10 drawings/s, run 5 m/s ~13/s, sprint 7.5 m/s ~15/s, contacts and passings in balance.
- tests/_probe_anime_accents.gd (`--fixed-fps 60`) - the landing and vault delays above.

## Tests

`tests/test_anime_hold.gd`: the settings row and default; the stride tracker fires 8 drawings a
cycle on a synthetic stride at walk and sprint rates, puts drawing 1 at the left contact, ignores
jitter in the dead band, takes a drawing on a stall; the hold's mode priority (accent over cycle
over live), the accent delay and length, the landing hold scaling with strength; the modifier's
three modes; pilot9's wiring.

## History: v1 (clock-stepped, rejected)

Built 2026-10-21: every pose (and at first the whole-body rotation) held and refreshed 12/s on a
shared clock, a move change refreshing at once, contact moves holding world position, the reflect
spin at 24/s. Lessons that still apply:

- Never write a non-interpolated child's `global_transform` under an interpolated parent: the
  scene tree draws it at the parent's INTERPOLATED transform times its local, so the model swung
  by up to a physics tick of motion every tick ("fighting", blurry). Solve the local against
  `parent.get_global_transform_interpolated()`. (v2 no longer moves any node.)
- Holding rotation hurt to look at; an uneven rhythm made it worse; 24 beat 12, but no rate fixed
  the "lag" read.
