# Spec: pilot9's scroll-wheel camera zoom

> **Status:** built 2026-09-25. **Played 2026-09-28 - feels good.**
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd` only.

## The rule

**Mouse wheel up pulls the third-person camera in, wheel down pushes it out.**

- Each notch moves the zoom target by `camera_zoom_step` (0.5 m), clamped to
  `[camera_zoom_min, camera_zoom_max]` (1.5 m to 8.0 m).
- It starts at `camera_distance` (3.5 m), the authored shot, so nothing changes until the
  player scrolls.
- The travel is the existing spring-arm ease at `camera_transition_speed` - no second
  smoothing path. Walls still win: the zoom sets what the MODE wants, and
  `_camera_obstruction_length()` still shortens it against geometry.
- A trackpad's fractional scroll scales the step by `event.factor`.
- First person ignores the wheel. The zoom is kept and comes back on switching to third.
- The zoom persists for the session - boarding and leaving EXIA does not reset it.

## Framing

**He stays low in the frame at every zoom.** Played 2026-09-25: the zoom felt good, but
zooming out slid him to the middle of the screen. The pivot sits 0.5 m above his middle, which
puts him low at 1.5 m and near centre at 8 m.

So the camera tilts up as the arm lengthens, by just enough to put his middle at a target
screen height:

- **Full zoom-in:** no tilt - wherever the rig already puts him. With the zoom-in drop below
  that is about 59% of the way down the screen at 75 degrees FOV (it was 73% before the drop).
- **Full zoom-out:** `camera_zoom_out_screen_height`, 0.68 - just inside the bottom third.
- **In between:** blended linearly in screen space, so he eases from one to the other and
  never bobs up toward centre on the way.

**The camera also rises as it pulls back**, by `camera_zoom_out_lift` (0.1 m; 0.2 m was a touch high) at full
zoom-out and nothing at full zoom-in, linear between. Asked for after a second play the same day
("bring the camera up a smidge", then "keep zoomed in how it was"). The lift moves CameraPivot
itself, so the wall probe casts from the raised point, and it follows the mode length rather
than the wall-squeezed one so a wall cannot bob it. The tilt accounts for the lift, so the
framing numbers above still hold - the lift only makes the zoomed-out view look down on him more.

**The camera drops as it pulls in**, by `camera_zoom_in_lift` (-0.3 m) at full zoom-in, blending
to `camera_zoom_out_lift` at full zoom-out. Asked for 2026-09-26: "move the camera down so pilot
is more centered when zoomed in all the way, keep zoomed out how it is". The pivot is then 0.2 m
above his middle up close instead of 0.5 m. Full zoom-out is unchanged - its lift and screen
height are the same numbers. Below `camera_zoom_min` (only the ease into first person) the drop
fades to nothing by length 0, so the first-person eye is not lowered.

The tilt is rolled into Camera3D's own pitch, not CameraPivot's, so movement, aiming and the
rail switch (which all read the pivot) are unchanged. It reads the live `spring_length`, so a
wall that pulls the camera in also drops the tilt, and first person gets none. The FOV used is
the base FOV, not the sprinting one, so a sprint does not nod the camera.

## Why `camera_distance` is not what the wheel writes

`camera_distance` is also the reference the body-hide check divides by (hide him below 30% of
it, i.e. 1.05 m, which is what makes the first-person switch read). If the wheel rewrote it,
zooming out from 1.5 to 8 m would divide a lagging 1.5 m by 8 m and blink his body out for a
few frames. So the wheel owns its own `_zoom_distance`, and `camera_zoom_min` stays above the
1.05 m hide line.

## Input

Read in `_unhandled_input()`, after the `frozen` guard, so a menu's scroll container gets the
wheel first and a paused game ignores it. Raw `MOUSE_BUTTON_WHEEL_UP/DOWN`, not an InputMap
action - there is no rebinding screen (see `settings.md`), and no controller binding in this pass.

## Out of scope

Controller zoom, a Settings row for it, and saving the zoom between sessions.
