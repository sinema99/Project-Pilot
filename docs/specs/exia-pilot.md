# Spec: Piloting EXIA

## Problem Statement

`assets/Mech_V1.glb` is in the project and standing on the test platform, but it is a prop: a
static model with an autoplaying idle. The mech is called **EXIA**, and the pieces needed to
make it drivable already exist in two places that have never met.

`scenes/mech.tscn` is a `CharacterBody3D` named `EXIA` carrying the whole pilot loop —
interaction area, prompt label, enter/exit, WASD, an exit marker — built out of three box
meshes as a stand-in. `scripts/player.gd` already implements the other half of the handshake:
`enter_vehicle()` hides Setsuna, disables her collider and stops her physics and input;
`exit_vehicle()` puts her back at a given position.

So the work is not to invent a system. It is to put the real model inside the placeholder that
was waiting for it, and to drive its five animations from movement and from the pilot handshake.

## Scope

EXIA is a **walking mech with five clips and nothing else**. Anything the export cannot
animate is out of scope, which settles several questions at once:

- **No jump, no crouch.** `mech.gd` inherited both from `player.gd`. There is no clip for
  either, so both come out. `Space` and `C` do nothing while piloting.
- **No turn clip.** The 2026-09-02 export animates `MECH_turning_L` and `MECH_turning_R`, but
  both are a foot shuffle on the spot: the legs and toes move, no yaw reaches the skeleton, and
  neither covers any ground. Playing one would leave the mech shuffling while the `ROTATE_SPEED`
  lerp did the actual turning underneath it, so both are imported and left unplayed. Wiring them
  in wants a clip that carries the rotation, and is a change to the export first.
- **Movement is WASD, camera-relative, on the ground, under gravity.** Gravity stays so the
  mech settles onto terrain instead of hanging wherever it is placed.
- **Setsuna climbs in.** The 2026-09-02 export carries `embark`, a 2.0 s clip of her scaling
  the machine and dropping into the cockpit, so the placeholder ("her model goes invisible the
  instant `F` is pressed") is gone — see **Embarking** below. **And she climbs back out on the
  same clip played backwards**, so the exit is no longer a cut either — see **Disembarking**. `MECH_launch` is still EXIA's own
  boot-up rather than a mount animation for her, which is why it now waits for the climb to
  finish instead of firing alongside it.

## The five animations

The Blender export carries sixteen actions. Eleven of them are Setsuna's whole action list
(`RUN LOOP`, `DASH`, `SLIDE START` …), retargeted onto the mech because it shares her Rigify
metarig bone names. They play, and they produce nonsense.

`scripts/mech_import.gd` runs as the GLB's import script and **deletes every animation whose
name does not begin with `MECH_`**, so the imported scene carries exactly five. The mech
cannot accidentally be driven by a clip authored for a 1.9 m character, and the AnimationPlayer
in the editor lists five items instead of sixteen. This is the same shape as
`scripts/map_import.gd`, which fixes up the hub blockout on import.

Godot's name-suffix importer already renames them:

| Blender action | Imported as | Loop | Plays |
|---|---|---|---|
| `MECH.idle` | `MECH_idle` | **none — held** | powering down: when nobody is aboard, and again the moment the pilot gets out |
| `MECH.launch` | `MECH_launch` | none — one-shot | the moment the pilot gets in |
| `MECH.standing` | `MECH_standing` | linear — set in `_subresources` | aboard and not moving |
| `MECH.walk.start` | `MECH_walk_start` | none — one-shot | first frame of movement |
| `MECH.walk.loop` | `MECH_walk` | linear — the importer consumed the `.loop` suffix | for as long as movement continues |

All five are 30 frames (1.0 s at the import's 30 fps). `MECH_standing` is a single pose held
across those frames; it loops only so that `current_animation` keeps naming it, which is what
the state machine reads.

**The clips chain by pose, and that is what the animation code is built around:**

```
MECH_idle ends crouched -> MECH_launch starts crouched, ends standing -> MECH_standing
```

So `MECH_idle` is not a resting loop — it is EXIA powering down, and the parked mech's crouch is
that clip's **held last frame**. A non-looping animation leaves the skeleton where it stopped, so
"hold the crouch" costs nothing at runtime: it is the absence of a clip, not a clip. The one rule
this imposes on the state machine is that it must not re-issue `MECH_idle` once it has ended, or
the mech stands up and crouches again once a second.

## The state machine

Four states, driven by two bools — is a pilot aboard, and is the mech moving this frame — plus
the two events from the pilot handshake.

```
                            ┌───── a movement key mid-launch ─────────────┐
                            │                                             v
  PARKED ──F, pilot in──> LAUNCH ──ends──> STANDING ──movement key──> WALK_START ──ends──> WALK
   (holds the crouch)                         ^                                             │
                                              └──────── all keys released ──────────────────┘

  F, pilot out, from any of the three piloted states: MECH_idle plays through, and the crouch
  it ends on is what PARKED means.
```

`MECH_walk_start` is a one-shot with `MECH_walk` queued behind it, the same trick `player.gd`
uses for `RUN START` → `RUN LOOP`; `MECH_launch` is the same shape with `MECH_standing` behind
it. Releasing every movement key returns to `MECH_standing` immediately, even mid-start — a start
clip that has to finish before the mech will stop is worse to drive than one that gets
interrupted. The two scripted transitions, `MECH_launch` and `MECH_idle`, are the exception:
nobody is waiting on them, so they play out.

Standing still means two different things, which is why `piloted` is a parameter. Aboard, it is
`MECH_standing`. Parked, it is the held last frame of `MECH_idle` — and because a one-shot leaves
`current_animation` empty when it ends, a parked mech reads as *nothing playing*. That is exactly
the state to leave alone.

Every clip is started through `_play_chain(clip, next)`, which **clears the queue first**.
Without that, driving off part-way through the launch would leave its queued `MECH_standing` in
place, and the mech would stop dead the instant `MECH_walk_start` ended instead of walking.

The choice is a pure function so it can be tested without a physics frame:

```gdscript
static func clip_for(piloted: bool, moving: bool, was_moving: bool, current: String) -> String
```

It returns the clip to start, or `""` to leave the playhead alone. Returning `""` — rather than
re-issuing the current clip — is what keeps `MECH_walk` from restarting on every frame, and
what lets `MECH_walk_start` and `MECH_launch` run to their ends.

## Entering

The prompt is a plain `Label` on EXIA's own `CanvasLayer`, already in `mech.tscn`. Its text
becomes **`F pilot`** when Setsuna is in range and **`F exit`** while piloting.

Range is the existing `InteractionArea`, sized off the mech: a 12 x 9 x 12 box, which clears
the 7.62 m arm span by about 2.2 m on each side. `body_entered` only latches bodies that
answer to `enter_vehicle`, so scenery entering the box cannot arm the prompt.

`F` is read in `_unhandled_input` on `mech.gd`. While Setsuna is piloting her own
`_unhandled_input` is switched off, so the key cannot be claimed twice.

## Embarking

`F` no longer hands her body straight over. It starts a **climb**, and the mech's boot-up waits
for it:

```
  F pressed ──> she is put on the mount mark, `embark` plays (2.0 s), EXIA holds its crouch
            ──> clip ends ──> MECH_launch starts, MECH_standing behind it; she is held on
                              embark's last frame and rides the cockpit shut
            ──> MECH_launch ends ──> enter_vehicle() hides her
```

She is **not** hidden the instant the climb ends. `MECH_launch` slides EXIA's canopy
(`spine.003`) shut over its own length, and for that beat she has to stay on screen sitting in
it — hiding her the frame the boot-up starts drops her out from under a canopy that is still
open. See **The canopy close** below.

The clip is authored travel, all of it. Her body does not move — `embark` translates her bones
from a standing pose at ground level to a seated one 6.2 m up, and every metre of that climb is
in the animation. That makes **where she is standing when it starts** the whole of the wiring:
start it a metre off and she climbs into thin air beside the mech.

### The mount mark

`EmbarkPoint` is a `Marker3D` on the mech, the same shape as `ExitPoint`: `mech.gd` puts the
pilot on it (position and yaw, less the root-motion correction below) and the clip does the rest. Its transform is **measured out of
the two GLBs**, not eyeballed, because both rigs are exported from the same Blender file and the
climb was authored against the mech where it stands in that file:

| | |
|---|---|
| Setsuna's armature, in the export | the origin, unrotated, scale `0.9343115` — so she stands at Blender `(0, 0, 0)` facing `+Z` |
| EXIA's armature, in the export | `(0, 6.60846, 4.213517)`, yawed `+90°`, scale `1.7267632` |
| EXIA's *body* origin | `6.609566` below its armature (that is what `Model`'s offset is), so Blender `(0, 0, 4.213517)` — on the ground, nose along `+X` |

Undoing the mech's `+90°` to get into its own space: she starts at mech-local
**`(4.213517, 0, 0)`** — 4.21 m out from the centreline, square to the nose, clear of the 4 m
wide hull by 2.2 m and well inside the 12 m interaction box — facing mech-local `-X`, which is
a **`-90°`** yaw. That is `EmbarkPoint`.

Three independent readings confirm the fit, and are the check to redo after a re-export:

- `embark`'s **first** spine frame is bit-identical to `IDLE`'s, position and rotation both, so
  she starts in her ordinary standing pose and nothing has to be blended into it.
- Her spine **ends** at Blender `(0.9535, 6.216, 4.2374)`, which is mech-local
  `(-0.024, 6.216, 0.954)`: dead on the centreline, 6.22 m up, 0.95 m forward of the mech's
  origin. A cockpit, on an 8.4 m machine.
- Her spine's **final rotation** is a `+90°` yaw, which in mech space is `0` — she ends facing
  out over the mech's own nose.

### Root motion moves the machine out from under the mark

The mark alone put her **2.17 m too far forward**, standing on the front of the chest with the
open canopy behind her, and the two features have to know about each other to fix it.

Her climb was authored against EXIA crouched at the end of its power-down. In Blender that pose
stands **2.17 m along the mech's nose**, because `MECH_idle` walks the machine forward as it
powers down and the travel is in the skeleton. `mech.gd` takes exactly that travel out of the
skeleton and hands it to the body instead (see **Root motion**), so on screen the crouch stands
2.17 m *behind* where the climb expects to find it. The clip cannot know that; the mount mark has
to give it back:

```gdscript
mount = EmbarkPoint.global_position - global_transform.basis * pose_travel
```

`pose_travel` is what the pose currently on screen has had taken out of it — the same curve root
motion is driven by, sampled rather than written down, so a re-exported power-down that travels a
different distance retunes the mount on its own. It is **held when a one-shot ends**, which is the
one thing about it that is not obvious: the parked mech's crouch is `MECH_idle`'s last frame, so
the displacement is still on screen long after the clip stopped, and `_travel_now()` reads zero
for a mech with nothing playing. That held value is exactly the state she climbs into. Sampling
the curve's end rather than the playhead's last position also keeps the final physics frame from
costing a few centimetres.

Measured in the engine, hip to hip against the mech's own skeleton, she now lands **1.1 mm** from
the offset the two exports were authored with — `(-0.0235, 3.644, -0.6425)` in the mech's frame.

The snap onto the mark is a cut, and deliberately so: she can press `F` from anywhere in the
interaction box, and there is no walk-to-point behaviour. The camera pan starting on the same
frame is what carries it. Arming the prompt only near the mount mark is the fix if the cut reads
badly, and it is out of scope until it does.

### Waiting for her

`embark_left` is the mech's countdown, and it is a third state rather than a flag on the two it
had. While it runs:

- **EXIA is not hers to drive yet.** `_physics_process` takes the parked branch — gravity,
  friction, `_drive_animation(false, false)`, root motion — so the machine holds the crouch
  `MECH_idle` left it in, exactly as if nobody had pressed anything.
- **`F` does nothing.** The climb owns her; there is nothing to press until she is aboard, and
  the prompt is hidden for its whole length.
- **The camera pan runs anyway**, and mouse look with it. It sets off from her view on the frame
  `F` is pressed and lands on EXIA's own camera 0.6 s later — which is the shot that frames a
  person climbing an 8.4 m machine, so the remaining 1.4 s of the climb is watched from there.

When it reaches zero the mech starts `MECH_launch` with `MECH_standing` queued behind it.
Everything downstream of that — the interrupted launch, the root motion across the clip change,
the queue — is unchanged, because from the launch's point of view nothing happened except that
it started 2 s later. What is new is that `enter_vehicle()` no longer fires here — it waits out
the launch, see **The canopy close**.

The climb settles at **t ≈ 1.5 s** and holds the cockpit pose for the last half second, so there
is a beat before the boot-up. Firing `MECH_launch` at 1.5 s rather than 2.0 s is the knob if
that beat is too long; the wait is the clip's own length, so a re-timed export moves it on its
own.

**A missing clip skips the whole thing.** `embark_length()` returns `0.0` when the export has no
`embark` — it is in `KEEP` in `scripts/setsuna_import.gd`, and that is the only switch — and a
zero-length climb boards her on the spot, which is what `F` did before this section existed. A
vehicle with no `EmbarkPoint` does the same. Neither is an error path; both are the placeholder,
still working.

### The canopy close

`MECH_launch` slides EXIA's canopy shut as it boots up, and the canopy is one bone: `spine.003`,
a child of `spine.002` up in the chest. It is still open on the launch's first frame and shut on
its last. Hiding Setsuna the moment the launch starts — which is what the code did before this
section — drops her out from under a canopy that is still halfway open, in full view of the
mech's own camera.

So `enter_vehicle()` waits for the launch. `seal_left` is a **fourth** countdown state, the same
shape as `embark_left`: set in `_board()` to `MECH_launch`'s own length, spent one frame at a
time. While it runs:

- **She stays on screen, held on `embark`'s last frame.** `embark` is `LOOP_NONE`, so once it
  ends the skeleton keeps the seated pose with no clip playing and player.gd's physics is already
  off (`_hand_over_controls` ran when the climb began) — she is frozen seated for free.
- **She is carried by `spine.003`.** `_board()` records the cockpit bone's world transform and
  her root's world transform at the instant the launch starts. Each `_physics_process` after
  that, `mech.gd` replays the bone's motion onto her root through `pilot.ride()`:

  ```gdscript
  seat_follow(cockpit_now, cockpit_board, pilot_board) ==
      cockpit_now * (cockpit_board.affine_inverse() * pilot_board)
  ```

  which is a rigid attach: her root, expressed once in the bone's frame, replayed against the
  bone's live transform. On the first frame `cockpit_now == cockpit_board` and she does not
  move. The bone's transform is read **after** `_apply_root_motion()`, so the ~1.66 m
  `MECH_launch` walks the body forward is already in it — she rides the mech forward and the
  canopy down together, with no separate root-motion handling of her own.
- **`F` does nothing and the prompt stays hidden**, the same as during the climb: the climb and
  the canopy close are one uninterruptible sequence. Movement input is dead too — the sealing
  branch takes friction and gravity only, and leaves `MECH_launch` to play through to the queued
  `MECH_standing`.

When `seal_left` reaches zero, `enter_vehicle()` hides her. Nothing is undone: her nodes never
changed parent, `ride()` only wrote `global_transform`, and the next `exit_vehicle()` overwrites
it with the ExitPoint teleport.

**No `spine.003`, or no `MECH_launch`, skips it.** `_board()` looks the bone up once at load;
`find_bone` returning `-1`, or the launch clip being absent, leaves `seal_left` at `0.0` and
`enter_vehicle()` fires from `_board()` on the spot — which is exactly what it did before this
section existed. Like the missing-`embark` path, it is the placeholder still working, not an
error.

## Disembarking

`F` in the cockpit is the entry run backwards, and it needs no new animation:

```
  F pressed ──> MECH_idle starts, EXIA powers down; she is on screen again, held on embark's
                last frame, riding the cockpit back open (1.0 s)
            ──> MECH_idle ends ──> `embark` plays from its last frame to its first (2.0 s),
                                   carrying her back down the machine onto the mount mark
            ──> clip ends ──> exit_vehicle() hands her body back where she is standing, and the
                              camera pans out of EXIA's view into hers
```

`MECH_idle` is the power-down, and where the canopy is concerned it is `MECH_launch` with its
ends swapped: `spine.003` runs from `(0, 1.9038, -0.4279)` shut to `(0, 1.8729, -1.5857)` open,
which is the launch's own two frames the other way round. So EXIA opens its cockpit on the way
out with nothing written for it, over the 1.0 s the power-down takes.

And `embark` played from its end to its start **is** the dismount. The climb is authored travel
with her body held still — she begins standing on the mount mark and ends seated 6.2 m up — so
running it backwards begins her seated 6.2 m up and ends her standing on the mark. Nothing about
the clip has to be symmetric for that to read: it is the same two seconds of hands and feet on
the hull, going the other way.

### The two countdowns

They are the entry's two mirrored, and they hold the same rules: `unseal_left` is `MECH_idle`'s
own length, `disembark_left` is `embark`'s.

- **`pilot` stays set for the whole of it.** She is not handed back until her feet are down, and
  EXIA is nobody's to drive from the frame `F` is pressed: movement input is dead through both
  countdowns, `F` does nothing, and the prompt is hidden — the same rule the climb in has, for
  the same reason.
- **She rides the canopy out on the same `seat_follow`.** `_cockpit_board` and `_pilot_board`
  were recorded when the launch started, and the offset between them,
  `cockpit_board.affine_inverse() * pilot_board`, is expressed in the cockpit bone's own frame —
  so it is still the seated pose however far the mech has walked since, and the exit re-measures
  nothing. The bone's rotation track is a single key, so the ride out is a pure translation:
  the canopy slides and she goes with it.
- **The descent starts from the mount mark again.** `_mount_position()` is read at the end of
  the power-down, and by then the mech is holding `MECH_idle`'s last frame carrying the same
  2.17 m of travel as the parked machine she climbed into — so the mark lands where it did on
  the way in, which is the spot the reversed clip needs her body on. It is also, to within a
  frame, where the canopy ride has just left her, so the snap onto it is not one that shows.
- **The camera stays on EXIA's** until the descent ends. The entry pans out of her view on the
  frame `F` is pressed, so the climb up is watched from the machine; the exit is that mirrored,
  so the climb down is watched from there too and the pan back into her view is the last thing
  that happens rather than the first. Mouse look stays live throughout, as it does on the way up.

She is handed back **where the descent leaves her** — standing on the mount mark, facing the
machine — rather than at `ExitPoint`. Teleporting her round to the back of the mech after she
has just climbed down the front of it is the one thing the descent cannot survive.

**Anything missing falls back to the cut.** The descent needs every piece the climb needed —
an `EmbarkPoint`, the `embark` clip, `spine.003`, and both `MECH_idle` and `MECH_launch` (the
launch because it is what recorded the seated offset) — and if any is absent `F` hands her
straight back at `ExitPoint` and plays the power-down under her, which is what the exit did
before this section existed. `ExitPoint` stays in the scene for exactly that path.

## Root motion

The clips travel, and until this section existed the body did not.

`MECH_idle` steps the mech **1.26 m** forward as it powers down and `MECH_launch` a further
**0.96 m** as it stands back up, so by the last frame of the boot-up the mech is **2.219457 m**
in front of the pose `MECH_standing` holds. Nothing moved the `CharacterBody3D` while that
happened, so the moment the queued `MECH_standing` took over it yanked the mech back the whole
2.22 m — a snap at the end of every launch, with the collision box having sat still through an
animation that walked the mesh two metres away from it.

The travel is authored as a translation of the **whole armature**. This rig has six unparented
bones — the hip (`spine`), the upper torso (`spine.002`), both hands and both feet — and each
one's last `MECH_launch` frame lands exactly 2.219457 m ahead of its own `MECH_standing` value.
The four parented bones (`upper_arm.L/R`, `thigh.L/R`) are keyed in their parent's space and
never saw the translation at all.

So `mech.gd` splits the travel out of the skeleton when the mech loads and replays it on the
body instead, which is what root motion means:

- `split_travel()` subtracts the hip's **horizontal** drift from every unparented bone's
  position track. That leaves the clips playing on the spot and makes `MECH_launch`'s last frame
  identical to `MECH_standing`'s pose — there is nothing left to snap back from.
- The drift it removed is kept as a one-track `Animation` and sampled every physics frame, and
  the difference since the last frame is handed to `move_and_collide()`. The mech — mesh,
  collider and camera together — covers exactly the ground the animation covered.

Three things follow from the details:

**Only x and z come out.** The hip drops 1.10 m through the crouch, and that *is* the crouch.
A body standing on the ground has nowhere to put it, so the vertical stays in the skeleton.

**Travel is measured from `MECH_standing`'s pose, not from each clip's own first frame.** That
is what makes the chain add up: `MECH_launch` opens 1.26 m along, where `MECH_idle` left the
mech, and that carried-over 1.26 m has to come out of the skeleton too or it snaps back at the
end of the launch just the same. It also means the power-down is root motion as well — parked
is not the same as anchored, so `_apply_root_motion()` runs in the unpiloted branch too.

**A clip change contributes nothing.** The new clip starts wherever it starts and the body has
already been walked there by the clip before it, so reading the difference across that boundary
would double the last one back on itself. This is also what makes an interrupted launch behave:
driving off mid-boot-up keeps the ground already covered and abandons the rest, with no pop,
because the skeleton is no longer holding a displacement that has to be given back.

Nothing about the render changes. The mech still sweeps forward through the boot-up, and its
feet still stay planted while it does — a foot that holds still in the world has to travel
backwards through a body that is moving forwards, which is precisely what subtracting the drift
from the toe tracks leaves behind. What changes is that the hitbox goes with it, and that the
mech genuinely ends each pilot cycle 2.22 m ahead of where it started.

`MECH_walk` and `MECH_standing` do not travel — the walk is an in-place cycle driven by `SPEED`
and the standing pose is a single held frame — so neither gets a curve, and root motion never
fights the velocity that already moves the mech.

The split rewrites the imported `Animation` resources, which are shared by every instance of
the GLB, so the curves are cached statically per resource: a second mech reads them back
instead of re-deriving them from tracks the first one already flattened.

## Geometry

Measured from the imported GLB, not eyeballed — from the *skinned* mesh at `MECH_standing`,
which is what the player sees, rather than the mesh's own bind-pose bounds. Up to the 2026-09-01
export the armature origin sat **6.609566 m above the soles** and `Model` was offset by exactly
that; the 2026-09-02 export moved the origin down to the feet, so that offset is now ~0 and the
model stands on the body origin, where a `CharacterBody3D` needs it.

That same export is also **yawed a quarter turn**, and the yaw is exactly one number: a **+90°
Y rotation on the `metarig_001` armature node**. Nothing is baked wrong underneath it - the bone
rests and every clip are still built around a `+Z` nose, which is why the raw travel tracks still
read `+Z` - the whole rig is simply turned on its way out of Blender.

`mech.gd` steers by `facing_for()`, which is `+Z`, so `Model` carries a `-90°` counter-rotation
(and the `x = 4.213517` that re-centres the armature's own offset). **This is a stopgap, not a
design choice**: the rotation is being applied at the source, and the export that lands it should
take `Model` back to an identity basis. `test_the_model_faces_the_way_the_mech_walks` asserts the
composition of the two rotations rather than either alone, so a fixed export swings the nose onto
`-X` and fails it; `test_the_export_is_still_yawed` fails alongside it, naming the change.

The numbers below are the 2026-09-01 re-export, which grew EXIA from 5.87 m to **8.40 m tall,
7.62 m across the arms and 4.15 m deep**. It reaches that size with a **1.7268 scale on the
`metarig_001` node**, which is why bone units are no longer metres — see the root motion section
and `travel_scale_for`.

| | Value | Why |
|---|---|---|
| Model transform | `-90°` about Y, `(4.213517, 0.00112, 0)` | un-yaws the export and puts the soles on the body origin |
| Body collider | `BoxShape3D(4, 8.55, 3)` at `y = 4.275` | torso and legs only — the arms are not solid |
| Interaction area | `BoxShape3D(12, 9, 12)` at `y = 4.4` | arm span plus ~2.2 m |
| Exit point | `(0, 0, -3.6)` | the fallback handback, straight out of the back, clear of the collider's 1.5 m half-depth |
| Camera pivot | `y = 7.9` | just under the 8.4 m head |
| Spring arm | `17.5` | held back in proportion as the mech grew |

`SPEED` is `7.0`. The first guess of `10.0` read as a skate and was halved to `5.0`, but that
was tuned against the 5.87 m mech; the re-export made it 1.43x taller, so its stride covers
1.43x the ground per cycle and `5.0` left it moonwalking. A walk cycle has an implied stride
length, and any speed the clip does not cover will foot-skate in one direction or the other.

## Out of scope

Mech collision against the world beyond the box; a seat or cockpit; walking her to the mount
mark instead of cutting her onto it; a dismount clip of its own (`embark` runs backwards
instead); lift off the ground (`MECH_launch` steps forward but never leaves the floor);
matching walk speed to stride length; damage, weapons, or a mech HUD.

## Verification

Headless tests cover what does not need a viewport: that the import script leaves exactly the
eight `MECH_` clips with the right loop modes, that `clip_for` produces the state machine
above, and that the `EXIA` scene still exposes the nodes `mech.gd` reaches for.

The climb is tested the same way, since the mount mark is geometry and the clip is a resource:
that `embark` survives Setsuna's import as a one-shot of the length the wait is derived from,
that `EmbarkPoint` sits off the mech's flank at the distance measured above and faces the
machine, that the pull-back is the 2.17 m `MECH_idle`'s own travel curve is worth, that the pilot answers to `begin_embark()`, and that the clip really does start from
`IDLE`'s pose and end on the mech's centreline. Whether the climb *lands* — whether her hands
meet the hull, whether the pan is looking the right way while she does it — is a play session.

The canopy close is tested where it is not a physics frame: that `seat_follow` is a rigid
attach — that she does not move on the first frame, that a translation of the cockpit bone
translates her one for one, and that a rotation of it carries her round with her offset
preserved; that the imported Mech_V1 skeleton has a `spine.003` bone, that it is parented (so
the root-motion split never touches it and its world transform carries the mech's forward travel
for free), and that it is not one of the travel roots; and that the pilot answers to `ride()`.
Whether she visually holds the seated pose while the canopy shuts, and whether the follow lags,
is a play session.

The descent is tested as the mirror of both: that `MECH_idle` opens the canopy bone the launch
shuts — its first and last `spine.003` frames are the launch's last and first — so there is a
cockpit to come out of; that the power-down is the 1.0 s the ride out is timed from; that the
seated offset `seat_follow` is given still puts her in the same place after the mech has walked
somewhere else, which is what lets the exit reuse the boards the entry recorded; and that the
pilot answers to `begin_unseal()` and `begin_disembark()`. Whether the climb reads as a climb
with its frames reversed — whether her feet land where they should and the descent does not look
like a rewind — is a play session, and the first thing to look at.

The root motion split is testable the same way, because it is a rewrite of an `Animation`
rather than a physics frame: that the imported `MECH_launch` really does end 2.22 m ahead of
`MECH_standing`, that after the split every unparented bone lands on its standing pose, that
the crouch stays in the skeleton, that the curve carries the full 2.22 m and not just the
launch's own 0.96 m, and that the parented bones and the two clips that stay put are left
alone. The tests work on duplicates: the split rewrites shared imported resources.

Everything about feel — whether 10 m/s is right, whether the walk reads at that scale or skates,
whether the launch is worth watching, whether the camera boom is long enough — is a play session,
not a test.
