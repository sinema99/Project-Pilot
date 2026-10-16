# Intro_Movie: the four intro shots back to back

2026-10-15. Grilled with the user. A viewing scene for watching the cutscene shots in a row to
judge how they flow together. It plays the live shot scenes, not recordings, so it always shows
each shot's latest version. Once the shots are locked, Godot's Movie Maker mode can record this
scene into one video.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Order | Shot 1 intro space (12.3 s) -> 2 cockpit (8 s) -> 3 descent (20 s) -> 4 flyover (3 s), ~43 s |
| 2 | Cuts | Hard cut by default: the next shot's first frame arrives on the frame after the last one ends. `cut` export switches to FADE through black, `fade_time` (0.3 s) each way |
| 3 | End | Holds the flyover's last frame. R replays from shot 1 |
| 4 | Controls | R restart the movie, Esc quit, Right / Left arrow next / previous shot. No on-screen overlay. `start_shot` export (1-4) opens it partway |
| 5 | File | `res://Intro_Movie.tscn` in the project root, root node `Intro_Movie`, script `scripts/cutscene/intro_movie.gd`. Not the main scene: open it and press F6 |
| 6 | Live vs recorded | Live, with every shot built ahead of time so cuts don't hitch. Record later if wanted |

The shot scenes are unchanged and still play standalone with their own R / Esc.

## How it works

Every shot is built once at startup and parked, paused at its first frame, in its own SubViewport
(own World3D, window-sized, never draws). Then, under a black cover, each shot is shown live in the
window for `warm_frames` frames in turn. That pays for each shot's `_ready` (procedural ruins,
wrecks, ground, roof bake) and its first draws in the window where nobody sees them.

Showing a shot moves it out of its SubViewport into the movie, re-enables processing, switches off
its own input (the movie owns R / Esc) and calls its `restart()`. Leaving a shot moves it back and
pauses it. The shots chain on their existing `finished` signal.

`Storm` (descent, flyover) writes shared `storm_*` shader globals in `_ready` and turns
`storm_fog` off in `_exit_tree`. Warming both storm shots would leave the globals on the last one
built, and moving a shot between viewports runs `_exit_tree`. So the movie calls `apply()` on the
live shot's storms every time a shot goes live, and sets `storm_fog` off when the live shot has
none.

Not in it: sound, transitions other than cut / fade, any change to the shots themselves.

## Built

2026-10-15. Departures from the plan above, from the windowed probe (`tests/_probe_intro_movie.gd`):

- Warming the shots inside rendering SubViewports did not help: the swap itself took ~1.5 ms, but
  the first frame each shot drew in the window still cost 34-39 ms (vs ~7 ms median). So the
  SubViewports only park the shots (they never draw), and the warm-up instead shows each shot live
  in the window for `warm_frames` (4) frames in turn under the black cover. Cuts then measured 14,
  10 and 26 ms (the last is inside the flyover's own p99 of ~26 ms). Startup under the cover is
  ~2 s.
- Parked shots stay autoplayed but paused at their first frame. With `autoplay` off, the intro's
  `_process` reads a playhead that doesn't exist and logs an error every frame.
- Not fixed, seen while probing: the cockpit's WARNING pop logs "triangulation failed"
  (`holo_display.gd:272`) on its own too.

Tests: `tests/test_intro_movie.gd` (order, hard cuts on `finished`, end hold, a parked shot's late
`finished` ignored, keys, `start_shot`, storm re-applied per live shot, live camera). The storm fog
global itself can't be read under the headless dummy renderer, so the test checks `live_storms`.
