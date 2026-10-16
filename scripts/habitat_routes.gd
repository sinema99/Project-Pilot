extends RefCounted

# The habitat's traversal layer, as DATA. See docs/specs/habitat-routes.md.
#
# This file knows nothing about nodes: it computes where every ledge, bulkhead, rail and vault
# block goes, and which one connects to which and by what move. scripts/habitat.gd turns the
# records into geometry (the `Routes` section), and tests/test_habitat_routes.gd audits the same
# records against the player's measured limits, so the map and the check cannot drift apart.
#
# LOCAL SPACE, the habitat's: y up, ground y = 0, the cab walkway at y = 16, the tower x 30..50,
# z -66..-50, its roof at y = 156. The constants below mirror habitat.gd's and are fenced by a
# test. The numbers under anchors() are surfaces that already exist, measured off the built map
# (the sections have been moved and scaled in the editor, so habitat.gd's own constants are not
# where they now are).
#
# Not a class_name: habitat.gd and the tests preload this by path.

# --- the tower, mirrored from habitat.gd ----------------------------------------------------------
const TX0 := 30.0
const TX1 := 50.0
const TZ0 := -66.0
const TZ1 := -50.0
const ROOF_Y := 156.0
const BRIDGE_TOP := 20.0

## How far a tower ledge juts from the face, how thick it is, and how close to a corner it may sit.
const LEDGE_D := 1.6
const LEDGE_T := 0.6
## Hop ledges stand off the face by this much, so a body jumping along one is further from the wall
## than the wall-run probe reaches and lands instead of attaching. Departure ledges, rest pads and
## balconies sit flush: those are where he is meant to hug the wall.
const STANDOFF := 1.8
const MARGIN := 0.35
## The summit approach pad sits this far under the roof, so the last move is a mantle.
const SUMMIT_STEP := 2.1

## The tower's four faces in climbing order, walked with the tower on the right hand: the left
## face first (the bridge arrives there), then the back, the right and the front. `o` is where the
## face starts, `t` the way it runs, `n` the way it faces.
const FACES := [
	{"name": "left", "o": Vector3(30, 0, -50), "t": Vector3(0, 0, -1), "n": Vector3(-1, 0, 0), "len": 16.0},
	{"name": "back", "o": Vector3(30, 0, -66), "t": Vector3(1, 0, 0), "n": Vector3(0, 0, -1), "len": 20.0},
	{"name": "right", "o": Vector3(50, 0, -66), "t": Vector3(0, 0, 1), "n": Vector3(1, 0, 0), "len": 16.0},
	{"name": "front", "o": Vector3(50, 0, -50), "t": Vector3(-1, 0, 0), "n": Vector3(0, 0, 1), "len": 20.0},
]
const RING := 72.0

## Per climb stage: the share of the player's limit each kind of move may use. `gap` and `rise` cap
## a hop, `run` caps a wall-run against the 15 m grid, `len` is the ledge length, `hops` the first
## guess at how many rising hops the stage takes. Each stage tightens the one before; the branches
## are the hardest routes on the map.
const STAGE_PLAN := [
	{"gap": 0.50, "rise": 0.70, "run": 0.55, "len": 2.6, "hops": 17},
	{"gap": 0.60, "rise": 0.78, "run": 0.70, "len": 2.2, "hops": 15},
	{"gap": 0.70, "rise": 0.86, "run": 0.80, "len": 1.9, "hops": 13},
	{"gap": 0.80, "rise": 0.94, "run": 0.90, "len": 1.6, "hops": 12},
]
## The wall-run is inserted once this many hops of a stage are done.
const RUN_AFTER := 3
## Branch moves may use this much of a limit.
const BRANCH_CAP := 0.92
## The stage's rest ledge: its length, and (stages 2 and 3, the ones with a branch) where it sits.
const REST_LEN := [5.0, 6.0, 3.8, 5.0]
const REST_D := [2.6, 2.6, 2.0, 2.6]
## The tower branches: a hop gap across to a pod (stage 2), a wall-run to one (stage 3).
const POD_LEN := [0.0, 4.0, 2.0, 0.0]
## Where on its face a rest pad starts, for the stage whose branch runs back to the corner (-1: at the face end).
const REST_U := [-1.0, -1.0, 13.4, -1.0]
## The corner balcony a wall-run lands on: length along the run, width out from the wall.
const BALCONY_LEN := 5.0
const BALCONY_W := 2.0

# --- existing surfaces (the map as built, local space) -------------------------------------------
## AABB(position, size); the top is position.y + size.y.
static func anchors() -> Dictionary:
	return {
		"cab_deck": AABB(Vector3(-2.2, 15.0, 52.0), Vector3(4.4, 1.0, 200.0)),
		"concourse": AABB(Vector3(-96.9, 4.0, 40.0), Vector3(168.7, 1.0, 12.0)),
		"hedge": AABB(Vector3(-100.0, -4.0, 20.0), Vector3(200.0, 4.0, 32.0)),
		# The terraces are rakes that fall away to the right: the sample column x -92..-88 has tops
		# 8.4 / 10.6 / 12.8 / 8.4 / 10.6 (t0..t4); t0_lo is t0's low right edge, t4_left t4's high left.
		"t0_lo": AABB(Vector3(-62.0, 2.4, 16.4), Vector3(3.8, 1.0, 17.2)),
		"t0": AABB(Vector3(-92.0, 7.4, 16.4), Vector3(4.0, 1.0, 17.2)),
		"t1": AABB(Vector3(-92.0, 9.6, -1.6), Vector3(4.0, 1.0, 17.2)),
		"t2": AABB(Vector3(-92.0, 11.8, -19.6), Vector3(4.0, 1.0, 17.2)),
		"t3": AABB(Vector3(-92.0, 7.4, -37.6), Vector3(4.0, 1.0, 17.2)),
		"t4": AABB(Vector3(-92.0, 9.6, -46.0), Vector3(4.0, 1.0, 7.6)),
		"t4_left": AABB(Vector3(-98.0, 10.9, -46.0), Vector3(6.0, 1.0, 7.6)),
		"cliff": AABB(Vector3(-112.0, 21.4, -70.0), Vector3(24.0, 1.0, 24.0)),
		"bridge": AABB(Vector3(-88.0, 19.0, -63.2), Vector3(119.0, 1.0, 10.4)),
		"island": AABB(Vector3(-42.0, -0.6, -16.0), Vector3(28.0, 1.0, 16.0)),
		"peninsula": AABB(Vector3(10.0, -1.0, 4.0), Vector3(30.0, 1.0, 16.0)),
		"roof": AABB(Vector3(30.0, 155.0, -66.0), Vector3(20.0, 1.0, 16.0)),
	}


# --- the player's limits ------------------------------------------------------------------------
## Everything the audit measures against, read off a pilot9 (a bare `new()` carries the exports).
## Plain arithmetic on the exports rather than pilot9's own distance helpers, so this file never
## has to load pilot9.gd itself: pilot9.gd names the Settings autoload, which a bare --script run
## cannot compile. tests/test_habitat_routes.gd checks the two agree.
static func limits(p: Object) -> Dictionary:
	return {
		"speed": p.sprint_speed, "jump_h": p.jump_height, "apex": p.jump_time_to_apex,
		"fall_mult": p.jump_fall_multiplier, "air_jumps": p.air_jumps,
		"wall_run": float(p.wall_run_speed) * float(p.wall_run_flat_time),
		"dash": float(p.dash_speed) * float(p.dash_time),
		"vault_depth": p.vault_max_depth, "vault_lo": p.vault_band_min, "vault_hi": p.vault_band_max,
		"rail_catch": p.rail_catch_radius, "rail_bend": p.rail_jump_max_bend,
		"rail_drop": p.rail_switch_max_drop,
	}


## How far a sprint jump clears at a given landing rise (negative: a drop), metres, held straight.
## The ordinary flat-to-flat 9 m at rise 0; shorter as the landing climbs; 0 above the apex.
static func jump_reach(rise: float, lim: Dictionary) -> float:
	var h: float = lim.jump_h
	if rise > h:
		return 0.0
	var apex: float = lim.apex
	var g_up := 2.0 * h / (apex * apex)
	var t_down := sqrt(2.0 * (h - rise) / (g_up * float(lim.fall_mult)))
	return float(lim.speed) * (apex + t_down)


# --- the records -------------------------------------------------------------------------------------
var pads: Dictionary = {}
var pad_ids: Array[String] = []
var walls: Array[Dictionary] = []
var rails: Array[Dictionary] = []
var links: Array[Dictionary] = []
var dressing: Array[Dictionary] = []
## The pad ids of each climb stage, in order, and the stage's rest pad id.
var stage_pads: Array = []
var rest_ids: Array[String] = []
var areas: Array[Dictionary] = []
var _lim: Dictionary = {}


## Builds every record. `lim` is limits() of a pilot9; the same dictionary the audit uses.
func build(lim: Dictionary) -> void:
	_lim = lim
	pads.clear()
	pad_ids.clear()
	walls.clear()
	rails.clear()
	links.clear()
	dressing.clear()
	stage_pads.clear()
	rest_ids.clear()
	areas.clear()
	_spine_east()
	_terraces_and_cliff()
	_plaza_and_bridge()
	_lake()
	_concourse_branches()
	_tower()


# --- helpers -----------------------------------------------------------------------------------------

func add_pad(id: String, center: Vector3, size: Vector2, thick: float, kind: String,
		extra := {}) -> Dictionary:
	var p := {"id": id, "center": center, "size": size, "thick": thick, "kind": kind,
		"accent": true, "support_to": -9999.0, "brace": false}
	p.merge(extra, true)
	pads[id] = p
	pad_ids.append(id)
	return p


static func pad_aabb(p: Dictionary) -> AABB:
	var c: Vector3 = p.center
	var s: Vector2 = p.size
	var t: float = p.thick
	return AABB(Vector3(c.x - s.x * 0.5, c.y - t, c.z - s.y * 0.5), Vector3(s.x, t, s.y))


## A pad's or an anchor's AABB by id.
func box_of(id: String) -> AABB:
	if pads.has(id):
		return pad_aabb(pads[id])
	return anchors()[id]


## Distance in plan (x, z) between two boxes' footprints; 0 when they overlap or touch.
static func hgap(a: AABB, b: AABB) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	return sqrt(dx * dx + dz * dz)


static func top_of(b: AABB) -> float:
	return b.end.y


func add_wall(id: String, center: Vector3, size: Vector3, kind: String, extra := {}) -> void:
	var w := {"id": id, "center": center, "size": size, "kind": kind, "accent": true}
	w.merge(extra, true)
	walls.append(w)


func add_rail(id: String, pts: Array, base_y := -9999.0, extra := {}) -> void:
	var r := {"id": id, "pts": pts, "base_y": base_y}
	r.merge(extra, true)
	rails.append(r)


func add_link(from: String, to: String, mech: String, branch: String, gap_cap: float,
		rise_cap: float, extra := {}) -> void:
	var l := {"from": from, "to": to, "mech": mech, "branch": branch, "gap_cap": gap_cap,
		"rise_cap": rise_cap}
	l.merge(extra, true)
	links.append(l)


func add_dress(kind: String, a: Vector3, b: Vector3, extra := {}) -> void:
	var d := {"kind": kind, "a": a, "b": b}
	d.merge(extra, true)
	dressing.append(d)


# --- the spine, east half: cab to concourse ---------------------------------------------------------

func _spine_east() -> void:
	# R1: off the front of the cab walkway, a long gentle fall onto the concourse.
	add_rail("R1", [Vector3(0, 15.0, 50.6), Vector3(-4.0, 13.6, 48.6), Vector3(-14.0, 9.6, 46.0),
		Vector3(-26.0, 6.0, 45.4)], 5.0)
	add_link("cab_deck", "concourse", "rail", "spine", 0.6, 0.6, {"rail": "R1"})

	# The vault gates across the concourse, three low walls to take at a run.
	for i in 3:
		var x := -30.0 - float(i) * 8.0
		add_wall("gate%d" % i, Vector3(x, 5.5, 44.6), Vector3(0.4, 1.0, 8.4), "vault")
	add_link("concourse", "concourse", "vault", "spine", 0.7, 0.7, {"walls": ["gate0", "gate1", "gate2"]})

	# From the concourse's lip down to the hedge, then a step up onto the lowest terrace.
	add_link("concourse", "hedge", "drop", "spine", 1.0, 1.0)
	add_pad("t0_step", Vector3(-55.2, 1.7, 27.0), Vector2(3.0, 3.0), 1.7, "step")
	add_link("hedge", "t0_step", "hop", "spine", 0.5, 0.6)
	add_link("t0_step", "t0_lo", "hop", "spine", 0.5, 0.6)
	add_link("t0_lo", "t0", "ramp", "spine", 0.0, 0.0)
	areas.append({"id": "concourse", "box": "concourse"})


# --- the spine, west half: terraces and the cliff ------------------------------------------------------

func _terraces_and_cliff() -> void:
	# The terraces are already a staircase of rakes, 0.8 m apart and 2.2 m a step.
	add_link("t0", "t1", "hop", "spine", 0.5, 0.75)
	add_link("t1", "t2", "hop", "spine", 0.5, 0.75)
	add_link("t3", "t4", "hop", "spine", 0.5, 0.75)
	add_link("t2", "t3", "drop", "spine", 1.0, 1.0)

	# Five ledges up the cliff's south face, zigzagging, from the top terrace to the cliff top.
	add_link("t4", "t4_left", "ramp", "spine", 0.0, 0.0)
	var prev := "t4_left"
	for i in 5:
		var xc := -97.5 if i % 2 == 0 else -92.5
		var top: float = [13.4, 15.4, 17.4, 19.2, 20.9][i]
		var id := "cs%d" % (i + 1)
		add_pad(id, Vector3(xc, top, -45.1), Vector2(3.0, 1.8), LEDGE_T, "ledge", {"brace": true, "toward": Vector3(0, 0, -1), "depth": 1.8})
		add_link(prev, id, "hop", "spine", 0.6, 0.7)
		prev = id
	add_link(prev, "cliff", "mantle", "spine", 0.0, 0.9)

	# R2, off the cliff's corner: a long gentle fall down the terraces. The way back, and a ride.
	add_rail("R2", [Vector3(-89.5, 21.6, -45.2), Vector3(-89.5, 19.6, -34.0), Vector3(-90.3, 16.0, -10.0),
		Vector3(-90.8, 12.4, 10.0), Vector3(-91.0, 9.2, 24.0)], 8.0)
	add_link("cliff", "t0", "rail", "B4", BRANCH_CAP, BRANCH_CAP, {"rail": "R2"})


# --- the bridge: plaza and the lake rail ------------------------------------------------------------------

func _plaza_and_bridge() -> void:
	add_link("cliff", "bridge", "drop", "spine", 1.0, 1.0)
	# The plaza: a wide deck over the bridge, with low blocks to vault and a long view of the tower.
	add_pad("plaza", Vector3(-19.0, 20.0, -58.0), Vector2(22.0, 30.0), 1.0, "plaza",
		{"support_to": -8.0})
	add_link("bridge", "plaza", "walk", "spine", 0.0, 0.0)
	# Where the bridge meets the tower: a step to take the first ledge from, so the climb opens with
	# an easy hop and nobody jumps at a ledge's side from the bridge.
	add_pad("bridge_step", Vector3(24.0, 21.0, -58.0), Vector2(3.0, 4.0), 1.0, "step")
	add_link("bridge", "bridge_step", "hop", "spine", 0.5, 0.5)
	add_wall("plz0", Vector3(-24.0, 20.6, -66.0), Vector3(6.0, 1.2, 1.2), "block")
	add_wall("plz1", Vector3(-14.0, 20.6, -50.0), Vector3(6.0, 1.2, 1.2), "block")
	add_wall("plz2", Vector3(-19.0, 20.5, -58.0), Vector3(0.4, 1.0, 8.0), "vault")
	add_wall("plz3", Vector3(-25.5, 20.5, -52.0), Vector3(0.4, 1.0, 5.0), "vault")
	add_link("plaza", "plaza", "vault", "spine", 0.7, 0.7, {"walls": ["plz2", "plz3"]})
	areas.append({"id": "plaza", "box": "plaza"})


# --- the lake: the rail to the island ------------------------------------------------------------------------

func _lake() -> void:
	add_pad("island_deck", Vector3(-28.0, 0.8, -8.0), Vector2(9.0, 7.0), 0.4, "pod", {"support_to": -8.0})
	add_wall("isl0", Vector3(-31.5, 1.3, -4.5), Vector3(4.0, 1.0, 0.5), "vault")
	add_wall("isl1", Vector3(-24.5, 1.3, -11.5), Vector3(0.5, 1.0, 4.0), "vault")
	add_rail("R3", [Vector3(-19.0, 19.2, -42.2), Vector3(-22.0, 13.0, -30.0), Vector3(-26.0, 6.0, -19.0),
		Vector3(-28.0, 2.2, -11.5)], -8.0)
	add_link("plaza", "island_deck", "rail", "B3", BRANCH_CAP, BRANCH_CAP, {"rail": "R3"})

	# The peninsula: an open area with a pavilion deck and low blocks to play on.
	add_pad("pen_deck", Vector3(24.0, 0.5, 11.0), Vector2(10.0, 8.0), 0.5, "plaza")
	add_wall("pen0", Vector3(20.0, 0.6, 8.0), Vector3(0.4, 1.0, 5.0), "vault")
	add_wall("pen1", Vector3(28.0, 0.6, 14.0), Vector3(4.0, 1.0, 1.2), "block")
	add_wall("pen2", Vector3(24.0, 0.6, 5.5), Vector3(6.0, 1.0, 0.4), "vault")
	areas.append({"id": "lake", "box": "pen_deck", "also": ["island_deck"]})


# --- the concourse branches -------------------------------------------------------------------------------------

func _concourse_branches() -> void:
	# B1: a covered gallery at the east end of the concourse, three vault gates in a row, opening
	# onto an overlook that hangs off the end of the deck.
	add_wall("gal_s", Vector3(57.0, 7.0, 40.3), Vector3(28.0, 4.0, 0.6), "hall")
	add_wall("gal_n", Vector3(57.0, 7.0, 51.7), Vector3(28.0, 4.0, 0.6), "hall")
	add_wall("gal_roof", Vector3(57.0, 9.3, 46.0), Vector3(28.0, 0.6, 12.0), "hall")
	for i in 3:
		add_wall("gv%d" % i, Vector3(49.0 + float(i) * 7.0, 5.5, 43.8), Vector3(0.4, 1.0, 6.6), "vault")
	add_pad("east_pod", Vector3(78.8, 5.0, 46.0), Vector2(14.0, 12.0), 1.0, "pod", {"support_to": 0.0})
	add_link("concourse", "east_pod", "vault", "B1", 0.7, 0.7, {"walls": ["gv0", "gv1", "gv2"]})
	add_wall("pod_e0", Vector3(82.0, 5.5, 41.0), Vector3(5.0, 1.0, 0.5), "vault")
	add_wall("pod_e1", Vector3(82.0, 5.5, 51.0), Vector3(5.0, 1.0, 0.5), "vault")

	# B2: a bulkhead hung over the hedge. Run along it off the concourse's edge; it ends over the
	# gap's far side and the balcony lies beyond its end, where the run drops him.
	var wall_len := 11.0
	var z_edge := 40.0
	var z_end := z_edge - wall_len
	add_pad("hedge_pod", Vector3(9.4, 5.0, z_end - 4.0), Vector2(6.4, 8.0), 1.0, "pod", {"support_to": 0.0})
	add_wall("hedge_wall", Vector3(12.9, 6.0, (z_edge + 7.5 + z_end) * 0.5),
		Vector3(0.6, 7.0, z_edge + 7.5 - z_end), "bulkhead", {"band_y": 6.6, "posts": [34.0]})
	add_link("concourse", "hedge_pod", "run", "B2", 0.82, 0.0, {"wall": "hedge_wall"})


# --- the tower ------------------------------------------------------------------------------------------------------

## Which face, and how far along it, a ring distance falls at.
static func face_at(s: float) -> Dictionary:
	var w := fposmod(s, RING)
	var start := 0.0
	for i in 4:
		var face_len: float = FACES[i].len
		if w < start + face_len:
			return {"face": i, "u": w - start, "start": start}
		start += face_len
	return {"face": 3, "u": FACES[3].len, "start": RING - FACES[3].len}


## A ledge on the ring: centre `s`, `length` along the face, juting `depth`, its top at `top`.
## Empty when it would cross a corner.
func ledge_at(s: float, length: float, depth: float, top: float, id: String, kind := "ledge") -> Dictionary:
	var f := face_at(s)
	var face: Dictionary = FACES[f.face]
	var u: float = f.u
	if u - length * 0.5 < MARGIN - 1e-4 or u + length * 0.5 > float(face.len) - MARGIN + 1e-4:
		return {}
	var o: Vector3 = face.o
	var t: Vector3 = face.t
	var n: Vector3 = face.n
	var standoff := STANDOFF if kind == "ledge" else 0.0
	var c := o + t * u + n * (standoff + depth * 0.5 - (0.05 if standoff == 0.0 else 0.0))
	c.y = top
	var size := Vector2(depth, length) if absf(n.x) > 0.5 else Vector2(length, depth)
	return {"id": id, "center": c, "size": size, "thick": LEDGE_T, "kind": kind, "accent": true,
		"support_to": -9999.0, "brace": true, "toward": -n, "s": s, "len": length, "face": f.face,
		"depth": depth, "standoff": standoff}


func _tower() -> void:
	var y0: float = float(pads["bridge_step"].center.y)
	var span := (ROOF_Y - SUMMIT_STEP - y0) / float(STAGE_PLAN.size())
	# The climb starts from the step on the bridge: a pad that is not on the ring, given a ring
	# position on the left face so the first ledge is searched for beside it.
	var cur: Dictionary = (pads["bridge_step"] as Dictionary).duplicate()
	cur["s"] = 5.0
	cur["len"] = 0.0
	for k in STAGE_PLAN.size():
		var plan: Dictionary = STAGE_PLAN[k]
		var target := y0 + span
		# Try hop counts nearest the plan's first, and take the first stage whose rest-pad hop is
		# no bigger than the stage's rise cap: r = span / n then agrees with the ring.
		var result := {}
		var order: Array[int] = []
		for d in range(0, 14):
			order.append(int(plan.hops) + d)
			if d > 0:
				order.append(int(plan.hops) - d)
		var skips := 3 if float(POD_LEN[k]) > 0.0 else 1
		for skip in skips:
			for g in order:
				if g < 6:
					continue
				var t := _gen_stage(k, cur, y0, target, span / float(g), skip)
				if t.is_empty():
					continue
				var last_rise: float = t.last_rise
				var cap: float = float(plan.rise) * float(_lim.jump_h)
				if last_rise <= cap + 1e-3 and last_rise >= span / float(g) * 0.5:
					result = t
					break
			if not result.is_empty():
				break
		if result.is_empty():
			push_error("HabitatRoutes: stage %d failed to generate; last traces: %s" % [k, str(trace.slice(maxi(trace.size() - 8, 0)))])
			return
		for p: Dictionary in result.pads:
			pads[p.id] = p
			pad_ids.append(p.id)
		for l: Dictionary in result.links:
			links.append(l)
		for d: Dictionary in result.dress:
			dressing.append(d)
		stage_pads.append(result.ids)
		rest_ids.append(result.rest)
		cur = pads[result.rest]
		y0 = float(cur.center.y)
	_summit()
	_tower_branches()


## One climb stage from `start` up to a rest pad whose top is `target`, at `r` metres a hop. Returns
## {pads, links, dress, ids, rest, hops} with `hops` the number of rising hops it actually took (the
## caller re-runs with r = span / hops until the two agree), or {} if it cannot be laid out.
func _gen_stage(k: int, start: Dictionary, y0: float, target: float, r: float, skip := 0) -> Dictionary:
	var plan: Dictionary = STAGE_PLAN[k]
	var length: float = plan.len
	var cur: Dictionary = start
	var out_pads: Array[Dictionary] = []
	var out_links: Array[Dictionary] = []
	var out_dress: Array[Dictionary] = []
	var ids: Array[String] = []
	var hops := 0
	var top := y0
	var uid := 0
	var forced_rest := float(POD_LEN[k]) > 0.0
	var rest_len: float = REST_LEN[k]
	var n_guess: int = int(round((target - y0) / r))

	# A: the first few hops.
	while hops < RUN_AFTER:
		top += r
		var nxt := _hop_search(cur, length, LEDGE_D, top, _gap_cap(plan, r), 9999.0, "s%d_%d" % [k, uid], "ledge")
		uid += 1
		if nxt.is_empty():
			return _fail("gen_stage #1")
		out_pads.append(nxt)
		ids.append(nxt.id)
		out_links.append(_hop_link(cur, nxt, plan, "hop"))
		cur = nxt
		hops += 1

	# B: the wall-run across the next long face.
	var run := _plan_run(cur, top + r, r, plan, "s%d_run" % k)
	if run.is_empty():
		return _fail("gen_stage #2")
	for p: Dictionary in run.pads:
		out_pads.append(p)
		ids.append(p.id)
	for l: Dictionary in run.links:
		out_links.append(l)
	for d: Dictionary in run.dress:
		out_dress.append(d)
	hops += int(run.hops)
	top += r * float(run.hops)
	cur = run.last

	# C: hops up to the rest pad.
	var rest := {}
	var guard := 0
	# A branch stage's rest pad sits at the far end of a long face, fixed once and hopped toward.
	var s_end := 0.0
	if forced_rest:
		var face := _next_long_face(float(cur.s) + float(cur.len) * 0.5)
		for _i in skip:
			face = _next_long_face(float(face.start) + float(face.len) - 0.5 * MARGIN)
		s_end = float(face.start) + float(face.len) - MARGIN - rest_len * 0.5
		if float(REST_U[k]) >= 0.0:
			s_end = float(face.start) + float(REST_U[k]) + rest_len * 0.5
	while guard < 80:
		guard += 1
		if forced_rest:
			var cand := ledge_at(s_end, rest_len, float(REST_D[k]), target, "rest%d" % k, "rest")
			if not cand.is_empty() and target - float(cur.center.y) <= float(plan.rise) * float(_lim.jump_h) + 1e-3 \
					and hgap(_as_box(cur), pad_aabb(cand)) <= _gap_cap(plan, maxf(target - top, 0.0)) + 1e-4 \
					and float(cand.s) > float(cur.s):
				rest = cand
				break
		elif hops >= n_guess - 1 and target - float(cur.center.y) <= float(plan.rise) * float(_lim.jump_h) + 1e-3:
			rest = _hop_search(cur, rest_len, float(REST_D[k]), target, _gap_cap(plan, maxf(target - top, 0.0)),
				9999.0, "rest%d" % k, "rest")
			if not rest.is_empty():
				break
		top += r
		var lim_s := 9999.0
		if forced_rest:
			lim_s = s_end - rest_len * 0.5 - length * 0.5 - 0.1
		var nxt := _hop_search(cur, length, LEDGE_D, top, _gap_cap(plan, r), lim_s, "s%d_%d" % [k, uid], "ledge")
		uid += 1
		if nxt.is_empty():
			return _fail("gen_stage #3 cur.s=%.1f s_end=%.1f lim=%.1f hops=%d top=%.1f target=%.1f" % [float(cur.s), s_end, lim_s, hops, top, target])
		out_pads.append(nxt)
		ids.append(nxt.id)
		out_links.append(_hop_link(cur, nxt, plan, "hop"))
		cur = nxt
		hops += 1
	if rest.is_empty():
		return _fail("gen_stage #4")
	out_pads.append(rest)
	ids.append(rest.id)
	out_links.append(_hop_link(cur, rest, plan, "hop"))
	hops += 1
	return {"pads": out_pads, "links": out_links, "dress": out_dress, "ids": ids, "rest": rest.id,
		"hops": hops, "last_rise": target - float(cur.center.y)}


## The share-of-the-limit gap cap in metres for a hop of `rise`.
var trace: Array[String] = []


func _fail(why: String) -> Dictionary:
	trace.append(why)
	return {}


func _gap_cap(plan: Dictionary, rise: float) -> float:
	return float(plan.gap) * jump_reach(rise, _lim)


func _hop_link(a: Dictionary, b: Dictionary, plan: Dictionary, mech: String) -> Dictionary:
	return {"from": a.id, "to": b.id, "mech": mech, "branch": "spine",
		"gap_cap": plan.gap, "rise_cap": plan.rise}


## The farthest valid ledge past `cur` whose footprint is no more than `g_cap` from it.
func _hop_search(cur: Dictionary, length: float, depth: float, top: float, g_cap: float,
		s_limit: float, id: String, kind: String) -> Dictionary:
	var cur_box := _as_box(cur)
	var cur_end: float = float(cur.s) + float(cur.len) * 0.5
	var best := {}
	var s := cur_end + length * 0.5 + 0.05
	var s_max := minf(cur_end + length * 0.5 + g_cap + 8.0, s_limit)
	while s <= s_max:
		var cand := ledge_at(s, length, depth, top, id, kind)
		if not cand.is_empty():
			var gap := hgap(cur_box, pad_aabb(cand))
			if gap <= g_cap + 1e-4:
				best = cand
		s += 0.05
	return best


func _as_box(p: Dictionary) -> AABB:
	if p.has("center"):
		return pad_aabb(p)
	return anchors()[p.id]


## The next back/front face start strictly after ring position `s_after`: {start, len, face}.
static func _next_long_face(s_after: float) -> Dictionary:
	var lap := floorf(s_after / RING) * RING
	var best := {}
	for _rep in 3:
		var start := 0.0
		for i in 4:
			var face_len: float = FACES[i].len
			var name: String = FACES[i].name
			if (name == "back" or name == "front") and lap + start > s_after + 0.01 and best.is_empty():
				best = {"start": lap + start, "len": face_len, "face": i}
			start += face_len
		lap += RING
	return best


## A corner balcony: the catch pad a wall-run lands on. The wall ends at the tower's corner, and he
## leaves it still moving at run speed, so the pad hangs out past the corner in his direction of
## travel, `BALCONY_LEN` long and as wide as a ledge. `forward` is the ring's own direction (the
## spine's runs); false is back toward the face's start corner (the stage-3 branch).
func _balcony(face_idx: int, face_start_s: float, forward: bool, top: float, id: String, kind: String) -> Dictionary:
	var face: Dictionary = FACES[face_idx]
	var o: Vector3 = face.o
	var t: Vector3 = face.t
	var n: Vector3 = face.n
	var face_len: float = face.len
	var c: Vector3
	var s_ref: float
	if forward:
		c = o + t * face_len + t * (BALCONY_LEN * 0.5 - 0.2) + n * (BALCONY_W * 0.5 - 0.05)
		s_ref = face_start_s + face_len
	else:
		c = o - t * (BALCONY_LEN * 0.5 - 0.2) + n * (BALCONY_W * 0.5 - 0.05)
		s_ref = face_start_s
	c.y = top
	var along_x := absf(t.x) > 0.5
	var size := Vector2(BALCONY_LEN, BALCONY_W) if along_x else Vector2(BALCONY_W, BALCONY_LEN)
	return {"id": id, "center": c, "size": size, "thick": LEDGE_T, "kind": kind, "accent": true,
		"support_to": -9999.0, "brace": true, "toward": -n, "s": s_ref, "len": 0.0, "face": face_idx,
		"depth": BALCONY_W, "balcony": true}


## The wall-run: hop (as many as it takes) to a departure ledge on the next long face, placed so the
## wall runs `run` metres beyond its far edge to the face's end, then land on a corner balcony.
## Returns {pads, links, dress, hops, last} or {}.
func _plan_run(cur: Dictionary, step_top: float, r: float, plan: Dictionary, prefix: String) -> Dictionary:
	var face := _next_long_face(float(cur.s) + float(cur.len) * 0.5)
	if face.is_empty():
		return {}
	var run_len: float = float(plan.run) * float(_lim.wall_run)
	var dep_len := 2.4
	var dep_end_u: float = float(face.len) - run_len
	if dep_end_u - dep_len < MARGIN:
		return {}
	var out_pads: Array[Dictionary] = []
	var out_links: Array[Dictionary] = []
	var out_dress: Array[Dictionary] = []
	var hops := 0
	var c := cur
	var top := step_top
	var dep_s: float = float(face.start) + dep_end_u - dep_len * 0.5
	var dep := {}
	for guard in 14:
		dep = ledge_at(dep_s, dep_len, LEDGE_D, top, prefix + "_dep", "dep")
		if not dep.is_empty() and float(dep.s) > float(c.s) \
				and hgap(_as_box(c), pad_aabb(dep)) <= _gap_cap(plan, r) + 1e-4:
			break
		dep = {}
		var mid := _hop_search(c, float(plan.len), LEDGE_D, top, _gap_cap(plan, r),
			dep_s - dep_len * 0.5 - float(plan.len) * 0.5 - 0.1, prefix + "_m%d" % guard, "ledge")
		if mid.is_empty():
			return {}
		out_pads.append(mid)
		out_links.append(_hop_link(c, mid, plan, "hop"))
		hops += 1
		c = mid
		top += r
	if dep.is_empty():
		return {}
	out_pads.append(dep)
	out_links.append(_hop_link(c, dep, plan, "hop"))
	hops += 1
	var arr := _balcony(face.face, face.start, true, top, prefix + "_arr", "ledge")
	out_pads.append(arr)
	out_links.append({"from": dep.id, "to": arr.id, "mech": "run", "branch": "spine",
		"gap_cap": plan.run, "rise_cap": 0.0, "face": face.face})
	# The green strip down the face the run follows, from the ledge's far edge to the corner.
	var fc: Dictionary = FACES[face.face]
	var a_pos: Vector3 = (fc.o as Vector3) + (fc.t as Vector3) * dep_end_u
	var b_pos: Vector3 = (fc.o as Vector3) + (fc.t as Vector3) * float(fc.len)
	out_dress.append({"kind": "strip", "a": a_pos + Vector3(0, top + 1.4, 0),
		"b": b_pos + Vector3(0, top + 1.4, 0), "n": fc.n})
	return {"pads": out_pads, "links": out_links, "dress": out_dress, "hops": hops, "last": arr}


func _summit() -> void:
	var last: Dictionary = pads[rest_ids[rest_ids.size() - 1]]
	add_link(last.id, "roof", "mantle", "spine", 0.0, 0.9)
	areas.append({"id": "summit", "box": "roof"})


## B5 and B6: pods off the stage-2 and stage-3 rest ledges, both at the branch cap. B5 is a sprint
## jump across the widest gap the cap allows, to a ledge behind the rest pad on the same face. B6 is a
## wall-run back along the face to its start corner, landing on a corner balcony.
func _tower_branches() -> void:
	var rest: Dictionary = pads[rest_ids[1]]
	var gap := floorf(BRANCH_CAP * jump_reach(0.0, _lim) * 10.0) / 10.0 - 0.1
	var pod_len: float = POD_LEN[1]
	var s_pod: float = float(rest.s) - float(rest.len) * 0.5 - gap - pod_len * 0.5
	var pod := ledge_at(s_pod, pod_len, 2.4, float(rest.center.y), "pod_hop", "pod")
	if pod.is_empty():
		push_error("HabitatRoutes: stage-2 pod does not fit")
	else:
		_add_existing_pad(pod)
		add_link(rest.id, pod.id, "hop", "B5", BRANCH_CAP, BRANCH_CAP)

	rest = pads[rest_ids[2]]
	var f := face_at(float(rest.s))
	var face_start: float = float(rest.s) - float(f.u)
	var balcony := _balcony(int(rest.face), face_start, false, float(rest.center.y), "pod_run", "pod")
	_add_existing_pad(balcony)
	add_link(rest.id, balcony.id, "run", "B6", BRANCH_CAP, 0.0, {"face": rest.face})
	var fc: Dictionary = FACES[rest.face]
	var u_start: float = float(f.u) - float(rest.len) * 0.5
	dressing.append({"kind": "strip",
		"a": (fc.o as Vector3) + (fc.t as Vector3) * 0.0 + Vector3(0, float(rest.center.y) + 1.4, 0),
		"b": (fc.o as Vector3) + (fc.t as Vector3) * u_start + Vector3(0, float(rest.center.y) + 1.4, 0),
		"n": fc.n})


func _add_existing_pad(p: Dictionary) -> void:
	pads[p.id] = p
	pad_ids.append(p.id)


# --- the audit ----------------------------------------------------------------------------------------
## Every violation of the spec's rules, as readable strings; empty when the routes are sound. Reads
## the same records habitat.gd builds from, against the limits build() was given.
func audit() -> PackedStringArray:
	var bad := PackedStringArray()
	var lim := _lim
	var eps := 0.02
	for l: Dictionary in links:
		var tag := "%s -> %s (%s, %s)" % [l.from, l.to, l.mech, l.branch]
		if not (pads.has(l.from) or anchors().has(l.from)):
			bad.append("%s: unknown from" % tag)
			continue
		if not (pads.has(l.to) or anchors().has(l.to)):
			bad.append("%s: unknown to" % tag)
			continue
		var a := box_of(l.from)
		var b := box_of(l.to)
		var rise := top_of(b) - top_of(a)
		var gap := hgap(a, b)
		match String(l.mech):
			"hop":
				if rise > float(lim.jump_h) * float(l.rise_cap) + eps:
					bad.append("%s: rise %.2f m exceeds %.0f%% of the jump" % [tag, rise, float(l.rise_cap) * 100.0])
				var reach := jump_reach(rise, lim)
				if gap > float(l.gap_cap) * reach + eps:
					bad.append("%s: gap %.2f m exceeds %.0f%% of the %.2f m reach at that rise" % [tag, gap, float(l.gap_cap) * 100.0, reach])
			"run":
				if gap > float(l.gap_cap) * float(lim.wall_run) + eps:
					bad.append("%s: wall-run %.2f m exceeds %.0f%% of %.0f m" % [tag, gap, float(l.gap_cap) * 100.0, float(lim.wall_run)])
				if absf(rise) > 0.3:
					bad.append("%s: a wall-run is level, this one changes height by %.2f" % [tag, rise])
				if l.has("wall"):
					var w := _wall(String(l.wall))
					if w.is_empty():
						bad.append("%s: unknown wall" % tag)
					else:
						var wsz: Vector3 = w.size
						if maxf(wsz.x, wsz.z) < gap + 2.0:
							bad.append("%s: the wall (%.1f m) is shorter than the run plus its ends" % [tag, maxf(wsz.x, wsz.z)])
						if wsz.y < 3.0:
							bad.append("%s: the wall is under 3 m tall" % tag)
				elif l.has("face"):
					for id: String in [l.from, l.to]:
						var sz: Vector2 = pads[id].size
						var jut := sz.x if absf((FACES[int(l.face)].n as Vector3).x) > 0.5 else sz.y
						if jut > 2.0:
							bad.append("%s: %s juts %.1f m from the face the run follows" % [tag, id, jut])
			"rail":
				bad.append_array(_audit_rail(l, a, b, lim, tag))
			"vault":
				bad.append_array(_audit_vault(l, lim, tag))
			"walk":
				if gap > 0.6 or absf(rise) > 0.5:
					bad.append("%s: not a walk: gap %.2f, rise %.2f" % [tag, gap, rise])
			"ramp":
				# A rake: up and along, no steeper than 25 degrees over the distance between the boxes.
				var run := Vector2(a.get_center().x - b.get_center().x, a.get_center().z - b.get_center().z).length()
				if rise > 0.05 and rise > run * tan(deg_to_rad(25.0)):
					bad.append("%s: a ramp climbing %.2f m over %.2f m is steeper than 25 degrees" % [tag, rise, run])
			"drop":
				if rise > 0.1:
					bad.append("%s: a drop goes up %.2f" % [tag, rise])
			"mantle":
				if rise < 1.0 or rise > 2.6 or gap > 1.5:
					bad.append("%s: not a mantle: rise %.2f gap %.2f" % [tag, rise, gap])
			_:
				bad.append("%s: unknown move" % tag)

	# The tower's stages tighten, one by one.
	for k in range(1, STAGE_PLAN.size()):
		for key in ["gap", "rise", "run"]:
			if float(STAGE_PLAN[k][key]) <= float(STAGE_PLAN[k - 1][key]):
				bad.append("stage %d does not tighten %s" % [k + 1, key])
		if float(STAGE_PLAN[k].len) >= float(STAGE_PLAN[k - 1].len):
			bad.append("stage %d does not shrink its ledges" % [k + 1])
	# Rest ledges: the climb is cut into stages about 33 m apart.
	var prev_y := BRIDGE_TOP + 1.0
	for id in rest_ids:
		var y: float = pads[id].center.y
		if y - prev_y < 25.0 or y - prev_y > 40.0:
			bad.append("rest %s is %.1f m above the last one (want 25..40)" % [id, y - prev_y])
		prev_y = y
	if not rest_ids.is_empty() and absf(float(pads[rest_ids[rest_ids.size() - 1]].center.y) - (ROOF_Y - SUMMIT_STEP)) > 0.2:
		bad.append("the summit approach is not %.1f m under the roof" % SUMMIT_STEP)

	# Branches: six, each ending on a payoff spot.
	var ends := {"B1": "east_pod", "B2": "hedge_pod", "B3": "island_deck", "B4": "t0", "B5": "pod_hop", "B6": "pod_run"}
	for br: String in ends:
		var found := false
		for l: Dictionary in links:
			if l.branch == br and l.to == ends[br]:
				found = true
		if not found:
			bad.append("branch %s has no link into %s" % [br, ends[br]])
	# The spine reaches the summit.
	if not _reaches("cab_deck", "roof"):
		bad.append("no chain of spine links leads from the cab deck to the roof")
	# Pads never roof one another in: where two overlap in plan, the upper keeps 2.6 m clear.
	for i in pad_ids.size():
		for j in range(i + 1, pad_ids.size()):
			var ba := pad_aabb(pads[pad_ids[i]])
			var bb := pad_aabb(pads[pad_ids[j]])
			var ox := minf(ba.end.x, bb.end.x) - maxf(ba.position.x, bb.position.x)
			var oz := minf(ba.end.z, bb.end.z) - maxf(ba.position.z, bb.position.z)
			if ox <= 0.01 or oz <= 0.01:
				continue
			var lower_top := minf(top_of(ba), top_of(bb))
			var upper_bottom := maxf(ba.position.y, bb.position.y)
			if upper_bottom - lower_top < 2.6:
				bad.append("pads %s and %s overlap in plan without 2.6 m of clear height" % [pad_ids[i], pad_ids[j]])
	return bad


func _wall(id: String) -> Dictionary:
	for w: Dictionary in walls:
		if w.id == id:
			return w
	return {}


func _rail(id: String) -> Dictionary:
	for r: Dictionary in rails:
		if r.id == id:
			return r
	return {}


func _audit_rail(l: Dictionary, a: AABB, b: AABB, lim: Dictionary, tag: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var r := _rail(String(l.rail))
	if r.is_empty():
		bad.append("%s: unknown rail" % tag)
		return bad
	var pts: Array = r.pts
	var p0: Vector3 = pts[0]
	var p1: Vector3 = pts[pts.size() - 1]
	# He leaves the front of `from` and falls onto it: it starts within reach of the edge, a little under it.
	var start_gap := hgap(a, AABB(p0, Vector3.ZERO))
	if start_gap > float(lim.rail_catch) + 0.6:
		bad.append("%s: the rail starts %.2f m from the edge he leaves, past the catch radius" % [tag, start_gap])
	if p0.y > top_of(a) + 0.2 or p0.y < top_of(a) - 2.0:
		bad.append("%s: the rail starts at y %.2f against a deck at %.2f" % [tag, p0.y, top_of(a)])
	# It ends above `to`, a short drop onto it.
	var end_gap := hgap(b, AABB(p1, Vector3.ZERO))
	if end_gap > 2.0:
		bad.append("%s: the rail ends %.2f m from where it should land" % [tag, end_gap])
	var drop := p1.y - top_of(b)
	var max_drop := minf(float(lim.rail_drop), 1.5)
	if drop < 0.0 or drop > max_drop:
		bad.append("%s: the rail ends %.2f m above its landing (want 0..%.1f)" % [tag, drop, max_drop])
	# He leaves the end at the rail's own speed: the landing has to run on beyond it.
	var last_dir: Vector3 = (pts[pts.size() - 1] as Vector3) - (pts[pts.size() - 2] as Vector3)
	last_dir.y = 0.0
	last_dir = last_dir.normalized()
	var room := 0.0
	while room < 30.0:
		var q := p1 + last_dir * room
		if q.x < b.position.x or q.x > b.end.x or q.z < b.position.z or q.z > b.end.z:
			break
		room += 0.1
	if room < 4.0:
		bad.append("%s: only %.1f m of landing beyond the end of the rail (want 4)" % [tag, room])
	var total := 0.0
	for i in pts.size() - 1:
		var d: Vector3 = (pts[i + 1] as Vector3) - (pts[i] as Vector3)
		total += d.length()
		var slope := rad_to_deg(atan2(-d.y, Vector2(d.x, d.z).length()))
		if slope > 40.0:
			bad.append("%s: segment %d falls at %.0f degrees" % [tag, i, slope])
		if slope < -2.0:
			bad.append("%s: segment %d climbs" % [tag, i])
		if i > 0:
			var d0: Vector3 = (pts[i] as Vector3) - (pts[i - 1] as Vector3)
			var bend := rad_to_deg(d0.angle_to(d))
			if bend > float(lim.rail_bend):
				bad.append("%s: bend %.0f degrees at point %d" % [tag, bend, i])
	if total < 12.0:
		bad.append("%s: the rail is only %.1f m long" % [tag, total])
	return bad


func _audit_vault(l: Dictionary, lim: Dictionary, tag: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var last_x := 9999.0
	for id: String in l.walls:
		var w := _wall(id)
		if w.is_empty():
			bad.append("%s: unknown wall %s" % [tag, id])
			continue
		var sz: Vector3 = w.size
		if sz.y < float(lim.vault_lo) or sz.y > float(lim.vault_hi):
			bad.append("%s: %s is %.2f m tall, outside the vault band" % [tag, id, sz.y])
		if minf(sz.x, sz.z) > float(lim.vault_depth):
			bad.append("%s: %s is %.2f m deep, past the vault depth" % [tag, id, minf(sz.x, sz.z)])
		var cx: float = (w.center as Vector3).x
		if last_x < 9000.0 and absf(cx - last_x) < 5.0:
			bad.append("%s: %s is under 5 m from the last gate" % [tag, id])
		last_x = cx
	return bad


## Whether `to` can be reached from `from` along the spine's links (walks run both ways).
func _reaches(from: String, to: String) -> bool:
	var seen := {from: true}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			return true
		for l: Dictionary in links:
			if l.branch != "spine":
				continue
			var nxt := ""
			if l.from == cur:
				nxt = l.to
			elif l.mech == "walk" and l.to == cur:
				nxt = l.from
			if nxt != "" and not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return false
