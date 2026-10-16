extends SceneTree
## Real runs over the habitat's routes: the real pilot9, the real Routes section, real collision.
## Not part of the suite (no test_ prefix) - it needs frames, like tests/_probe_vault.gd. Exits 1 if
## any scenario fails. See docs/specs/habitat-routes.md, "Verification".
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_routes.gd [-- verbose] [filter]
##
## A hop stands the pilot on one pad (as far from the next as the pad allows, so the run-up is the
## longest the map gives him), points the camera at the next, holds forward and presses jump the
## frame he reaches the edge. A competent player picks the gait, so a hop is tried at a run and, if
## that misses, at a sprint; it passes if either lands on the next pad.

const ROUTES := preload("res://scripts/habitat_routes.gd")

var world: Node3D
var habitat: Node3D
var pilot: CharacterBody3D
var rt
var lim: Dictionary
var fails: Array[String] = []
var passes := 0
var verbose := false
var only := ""
var run_all := true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	verbose = args.has("verbose")
	for a in args:
		if a != "verbose":
			only = a
	_main.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _spawn_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	habitat = (load("res://scenes/habitat.tscn") as PackedScene).instantiate()
	world.add_child(habitat)
	await _frames(4)


func _spawn_pilot(at: Vector3, yaw: float) -> void:
	if pilot and is_instance_valid(pilot):
		pilot.queue_free()
		await _frames(2)
	for a in ["forward", "jump", "sprint", "walk", "crouch", "backward", "left", "right"]:
		Input.action_release(a)
	pilot = (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	world.add_child(pilot)
	pilot.global_position = at + Vector3(0, 0.03, 0)
	pilot.camera_pivot.rotation.y = yaw
	await _frames(3)


func _yaw_for(dir: Vector3) -> float:
	# Forward at yaw 0 is -Z; turning the pivot by `yaw` rotates it about Y.
	return atan2(-dir.x, -dir.z)


func _inside(b: AABB, p: Vector3, pad: float) -> bool:
	return p.x >= b.position.x - pad and p.x <= b.end.x + pad and p.z >= b.position.z - pad \
		and p.z <= b.end.z + pad


## How far along `dir` from `p` the footprint of `b` is left (0 when already outside).
func _exit_dist(b: AABB, p: Vector3, dir: Vector3) -> float:
	var t := 0.0
	while t < 40.0:
		var q := p + dir * t
		if q.x < b.position.x or q.x > b.end.x or q.z < b.position.z or q.z > b.end.z:
			return t
		t += 0.02
	return t


## The start point on `a` farthest back from `dir`, kept `inset` in from the edges.
func _run_up_start(a: AABB, ca: Vector3, dir: Vector3, inset: float) -> Vector3:
	var best := ca
	var t := 0.0
	while t < 30.0:
		var q := ca - dir * t
		if q.x < a.position.x + inset or q.x > a.end.x - inset or q.z < a.position.z + inset \
				or q.z > a.end.z - inset:
			break
		best = q
		t += 0.05
	return best


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passes += 1
		print("  PASS  ", name, "  ", detail if verbose else "")
	else:
		fails.append(name)
		print("  FAIL  ", name, "  ", detail)


func _wanted(name: String) -> bool:
	return only == "" or name.contains(only)


## One attempt. `a`, `b`: the pad the pilot leaves and the one he should land on. `start` and `dir`
## are where he stands and which way he runs. opts: sprint, wall_run (expect to see it), edge,
## frames, jump (false: never press jump - the run itself must carry him).
func _attempt(a: AABB, b: AABB, start: Vector3, dir: Vector3, opts: Dictionary) -> Dictionary:
	await _spawn_pilot(start, _yaw_for(dir))
	Input.action_press("forward")
	var jumped := -1
	var f := 0
	var saw_run := false
	var landed := false
	var peak := 0.0
	var max_f: int = int(opts.get("frames", 360))
	var want_jump: bool = opts.get("jump", true)
	var forward_down := true
	while f < max_f:
		f += 1
		pilot.sprint_toggled = bool(opts.get("sprint", false))
		var p := pilot.global_position
		peak = maxf(peak, Vector3(pilot.velocity.x, 0, pilot.velocity.z).length())
		if pilot.is_wall_running:
			saw_run = true
		if jumped > 0 and not pilot.is_on_floor() and _inside(b, p, -0.25) and p.y < b.end.y + 2.5:
			if forward_down:
				Input.action_release("forward")
				forward_down = false
		elif not forward_down:
			Input.action_press("forward")
			forward_down = true
		if want_jump and jumped < 0 and pilot.is_on_floor():
			var ready: bool = _exit_dist(a, Vector3(p.x, 0, p.z), dir) <= float(opts.get("edge", 0.3))
			if opts.has("near_b"):
				ready = _gap_to(b, p) <= float(opts.near_b)
			if ready:
				if verbose:
					print("      jump at frame %d from (%.2f, %.2f, %.2f) dir (%.2f, %.2f) speed %.1f" % [f, p.x, p.y, p.z, dir.x, dir.z, Vector3(pilot.velocity.x, 0, pilot.velocity.z).length()])
				Input.action_press("jump")
				jumped = f
		elif jumped > 0 and f == jumped + 2:
			Input.action_release("jump")
		if verbose and jumped > 0 and (f - jumped) % 5 == 0 and f - jumped < 80:
			print("        f+%d pos (%.2f, %.2f, %.2f) vel (%.1f, %.1f, %.1f) floor %s fwd %s" % [f - jumped, p.x, p.y, p.z, pilot.velocity.x, pilot.velocity.y, pilot.velocity.z, str(pilot.is_on_floor()), str(forward_down)])
		var left_a := not _inside(a, p, 0.0) or p.y > a.end.y + 0.3 or p.y < a.end.y - 0.3
		if (jumped > 0 or not want_jump) and left_a and pilot.is_on_floor() and _inside(b, p, 0.6) \
				and absf(p.y - b.end.y) < 0.4:
			landed = true
			break
		if p.y < minf(a.end.y, b.end.y) - 40.0:
			break
		await process_frame
	Input.action_release("forward")
	Input.action_release("jump")
	return {"landed": landed, "saw_run": saw_run, "frames": f, "peak": peak, "end": pilot.global_position}


## Plan distance from `p` to the footprint of `b` (0 inside it).
func _gap_to(b: AABB, p: Vector3) -> float:
	var dx := maxf(maxf(b.position.x - p.x, p.x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.z - p.z, p.z - b.end.z), 0.0)
	return sqrt(dx * dx + dz * dz)


func _end_str(r: Dictionary) -> String:
	var e: Vector3 = r.end
	return "end (%.1f, %.1f, %.1f) frames %d peak %.1f wall-run %s" % [e.x, e.y, e.z, r.frames, r.peak, str(r.saw_run)]


## Hop from one pad to another, at a run and then a sprint.
func _hop(name: String, from_id: String, to_id: String, opts := {}) -> void:
	if not _wanted(name):
		return
	var a: AABB = rt.box_of(from_id)
	var b: AABB = rt.box_of(to_id)
	var ca := a.get_center()
	var cb := b.get_center()
	var dir := Vector3(cb.x - ca.x, 0, cb.z - ca.z)
	if opts.has("dir"):
		dir = opts.dir
	dir = dir.normalized()
	var start: Vector3
	if opts.has("start"):
		start = opts.start
		dir = Vector3(cb.x - start.x, 0, cb.z - start.z).normalized() if not opts.has("dir") else dir
	else:
		start = _run_up_start(a, ca, dir, float(opts.get("inset", 0.45)))
	start.y = a.end.y
	var gaits: Array = [false, true]
	if opts.has("sprint"):
		gaits = [opts.sprint]
	var last := {}
	for sprint: bool in gaits:
		var o := opts.duplicate()
		o["sprint"] = sprint
		last = await _attempt(a, b, start, dir, o)
		var ok: bool = last.landed and (not opts.get("wall_run", false) or last.saw_run)
		if ok:
			_report(name, true, "%s: %s" % ["sprint" if sprint else "run", _end_str(last)])
			return
	_report(name, false, _end_str(last))


## A chain of pads taken in one run, momentum carried from ledge to ledge: the pilot always steers at
## the next pad, jumps at the edge of the one he is on, and lets go of the stick over the next pad's
## footprint (the air brake stops him dead) so he drops onto it. That is what a player does.
func _chain(name: String, ids: Array, opts := {}) -> void:
	if not _wanted(name):
		return
	var last := {}
	for sprint: bool in [false, true]:
		last = await _chain_attempt(ids, sprint, opts)
		if last.ok:
			_report(name, true, "%s: %d hops, %d frames%s" % ["sprint" if sprint else "run", ids.size() - 1,
				last.frames, " (wall-run touched %d times)" % last.wall if last.wall > 0 else ""])
			return
	_report(name, false, "stuck on hop %s -> %s, end (%.1f, %.1f, %.1f) wall-run %d" % [
		last.hop_from, last.hop_to, last.end.x, last.end.y, last.end.z, last.wall])


func _chain_attempt(ids: Array, sprint: bool, opts: Dictionary) -> Dictionary:
	var boxes: Array[AABB] = []
	for id: String in ids:
		boxes.append(rt.box_of(id))
	var ca := boxes[0].get_center()
	var first_dir := (boxes[1].get_center() - ca)
	first_dir.y = 0
	first_dir = first_dir.normalized()
	var start := _run_up_start(boxes[0], ca, first_dir, 0.35)
	start.y = boxes[0].end.y
	await _spawn_pilot(start, _yaw_for(first_dir))
	Input.action_press("forward")
	var idx := 0
	var f := 0
	var hop_f := 0
	var jumped := false
	var release_jump_at := -1
	var wall := 0
	var was_wall := false
	var ok := false
	var max_f := 330 * ids.size()
	var forward_down := true
	while f < max_f:
		f += 1
		hop_f += 1
		pilot.sprint_toggled = sprint
		var p := pilot.global_position
		var nxt := boxes[idx + 1]
		var cur := boxes[idx]
		var to := nxt.get_center() - p
		to.y = 0
		if to.length() > 0.2:
			pilot.camera_pivot.rotation.y = _yaw_for(to.normalized())
		if pilot.is_wall_running and not was_wall:
			wall += 1
		was_wall = pilot.is_wall_running
		var on_floor := pilot.is_on_floor()
		if on_floor and _inside(nxt, p, 0.15) and absf(p.y - nxt.end.y) < 0.4:
			idx += 1
			jumped = false
			hop_f = 0
			if verbose:
				print("      landed on %s at frame %d" % [ids[idx], f])
			if idx == ids.size() - 1:
				ok = true
				break
			if not forward_down:
				Input.action_press("forward")
				forward_down = true
			await process_frame
			continue
		# In the air over the next pad: let go and drop onto it.
		if not on_floor and jumped and _inside(nxt, p, -0.25) and p.y < nxt.end.y + 2.5:
			if forward_down:
				Input.action_release("forward")
				forward_down = false
		elif not forward_down:
			Input.action_press("forward")
			forward_down = true
		if on_floor and not jumped:
			var dir := to.normalized()
			if _exit_dist(cur, Vector3(p.x, 0, p.z), dir) <= float(opts.get("edge", 0.3)) or not _inside(cur, p, 0.2):
				Input.action_press("jump")
				release_jump_at = f + 2
				jumped = true
		if release_jump_at > 0 and f >= release_jump_at:
			Input.action_release("jump")
			release_jump_at = -1
		if hop_f > 300 or p.y < boxes[idx].end.y - 30.0:
			break
		await process_frame
	Input.action_release("forward")
	Input.action_release("jump")
	return {"ok": ok, "frames": f, "wall": wall, "end": pilot.global_position,
		"hop_from": ids[idx], "hop_to": ids[mini(idx + 1, ids.size() - 1)]}


## Run a wall: stand hugging the face at one end of a ledge and run its length; the wall ends and he
## should land on the balcony beyond. `pad_from`'s `toward` points at the wall.
func _wall_run(name: String, from_id: String, to_id: String, along: Vector3, frames := 420) -> void:
	if not _wanted(name):
		return
	var pf: Dictionary = rt.pads[from_id]
	var a: AABB = rt.box_of(from_id)
	var b: AABB = rt.box_of(to_id)
	var toward: Vector3 = pf.toward
	var depth: float = pf.depth
	along = along.normalized()
	# The far-back end of the ledge, `0.5` m off the wall.
	var c := a.get_center()
	var half_len: float = pf.len * 0.5 if pf.len > 0.0 else 1.0
	var start := Vector3(c.x, a.end.y, c.z) - along * (half_len - 0.3)
	start += toward * (depth * 0.5 - 0.5)
	var last := {}
	for sprint: bool in [false, true]:
		last = await _attempt(a, b, start, along, {"sprint": sprint, "frames": frames, "edge": 0.25})
		if last.landed and last.saw_run:
			_report(name, true, "%s: %s" % ["sprint" if sprint else "run", _end_str(last)])
			return
	_report(name, false, _end_str(last))


## From pad `from_id` run off its edge onto a rail, ride it, and expect to land on `to_id`.
func _rail(name: String, from_id: String, rail_id: String, to_id: String, dir: Vector3, start_back := 5.0, sprint_gear := false) -> void:
	if not _wanted(name):
		return
	var a: AABB = rt.box_of(from_id)
	var b: AABB = rt.box_of(to_id)
	var r: Dictionary = rt._rail(rail_id)
	var p0: Vector3 = r.pts[0]
	dir = dir.normalized()
	var start := Vector3(p0.x, a.end.y, p0.z) - dir * start_back
	await _spawn_pilot(start, _yaw_for(dir))
	Input.action_press("forward")
	var f := 0
	var grind_frames := 0
	var landed := false
	var started := -1
	while f < 1200:
		f += 1
		pilot.sprint_toggled = sprint_gear
		if pilot.is_rail_grinding:
			grind_frames += 1
			if started < 0:
				started = f
		var p := pilot.global_position
		if started > 0 and not pilot.is_rail_grinding and pilot.is_on_floor() \
				and _inside(b, p, 0.5) and absf(p.y - b.end.y) < 0.5:
			landed = true
			break
		if p.y < b.end.y - 25.0:
			break
		await process_frame
	Input.action_release("forward")
	_report(name, landed and grind_frames > 20, "caught at frame %d, rode %d frames, end (%.1f, %.1f, %.1f)" % [
		started, grind_frames, pilot.global_position.x, pilot.global_position.y, pilot.global_position.z])


## A row of vault walls along `dir` from `start`; jump when each is close.
func _vault_row(name: String, start: Vector3, dir: Vector3, wall_ids: Array, target: AABB, frames := 700) -> void:
	if not _wanted(name):
		return
	dir = dir.normalized()
	await _spawn_pilot(start, _yaw_for(dir))
	Input.action_press("forward")
	var f := 0
	var vaults := 0
	var was_vaulting := false
	var arrived := false
	var jump_until := -1
	while f < frames:
		f += 1
		pilot.sprint_toggled = true
		var p := pilot.global_position
		if pilot.is_vaulting and not was_vaulting:
			vaults += 1
		was_vaulting = pilot.is_vaulting
		if jump_until < 0 and pilot.is_on_floor():
			for id: String in wall_ids:
				var w: Dictionary = rt._wall(id)
				var c: Vector3 = w.center
				var sz: Vector3 = w.size
				var ahead := (c - p).dot(dir) - maxf(absf(sz.x * dir.x), absf(sz.z * dir.z)) * 0.5
				if ahead > 0.0 and ahead < 1.1:
					Input.action_press("jump")
					jump_until = f + 2
					break
		elif jump_until > 0 and f >= jump_until:
			Input.action_release("jump")
			jump_until = -1
		if _inside(target, p, 0.0) and pilot.is_on_floor() and absf(p.y - target.end.y) < 0.6:
			arrived = true
			break
		await process_frame
	Input.action_release("forward")
	Input.action_release("jump")
	_report(name, arrived, "vaults %d of %d, frames %d, end (%.1f, %.1f, %.1f)" % [vaults,
		wall_ids.size(), f, pilot.global_position.x, pilot.global_position.y, pilot.global_position.z])


## A mantle: from a pad run at the wall it hangs on and jump a body-length short of it.
func _mantle(name: String, from_id: String, target: AABB, toward: Vector3, depth: float, top_check := true) -> void:
	if not _wanted(name):
		return
	var a: AABB = rt.box_of(from_id)
	var c := a.get_center()
	var start := Vector3(c.x, a.end.y, c.z) - toward * (depth * 0.5 - 0.4)
	await _spawn_pilot(start, _yaw_for(toward))
	Input.action_press("forward")
	var f := 0
	var climbed := false
	var done := false
	var jumped := false
	var wall_pt := Vector3(c.x, 0, c.z) + toward * (depth * 0.5)
	while f < 420:
		f += 1
		var p := pilot.global_position
		if pilot.is_climbing:
			climbed = true
		if not jumped and pilot.is_on_floor() and f > 20:
			if wall_pt.distance_to(Vector3(p.x, 0, p.z)) < 1.4:
				Input.action_press("jump")
				jumped = true
		elif jumped and f % 4 == 0:
			Input.action_release("jump")
		if climbed and pilot.is_on_floor() and _inside(target, p, 0.2) and absf(p.y - target.end.y) < 0.4:
			done = true
			break
		await process_frame
	Input.action_release("forward")
	Input.action_release("jump")
	_report(name, done, "mantled %s, end (%.1f, %.1f, %.1f)" % [str(climbed), pilot.global_position.x,
		pilot.global_position.y, pilot.global_position.z])


func _main() -> void:
	var probe: Object = (load("res://scripts/pilot9.gd") as GDScript).new()
	lim = ROUTES.limits(probe)
	(probe as Node).free()
	rt = ROUTES.new()
	rt.build(lim)
	await _spawn_world()
	var anchors: Dictionary = ROUTES.anchors()

	# --- the spine, east: the cab drop, the gates, the way down to the terraces ---
	for gear in [false, true]:
		var tag := " (sprint gear)" if gear else " (grind gear)"
		await _rail("R1 cab drop rail" + tag, "cab_deck", "R1", "concourse", Vector3(0, 0, -1), 6.0, gear)
	await _vault_row("concourse vault gates", Vector3(-22, 5.0, 45.0), Vector3(-1, 0, 0), ["gate0", "gate1", "gate2"],
		AABB(Vector3(-70, 4.0, 41.0), Vector3(12.0, 1.5, 9.0)))
	await _hop("step up to t0_step", "hedge", "t0_step", {"start": Vector3(-62.0, 0.0, 36.0), "near_b": 2.3})
	await _hop("t0_step to t0_lo", "t0_step", "t0_lo")
	await _hop("t0 to t1", "t0", "t1", {"inset": 0.2})
	await _hop("t3 to t4", "t3", "t4", {"inset": 0.2})

	# --- the cliff stair and the bridge ---
	await _hop("t4_left to cs1", "t4_left", "cs1", {"start": Vector3(-96.5, 11.9, -40.0), "near_b": 1.0})
	await _chain("cliff stair cs1..cs5", ["cs1", "cs2", "cs3", "cs4", "cs5"])
	await _mantle("cs5 mantles onto the cliff", "cs5", anchors.cliff, Vector3(0, 0, -1), 1.8)

	# --- the branches ---
	for gear in [false, true]:
		var tag2 := " (sprint gear)" if gear else " (grind gear)"
		await _rail("R3 plaza to the island" + tag2, "plaza", "R3", "island_deck", Vector3(0, 0, 1), 5.0, gear)
		await _rail("R2 cliff line" + tag2, "cliff", "R2", "t0", Vector3(0, 0, 1), 4.0, gear)
	await _hop("B2 wall-run to the hedge balcony", "concourse", "hedge_pod",
		{"start": Vector3(12.05, 5.0, 51.0), "dir": Vector3(0, 0, -1), "wall_run": true, "frames": 600, "edge": 0.35})
	await _vault_row("B1 gallery vault gates", Vector3(40, 5.0, 44.0), Vector3(1, 0, 0), ["gv0", "gv1", "gv2"],
		AABB(Vector3(72.0, 4.0, 40.0), Vector3(14.0, 1.5, 12.0)))

	# --- the tower: the first ledge, then every chain of hops, every run, the pods, the summit ---
	await _hop("bridge to the step", "bridge", "bridge_step", {"start": Vector3(14.0, 20.0, -58.0), "near_b": 1.6})
	await _hop("step to the first ledge", "bridge_step", "s0_0")
	var chain: Array = []
	var n_chain := 0
	for l: Dictionary in rt.links:
		var ring: bool = l.mech == "hop" and l.branch == "spine" and rt.pads.has(l.from) and rt.pads.has(l.to) \
			and rt.pads[l.from].has("s") and rt.pads[l.to].has("s")
		if ring and (chain.is_empty() or chain[chain.size() - 1] == l.from):
			if chain.is_empty():
				chain.append(l.from)
			chain.append(l.to)
			continue
		if chain.size() >= 2:
			n_chain += 1
			await _chain("climb chain %d (%s .. %s)" % [n_chain, chain[0], chain[chain.size() - 1]], chain)
		chain = []
		if ring:
			chain.append(l.from)
			chain.append(l.to)
	if chain.size() >= 2:
		n_chain += 1
		await _chain("climb chain %d (%s .. %s)" % [n_chain, chain[0], chain[chain.size() - 1]], chain)
	for k in 4:
		var dep := ""
		var arr := ""
		for id: String in rt.stage_pads[k]:
			if id.ends_with("_dep"):
				dep = id
			if id.ends_with("_arr"):
				arr = id
		var fc: Dictionary = ROUTES.FACES[int(rt.pads[dep].face)]
		await _wall_run("stage %d wall-run" % (k + 1), dep, arr, fc.t)
	await _hop("B5 hop to the lookout pod", rt.rest_ids[1], "pod_hop", {"inset": 0.35, "frames": 480})
	var rest2: Dictionary = rt.pads[rt.rest_ids[2]]
	var fc2: Dictionary = ROUTES.FACES[int(rest2.face)]
	await _wall_run("B6 wall-run to the far pod", rest2.id, "pod_run", -(fc2.t as Vector3), 600)
	await _mantle("summit mantle", rt.rest_ids[3], anchors.roof, rt.pads[rt.rest_ids[3]].toward,
		float(rt.pads[rt.rest_ids[3]].depth))

	print("")
	if fails.is_empty():
		print("PROBE PASS  %d scenarios" % passes)
		quit(0)
	else:
		print("PROBE FAIL  %d of %d failed: %s" % [fails.size(), fails.size() + passes, ", ".join(fails)])
		quit(1)
