extends RefCounted

# EXIA's two white back panels: heavy storage boxes hung off the back of the shoulders.
# See docs/specs/exia-back-panels.md.
#
# THE RULE (rev 6, 2026-11-12, the user's): each box's top front edge is a hinge fixed to its own
# shoulder bone. One angle, shared by both boxes and held against the upright mech, is the only thing
# that changes, and it only moves the bottom. Nothing slides a box, nothing stands one on its bottom
# edge. tests/_probe_mech_panels_hinge.gd checks the hinge never leaves its shoulder.
#
# The placement is written in the mech BODY frame (metres, nose +Z, soles at y = 0) at
# MECH_standing, measured from the skinned mesh, so it does not depend on the bones' axes or the
# armature's 1.7267 scale. build() turns each hinge into an offset in its shoulder bone's frame once.

## The shoulder each box hangs from, by side. shoulder.L sits on the mech's +X, the side +1 slab
## (PanelR); the side -1 slab (PanelL) is on -X with shoulder.R.
const BONES := {-1.0: "shoulder.R", 1.0: "shoulder.L"}
const WIDTH := 1.0
## 1.0 m, as thick as it is wide (user, 2026-11-12); grows BACKWARD from the front face.
const THICKNESS := 1.0
## Centre of each slab across the back; the inner edges sit at +-1.25, a 2.5 m gap.
const CENTRE_X := 1.75
## Top level with the pauldrons, bottom just above the feet (they top out at ~0.46).
const TOP := 8.0
const BOTTOM := 0.5
## The body's back in the panels' own lane (|x| 1.25..2.25), y 5..8, at MECH_standing. Not the
## backpack between them (-2.12), which put the slabs a metre off the body (2026-11-12).
const SHOULDER_BACK := -1.15
## Front face almost touching the body (2026-11-12).
const GAP := 0.05

## The angle, held against the upright mech (its body frame, banked with the model). Positive =
## bottom out behind. Standing and running are picked; the kneel is the kickstand (kickstand_deg).
const STAND_TILT_DEG := 10.0
## Running (Loco.RUN, run and sprint).
const RUN_TILT_DEG := 25.0
## Stand -> run eases out over this, run -> stand back over this (smoothstep, no overshoot).
const RUN_OUT_TIME := 0.25
const RUN_BACK_TIME := 0.4
## The kneel weight follows the power-down / boot-up clip; this caps how fast it may move, so a
## boot-up cut short by a movement key folds the slabs out instead of snapping them.
const KNEEL_MAX_RATE := 4.0

const NODE_PREFIX := "BackPanels"


## Length along the slab, top to bottom, FULL (the mesh's own size; a slab is scaled down from it).
static func length() -> float:
	return TOP - BOTTOM


## Cargo-driven length (2026-11-13): the panels shrink with how full the stash is, in 4 steps. Empty
## is a 1 m cube at the hinge, never hidden; any cargo up to a third is the first step, up to two
## thirds the second, over that the full length. Both slabs share it.
const MIN_LENGTH := 1.0
const FILL_STEPS := 4
## The length eases to a new step over this (seconds).
const LENGTH_EASE_TIME := 0.3


## Occupied cells / total cells of `grid`, 0..1. No grid = empty.
static func fill_fraction(grid: ItemGrid) -> float:
	if grid == null or grid.width * grid.height <= 0:
		return 0.0
	var used := 0
	for it: ItemStack in grid.items:
		var fp := it.footprint()
		used += fp.x * fp.y
	return clampf(float(used) / float(grid.width * grid.height), 0.0, 1.0)


## The stepped length for `fill`: 0 -> MIN_LENGTH, then even steps up to length() above 2/3.
static func length_for_fill(fill: float) -> float:
	if fill <= 0.0:
		return MIN_LENGTH
	var step := clampi(ceili(fill * (FILL_STEPS - 1) - 0.00001), 1, FILL_STEPS - 1)
	return lerpf(MIN_LENGTH, length(), float(step) / float(FILL_STEPS - 1))


## The attachment node on `side`'s shoulder bone, and the slab under it.
static func attachment_name(side: float) -> String:
	return NODE_PREFIX + ("L" if side < 0.0 else "R")


static func slab_name(side: float) -> String:
	return "PanelL" if side < 0.0 else "PanelR"


## The hinge (the middle of the top front edge) in the body frame at MECH_standing.
static func hinge_standing(side: float) -> Vector3:
	return Vector3(CENTRE_X * side, TOP, SHOULDER_BACK - GAP)


## The hinge as an offset in the shoulder bone's frame: `shoulder_standing` is that bone in the body
## frame at MECH_standing. Fixed for good once built.
static func hinge_offset(shoulder_standing: Transform3D, side: float) -> Vector3:
	return shoulder_standing.affine_inverse() * hinge_standing(side)


## The hinge this frame, `shoulder` the bone in the body frame now.
static func hinge(shoulder: Transform3D, offset: Vector3) -> Vector3:
	return shoulder * offset


## A slab hung from its hinge, tilted `deg` against the upright mech (bottom out). Local +Z of the
## slab faces the mech.
## `len` is the slab's current length (scaled from the full mesh); the hinge stays on its top edge.
static func hung(hinge_point: Vector3, deg: float, slab_len: float = -1.0) -> Transform3D:
	if slab_len < 0.0:
		slab_len = length()
	var b := Basis(Vector3.RIGHT, deg_to_rad(deg))
	var origin := hinge_point - b * Vector3(0.0, slab_len * 0.5, THICKNESS * 0.5)
	return Transform3D(b.scaled_local(Vector3(1.0, slab_len / length(), 1.0)), origin)


## The parked kneel's kickstand: the angle that puts the lower box's bottom front edge (its lowest
## point while it swings out, 0..90 deg) on the ground, y 0. Fitted to the LOWER hinge, so no box goes
## below the floor; the other hovers by the hinges' height difference. A hinge higher than the box is
## long can't reach the floor: 0, hanging straight.
static func kickstand_deg(lowest_hinge_y: float, slab_len: float = -1.0) -> float:
	if slab_len < 0.0:
		slab_len = length()
	return rad_to_deg(acos(clampf(lowest_hinge_y / slab_len, 0.0, 1.0)))


## The one angle both boxes hold. `run` 0..1 stand -> run, `kneel` 0..1 -> parked, `sway` the rev 5
## swing (degrees, positive out), `kick` the kickstand, `clearance` the floor the baked table sets
## through the power-down and boot-up (NO_FLOOR elsewhere): the box never swings in past it.
static func angle(run: float, kneel: float, sway: float, kick: float, clearance: float) -> float:
	var hanging := lerpf(STAND_TILT_DEG, RUN_TILT_DEG, run) + sway
	return maxf(lerpf(hanging, kick, kneel), clearance)


## How far into the parked kneel the clip on screen is. MECH_idle folds in as it powers down and
## MECH_launch opens back out as it boots up, both on a smoothstep of the clip time. `parked` with
## nothing playing is the held crouch.
static func kneel_target(current: String, clip_pos: float, clip_length: float, parked: bool) -> float:
	var u := clampf(clip_pos / clip_length, 0.0, 1.0) if clip_length > 0.0 else 1.0
	match current:
		"MECH_idle":
			return smoothstep(0.0, 1.0, u)
		"MECH_launch":
			return smoothstep(0.0, 1.0, 1.0 - u)
		"":
			return 1.0 if parked else 0.0
	return 0.0


## Rev 6: through the power-down and boot-up the body moves into the boxes. The fix is the angle,
## never a slide: the smallest angle (degrees) that keeps the skinned body out of BOTH boxes, one
## value for both since they share the angle, at 41 even steps of the clip. Baked by
## `tests/_probe_mech_panels_transition.gd -- bake` (eased 0.2 s ahead / 0.35 s behind like rev 4c);
## re-bake after a Mech_V1 re-export. The user's accepted clips are left out (2026-11-12): parked, the
## ground wins over the right upper arm and the kneeling left leg; and the boot-up's 0.15-0.33 s, where
## the chest rises into the right box's hinge and no angle can clear it, keeps the normal swing.
const CLEARANCE := {
	"MECH_idle": [0.0, 0.0, 0.0, 0.0, 0.0, 0.39, 1.43, 2.9, 4.58, 6.25, 7.72, 8.94, 10.2, 11.57, 13.03, 14.56, 15.91, 17.09, 18.35, 19.39, 20.26, 21.14, 22.06, 22.76, 22.76, 22.76, 22.43, 21.5, 20.07, 18.25, 16.12, 13.8, 11.38, 8.96, 6.64, 4.51, 2.69, 1.26, 0.33, 0.0, 0.0],
	"MECH_launch": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.84, 3.06, 6.2, 9.81, 13.41, 16.55, 18.77, 19.61, 19.61, 19.61, 19.32, 18.52, 17.43, 16.27, 14.92, 13.93, 12.85, 11.84, 10.87, 9.89, 8.92, 8.11, 7.16, 6.33, 5.42, 4.47, 3.51, 2.6, 1.77, 1.05, 0.5, 0.0],
}
## A clearance that drops (a boot-up cut short) eases back at this many deg/s; a rising one applies
## at once, so it is never late.
const CLEARANCE_RETURN_RATE := 120.0
## The clearance outside those clips: below any angle the poses and the sway can reach.
const NO_FLOOR := -90.0


## The clearance floor at `u` (0..1) through `clip`, degrees. NO_FLOOR for any other clip.
static func clearance_for(clip: String, u: float) -> float:
	if not CLEARANCE.has(clip):
		return NO_FLOOR
	var table: Array = CLEARANCE[clip]
	if table.size() < 2:
		return NO_FLOOR
	var f := clampf(u, 0.0, 1.0) * (table.size() - 1)
	var i := mini(int(f), table.size() - 2)
	return lerpf(float(table[i]), float(table[i + 1]), f - i)


## One frame of the stand <-> run swing: `lin` is the linear timer, returns its next value. Show
## smoothstep(0, 1, lin).
static func step_run(lin: float, running: bool, delta: float) -> float:
	if running:
		return minf(lin + delta / RUN_OUT_TIME, 1.0)
	return maxf(lin - delta / RUN_BACK_TIME, 0.0)


## The mech body's own imported surface material (the export's one unnamed pure-white slot), so
## ApplyCelMech's derive pass keys the slabs to the very material it gives the body. Without it the
## box has no slot and gets the applier's base swatch, a warm grey. Fallback: plain white.
static func body_material(skeleton: Skeleton3D) -> Material:
	for node in skeleton.get_children():
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var mat := mi.mesh.surface_get_material(0)
			if mat != null:
				return mat
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	return white


# --- Rev 5: the heavy swing (docs/specs/exia-back-panels.md "Rev 5") ---------------------------------
# One hinge angle shared by both slabs, in degrees, positive = bottom out. A damped spring driven by
# the mech's forward acceleration, plus kicks (angular velocity, deg/s) for footfalls, take-off and
# landing. State is a Vector2(angle, angular velocity).

## ~1 s swing, one overshoot then settled.
const SWAY_PERIOD := 1.0
const SWAY_DAMPING_RATIO := 0.35
## Static swing per m/s^2 of forward acceleration: lags out speeding up, carries in slowing down.
const SWAY_DEG_PER_ACCEL := 0.3
## The acceleration fed in is clamped and low-passed: STAND's instant stop is one 540 m/s^2 tick.
const SWAY_ACCEL_CLAMP := 20.0
const SWAY_ACCEL_SMOOTH_TIME := 0.08
## A turn's |lateral acceleration| swings the bottoms out by this share of the forward gain.
const SWAY_TURN_SHARE := 0.15
## Kicks, deg/s, negative = inward (a vertical jolt pulls a tilted slab toward hanging straight).
const SWAY_FOOTFALL_KICK := -14.0
const SWAY_FOOTFALL_RUN_SHARE := 0.6
const SWAY_TAKEOFF_KICK := -18.0
const SWAY_LAND_KICK := -25.0
## Soft caps: past them a stiff, extra-damped cushion pushes back (the "thunk" against the back).
const SWAY_OUT_CAP_DEG := 6.0
const SWAY_IN_CAP_DEG := 3.0
const SWAY_CUSHION_K := 600.0
const SWAY_CUSHION_DAMP := 24.0
## Safety clamp at this multiple of each cap.
const SWAY_HARD_CLAMP := 1.5
## Sub-step size: the cushion is stiff.
const SWAY_MAX_STEP := 1.0 / 120.0


## Low-passes the forward acceleration fed to the swing. `smoothed` the last value, `raw` this tick's.
static func smooth_accel(smoothed: float, raw: float, delta: float) -> float:
	var a := clampf(raw, -SWAY_ACCEL_CLAMP, SWAY_ACCEL_CLAMP)
	return lerpf(smoothed, a, 1.0 - exp(-delta / SWAY_ACCEL_SMOOTH_TIME))


## The forward drive for the swing from forward and lateral acceleration (m/s^2): a turn only ever
## swings the bottoms out.
static func sway_drive(forward_accel: float, lateral_accel: float) -> float:
	return forward_accel + SWAY_TURN_SHARE * absf(lateral_accel)


## One step of the swing. `state` = (angle deg, angular velocity deg/s); `drive` m/s^2 (sway_drive).
static func step_sway(state: Vector2, drive: float, delta: float) -> Vector2:
	var w := TAU / SWAY_PERIOD
	var k := w * w
	var c := 2.0 * SWAY_DAMPING_RATIO * w
	var target := SWAY_DEG_PER_ACCEL * drive
	var steps := maxi(1, ceili(delta / SWAY_MAX_STEP))
	var h := delta / steps
	var ang := state.x
	var vel := state.y
	for i in steps:
		var acc := -k * (ang - target) - c * vel
		if ang > SWAY_OUT_CAP_DEG:
			acc -= SWAY_CUSHION_K * (ang - SWAY_OUT_CAP_DEG) + (SWAY_CUSHION_DAMP * vel if vel > 0.0 else 0.0)
		elif ang < -SWAY_IN_CAP_DEG:
			acc -= SWAY_CUSHION_K * (ang + SWAY_IN_CAP_DEG) + (SWAY_CUSHION_DAMP * vel if vel < 0.0 else 0.0)
		vel += acc * h
		ang += vel * h
		var hi := SWAY_OUT_CAP_DEG * SWAY_HARD_CLAMP
		var lo := -SWAY_IN_CAP_DEG * SWAY_HARD_CLAMP
		if ang > hi or ang < lo:
			ang = clampf(ang, lo, hi)
			vel = 0.0
	return Vector2(ang, vel)


## A planted foot: the sprint's full thump, the run's share of it.
static func footfall_kick(sprinting: bool) -> float:
	return SWAY_FOOTFALL_KICK * (1.0 if sprinting else SWAY_FOOTFALL_RUN_SHARE)


## A landing `fall` metres below the peak, scaled like the camera's landing dip (fall / jump height).
static func land_kick(fall: float, jump_height: float) -> float:
	return SWAY_LAND_KICK * clampf(fall / jump_height, 0.5, 2.0)


## Places one slab for this frame: hung from its hinge at `deg`, written into its shoulder
## attachment's frame. `shoulder` is that bone in the body frame now. The attachment carries the box
## with the bone, so a bone that moves after this runs still takes the hinge with it.
static func place(slab: Node3D, shoulder: Transform3D, offset: Vector3, deg: float, slab_len: float = -1.0) -> void:
	slab.transform = shoulder.affine_inverse() * hung(hinge(shoulder, offset), deg, slab_len)


## Builds one BoneAttachment3D per shoulder bone, each holding its slab. `shoulders_standing` maps
## side -> that bone in the body frame at MECH_standing. Returns side -> attachment ({} without the
## bones). Each attachment keeps its slab's hinge offset in the meta "hinge_offset".
static func build(skeleton: Skeleton3D, shoulders_standing: Dictionary) -> Dictionary:
	var out := {}
	if skeleton == null:
		return out
	for side: float in [-1.0, 1.0]:
		if skeleton.find_bone(BONES[side]) < 0:
			return {}
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, length(), THICKNESS)
	box.material = body_material(skeleton)
	for side: float in [-1.0, 1.0]:
		var attach := BoneAttachment3D.new()
		attach.name = attachment_name(side)
		attach.bone_name = BONES[side]
		skeleton.add_child(attach)
		var standing: Transform3D = shoulders_standing[side]
		var offset := hinge_offset(standing, side)
		attach.set_meta("hinge_offset", offset)
		var slab := MeshInstance3D.new()
		slab.name = slab_name(side)
		slab.mesh = box
		attach.add_child(slab)
		place(slab, standing, offset, STAND_TILT_DEG, MIN_LENGTH)
		out[side] = attach
	return out
