# Spec: the hologram pause menu

> **Superseded in part (2026-09-29):** the panel glass, the world-dim numbers and the panel resolution (1280 x 800) now live in [menu-refresh.md](menu-refresh.md).

> **Status:** specced 2026-09-29 from a grilling session; **built 2026-09-29**, not yet played. See
> "Built" at the end for where the build departs from this text.
> **Scene:** `scenes/pilot9.tscn` (the rig), the `UI` autoload (the shell's home).
> **Touches:** `scripts/ui/ui_manager.gd`, `scripts/settings.gd`, `scripts/ui/tabs/tab_settings.gd`,
> `scripts/pilot9.gd` (one hook), plus new files listed under File layout.

## The ask

"I want the pause menu to look like it's a 3D hologram being projected in front of pilot. The
camera would zoom and pan in ... zoom in and pan to over the shoulder. Ideally it would look like
the projection hologram is coming out of pilot's head/helmet." The reference is a screenshot from
behind pilot: **pilot on the left third of the frame, the camera behind him and to his right,
open space on the right** where the hologram goes.

## The rule

**Esc freezes the world as today, then the camera swings to a fixed over-the-right-shoulder shot
and pilot's visor projects the real, working pause menu onto a floating 3D panel on the right of
the frame.** Closing reverses it, and the game stays frozen until the camera is home.

Decided in the grilling, in order:

| # | Decision | Chosen |
|---|---|---|
| 1 | Real menu or decorative intro | **The real menu lives in the hologram.** The shell renders into a SubViewport on a 3D panel for the whole pause. |
| 2 | World while paused | **Hard freeze, as today.** Pilot freezes mid-pose (mid-air, mid-wall-run, anything). Only the camera, the panel, the beam and the visor ring run. |
| 3 | What the shot is anchored to | **Pilot's facing** (yaw), always the same framing. The swing takes a **fixed time** and goes **the short way round**. |
| 3b | Which shoulder | **Camera behind and to his right. Pilot on the left of the screen, hologram on the right**, as in the reference. |
| 4 | Walls | **Camera sweeps and stops short** (with a minimum distance so it never enters his head). **Panel has no depth test** - walls never hide it. |
| 5 | The projection | **Beam only during the open**, then it fades. **The visor seam glows** for as long as the menu is up. |
| 6 | Visor glow source | **Built in engine:** an emissive ring on a `BoneAttachment3D` on `Head`. No Blender change. |
| 7 | Panel look | **Cyan/teal. FX on the glass, text solid.** Scanlines, edge glow and glitch live on the panel background; glyphs and the selected row stay crisp. |
| 8 | The 65 % dim | **Dim the world, not pilot.** Environment darkens + desaturates + vignettes; pilot keeps his lighting and rim light; the hologram glows on top. No 2D dim sheet in hologram mode. |
| 9 | Confirm dialogs in game | **Inside the same hologram**, stacked over the shell as they are today. |
| 10 | Mouse | **Full mouse** via camera-ray / panel-plane intersection -> UV -> forwarded event. **The OS cursor stays visible.** |
| 11 | Panel pose + size | **Flat. Faces the camera, turned 15-20° toward pilot.** About 55 % of screen width and 75 % of height at the final shot. |
| 12 | Timing | Open ~0.55 s to usable, close ~0.3 s, **game stays frozen until the camera is back.** Esc mid-animation reverses from where it is. |
| 13 | In the mech | **Flat shell fallback.** No hologram while pilot is aboard EXIA. |
| 14 | Setting | **HOLOGRAM MENU** on/off row, default on; off = the old flat pause. **CAMERA MOTION off = the camera cuts** instead of orbiting (hologram still shows). |
| 15 | Pilot frozen tilted | **Level shot, tilted emitter.** Framing uses yaw only with world-up; the ring and beam origin ride the real head bone; the panel is always upright. |

Defaults the user accepted without a question of their own:

- The pause shot has **its own fixed FOV**. Sprint FOV, the dash FOV kick and camera sway are
  ignored while it is up, and **everything returns exactly** on close.
- Frozen VFX (afterimages, speed lasers, grind sparks, dust) **stay frozen in place and are dimmed
  with the world** - they are not pilot.
- **The rim light stays on** pilot.
- Changing HOLOGRAM MENU while the menu is open applies to **the next** pause.

## Choosing flat vs hologram

Decided once, at the moment Esc opens the shell, and held until the menu is fully closed:

```
hologram = Settings.hologram_menu
       and a hologram host exists in the tree (pilot9's rig, via a group)
       and pilot9 is visible                # boarding EXIA sets pilot9.visible = false
       and pilot9's Camera3D is the current camera
```

Anything false -> today's flat shell, untouched. That also covers the main menu (no pilot at all),
which keeps its flat standalone settings screen and flat confirm dialog.

The decision is a **pure function** of those four booleans so it can be unit tested without a tree.

## The shot

Computed **once**, on the frame Esc is pressed, from the frozen pose. Nothing moves during the
pause, so there is nothing to track.

- **Basis:** pilot's yaw only (his model's forward, flattened onto the ground plane), world-up. His
  slope pitch, wall-run lean and mantle pose never roll the camera.
- **Target camera position:** behind his head and offset to his **right**, slightly above eye line,
  looking forward past his right shoulder into the panel. Starting numbers (all tunable exports
  on the rig):
  - `shot_back` 1.1 m behind the head
  - `shot_right` 0.55 m to his right
  - `shot_up` 0.15 m above the head bone
  - `shot_fov` 55°
  - Aim: pilot's head sits on the **left third** of the frame; the panel fills the right side.
- **Swing:** from the gameplay camera's current global transform to the target, over
  `open_camera_time` (0.45 s) with ease-out, regardless of distance. The yaw goes the **short way
  round**, so a pause taken while looking at his face never takes a slow 180°. Position and
  rotation are interpolated separately (position along an arc around his head, not a straight
  line through him) so a big swing never passes through his body.
- **CAMERA MOTION off:** no swing. The camera cuts to the target on the first frame, and cuts back
  on close. The beam and panel animations still play.

### Walls

- A **sphere sweep** (same radius idea as the SpringArm backstop in
  `docs/specs/pilot9-camera-collision.md`) from the head bone toward the target. The camera stops at
  the first hit, pulled back by the sphere radius.
- Clamped to `shot_min_distance` (0.45 m) from the head so it can never end up inside his helmet.
  If even that is blocked, it sits at the minimum and clips - a readable menu beats a perfect shot.
- The composition is **never mirrored** to the left shoulder. Pilot-left / holo-right is the rule.
- **Build check:** the tree is paused while this runs. Confirm `direct_space_state` queries still
  answer while `get_tree().paused` is true (the physics server is set inactive on pause). If not,
  run the sweep in the same frame as the Esc press, before `paused` goes true.

### Handing the camera back

The rig **writes `camera_3d.global_transform` and `camera_3d.fov` directly** while the menu is up.
The SpringArm, the camera sway, the sprint and dash FOV code all sit in paused nodes, so nothing
fights it. On open it saves the camera's local transform and fov. The close animation ends
**exactly** on those saved values, then control goes back to the gameplay code as if nothing
happened.

## The projection

### The visor ring

- A `BoneAttachment3D` on the `Head` bone under pilot9's skeleton, holding a **thin emissive ring**
  - a flattened torus (or strip) generated in code, tuned to sit in the visor seam at eye level.
  Tunables: radius, height offset, thickness, tilt.
- Cyan/teal, unshaded, emissive. It is **pilot geometry**, so it is exempt from the world dim.
- Off in gameplay. Lights on at 0.10 s into the open, stays on until the close collapses the panel
  back into it, then goes out.
- Both the ring and the **beam origin** hang off this one attachment, so the beam always leaves
  the real, possibly tilted, helmet.
- The rig nodes are `PROCESS_MODE_ALWAYS`. The attachment itself is fine paused - the bone does not
  move.
- If the ring does not sit well in the seam, the fallback is a Blender visor mesh (grill Q6 option
  B), which replaces only the ring and nothing else.

### The beam

- A cone (or a four-sided frustum) from the visor emitter out to the panel's four corners.
  Additive, unshaded, faint, with a gradient toward the panel and a few scrolling streaks.
- Lives **only during the open**: flares 0.15-0.35 s, fades 0.55-0.85 s. It does not appear during
  the steady state. On close, a short reverse flare can sell the panel collapsing back into the
  visor (optional, same timings compressed into the close).
- No depth test, same as the panel, so a wall between his head and the panel never cuts it.

## The panel

- A flat `MeshInstance3D` quad with a `ViewportTexture` from a `SubViewport` sized
  `panel_resolution` (1600 x 1000 to start). The shell is laid out against 1920 x 1080 today, so
  the build either sets the SubViewport to 1920 x 1080 or lets the shell's anchors reflow into
  1600 x 1000 - pick whichever keeps the settings rows legible. Text sharpness at 1080p+ is the
  bar.
- **Pose:** placed in front of pilot and to his right, so at the final shot it covers about the
  **right 55 % of the screen width and 75 % of its height**. It faces the camera, then is **yawed
  15-20° toward pilot** (`panel_turn`), so its right edge sits a little farther away than its left.
  Upright always (world-up), whatever his tilt.
- **Material:** its own spatial shader, `shaders/ui/hologram_panel.gdshader`:
  - `render_mode unshaded, depth_test_disabled, blend_mix` (or additive for the glass, see below),
    `cull_disabled`, drawn after the world.
  - **Mono cyan/teal.** The viewport's colours are mapped to luminance, then tinted.
  - **FX on the glass, not the words.** Pixels that are the panel's background get the
    translucent tinted glass, scanlines, slow scroll, edge glow and the occasional glitch band.
    Pixels that are text or the selected-row highlight (high luminance in the viewport) render
    near-solid and bright with **no scanline breakup and no flicker**.
  - Uniforms for the open/close: `reveal` (0..1, a scanline wipe from the edge nearest his head),
    `collapse` (0..1).
- **Build pass:** 0.25-0.55 s of the open, driven by `reveal`.

## The world dim (not pilot)

In hologram mode the 2D `_dim` ColorRect stays hidden. In its place:

- The **world** darkens ~40-50 % and desaturates, with a soft vignette.
- **Pilot, the visor ring, the beam and the panel are not dimmed.** Pilot keeps his cel lighting
  and his rim light.

Approach: a full-screen post quad (spatial, reads `screen_texture`) that darkens, desaturates and
vignettes **everything except pixels marked as pilot**. Pilot is marked with the **stencil buffer**
(Godot 4.5+ spatial `stencil_mode`): pilot's meshes write a stencil ref while the menu is up, and
the dim quad only draws where the stencil does not match. The ring, beam and panel are drawn after
the dim quad, so they sit on top regardless.

- The pilot stencil write goes on as an **overlay/extra pass only while the menu is up**, so
  gameplay rendering is unchanged when the menu is closed.
- **Build check:** confirm `stencil_mode` syntax and draw order in 4.6. Fallback if stencils fight
  the cel overlay chain (cel material + ink hull + rim overlay): the dim quad tests depth against a
  "pilot depth" drawn by a pilot-only pass, the same screen-space depth trick the rim light uses.
- Fades in with the camera swing (0-0.45 s), out with the close.
- Frozen VFX are not pilot, so they get dimmed. That is intended.

## The UI side

### Where the shell lives

The `UI` autoload keeps owning the shell and confirm instances. In hologram mode, on open, it
**reparents** `shell` and `confirm` from its CanvasLayer into the rig's SubViewport, and back on
close (only when the mode actually changes between opens). `settings` (the standalone screen) never
moves - it is main-menu only.

`focus_first()` keeps working unchanged - focus is per viewport.

### Paused-until-home

Today `_apply()` sets `get_tree().paused` straight from `resolve()`. The pure `resolve()` stays
**unchanged**, and its tests should pass unedited. The only new rule lives in `_apply()`:

- On a transition to an **empty stack** in hologram mode, the tree **stays paused** and the rig
  plays the close. When the rig reports `closed`, `_apply` finishes: unpause, recapture the cursor,
  move the shell back to the CanvasLayer if needed.
- **Esc during the close** re-opens from the current point: the rig reverses, and the stack gets
  `shell` again as normal.
- **Esc during the open** backs out as normal (`resolve` pops `shell`) and the rig reverses from
  wherever it is.
- There is only ever **one** animation. The rig owns a single `t` (0 = gameplay, 1 = fully open)
  and a direction. Open and close are the same timeline played at different speeds.

### Input

- **Esc / pause** stay handled by `UI._input` exactly as today - it runs before anything reaches
  the viewport.
- **Keyboard / gamepad:** forwarded into the SubViewport with `push_input()` while the menu is up.
- **Mouse:** each mouse event is turned into a ray from `camera_3d` through the cursor, intersected
  with the panel's plane (no physics body - the panel is a quad at a known transform, and with no
  depth test nothing can block it), mapped to panel UV, then to viewport pixels, and forwarded as a
  copy of the event with the new position. Hover, click and slider drag all ride this. Outside the
  quad -> the event is dropped (it does not reach the world, which is paused anyway).
- **All input is blocked until the open reaches `t = 1`** (~0.55 s), so a held Enter or a stray
  click never lands on a panel that is still moving.
- **The OS cursor is visible**, as in any pause. No in-panel reticle.

The ray -> UV mapping is a **pure function** (camera transform, fov, viewport size, panel transform,
panel size, mouse pos -> UV or null) and is unit tested.

## Timing

One timeline, `t` from 0 to 1. The open plays it forward in ~0.85 s total (usable at 0.55 s), the
close plays it back in ~0.3 s (all tracks compressed).

| time (open) | event |
|---|---|
| 0.00 - 0.45 s | camera swings to the shot (ease-out), world dim fades in |
| 0.10 s | visor ring lights |
| 0.15 - 0.35 s | beam flares out |
| 0.25 - 0.55 s | panel draws in (`reveal` scanline wipe from his side) |
| **0.55 s** | **input live** |
| 0.55 - 0.85 s | beam fades; ring stays lit |

Close (~0.3 s): panel collapses toward the visor, beam optional short flash, ring goes out, dim
fades, camera returns to its saved transform and fov. **Unpause happens on the last frame.**

## Setting

New row in `scripts/settings.gd`, next to CAMERA MOTION:

```
[&"hologram_menu", "HOLOGRAM MENU", "controls", ["off", "on"], 1],
```

with a `hologram_menu: bool` getter. `tab_settings.gd` already special-cases the on/off rows in its
apply list (`&"camera_motion", &"movement_effects"`), so add it there. Nothing needs to happen when
it changes - the value is read at the next Esc.

## File layout

New:
- `scripts/pilot9_hologram.gd` - the rig: shot maths, timeline, camera drive, input forwarding,
  ray -> UV. Joins group `hologram_host`. `PROCESS_MODE_ALWAYS`.
- `scenes/pilot9_hologram.tscn` - SubViewport, panel quad, beam, visor ring + `BoneAttachment3D`,
  dim quad. Instanced into `scenes/pilot9.tscn` (via `pilot9_build_scene.gd`, so a rebuild keeps
  it).
- `shaders/ui/hologram_panel.gdshader`, `shaders/ui/hologram_beam.gdshader`,
  `shaders/ui/hologram_dim.gdshader`.

Edited:
- `scripts/ui/ui_manager.gd` - flat/hologram choice at open, reparenting, paused-until-home.
- `scripts/settings.gd`, `scripts/ui/tabs/tab_settings.gd` - the row.
- `scripts/pilot9_build_scene.gd` - instance the rig.
- `docs/specs/ui-shell.md` - a pointer to this spec from "Screen Stack".

## Tests

- **`resolve()` untouched** - the existing UI stack tests pass unedited.
- **Mode choice** - the four-boolean pure function: setting off, no host, pilot hidden (mech), not
  current camera -> flat; all true -> hologram.
- **Shot maths** - given a head position and yaw: the target is behind and to the **right**; a
  tilted pose (pitch/roll on the model) gives the same target as the level pose; the swing yaw
  takes the short way (e.g. 170° vs -190°).
- **Wall clamp** - never closer than `shot_min_distance`.
- **Ray -> UV** - centre of the panel maps to (0.5, 0.5); a ray missing the quad returns null; the
  15-20° turn does not break the mapping at the corners.
- **Timeline** - input is blocked below `t = 1`; the tree is still paused on the frame the close
  starts and unpaused only after it ends; Esc mid-close reverses without resetting `t`.
- **Setting** - the row exists with default "on"; changing it while open does not change the
  current pause's mode.
- **Camera restore** - after a full open/close, `camera_3d` local transform and fov equal what they
  were before Esc.
- Look (colour, glow, scanlines, ring fit, framing) can only be judged in play.

## Out of scope

- A mech version of the hologram (EXIA's head as the emitter). Its own spec if wanted.
- A separate floating panel for confirm dialogs.
- An in-panel hologram cursor.
- A slow-mo ramp into the freeze.
- Any Blender change (the visor mesh is only the fallback if the ring does not fit).

## Known risks

- **Legibility** of a 520-line settings tab on an angled, tinted panel. The mitigations are all
  tunables: `panel_turn`, panel size, `panel_resolution`, and the text-stays-solid rule.
- **Stencil support** in the cel material chain (see The world dim). There is a named fallback.
- **Physics queries while paused** (see Walls). There is a named fallback.
- **Display mode changes** while the menu is up: KEEP THIS DISPLAY MODE opens inside the hologram
  right after the window or 3D resolution changes. The SubViewport is a fixed size, so the panel
  should survive, but this is the first thing to check after a mode switch.

## Built

2026-09-29. Everything above shipped; a windowed probe (`tests/_probe_hologram.gd`) screenshots the
open and confirms the tree stays paused until the camera is home and the camera transform and fov
come back exactly. Departures:

- **No `pilot9_hologram.tscn`.** The rig builds its own nodes in code (`scripts/pilot9_hologram.gd`)
  and pilot9's `_ready()` adds it via `_setup_hologram()`, the same pattern as the item holder, so a
  rebuild of `pilot9.tscn` cannot lose it. `pilot9_build_scene.gd` is untouched.
- **Stencil works in 4.6** (`stencil_mode write / read, compare_not_equal` in
  `shaders/ui/hologram_stencil.gdshader` and `hologram_dim.gdshader`), chained onto the rim overlay's
  `next_pass` (or set as the overlay when the rim is off) only while the menu is up. The depth
  fallback was not needed.
- **The panel has one `reveal` uniform**, no separate `collapse`: the close plays the same timeline
  backwards, so the wipe reverses by itself.
- **The wall sweep runs before the tree pauses** (`_apply` calls `open()` first), which is the named
  fallback for physics queries while paused.
- The glass's alpha is constant: the shell's own background is transparent, so it cannot borrow the
  viewport's alpha.
- Tunables live as exports on the rig (`shot_*`, `panel_*`, `ring_*`). The ring sits on the `Head`
  bone at `ring_offset` (0, 0.08, 0.02); it read as a seam line at eye level in the probe.
