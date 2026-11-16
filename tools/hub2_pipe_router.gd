extends RefCounted

# Routes hub2's pipe bundles so no pipe ends in the air (docs/specs/hub2-pipe-routing.md).
# A route starts on a wall/ceiling crease (from Hub2WearBake's concave lines) and WALKS along the wall in
# both directions with rays: an inside corner (wall ahead) -> turn and follow the new wall, or run
# straight into it; the wall ending (outside corner) -> wrap round the edge, or elbow into the wall just
# before it; a prop / crane / another pipe in the way -> elbow into the wall before it. Then vertical
# drops in wall-wall inside corners: tee into a bundle bending in that corner, or up into the ceiling,
# and down into the floor.
#
# Geometry: a route is a list of wall LINES (q = a point on the wall plane, d = travel direction, w =
# toward the wall, all horizontal). A horizontal bundle is stacked down the wall, so pipe k is the
# line shifted out by its wall offset o_k at its own height y_k; its bends are where consecutive shifted
# lines cross.

const STEP := 0.5
## A turn is only taken when the new wall is clear for this long.
const MIN_TURN := 4.0
const MAX_LINE := 260.0
const CELL := 4.0

var ss: PhysicsDirectSpaceState3D
## Colliders under this node are the map; anything else is a prop.
var map_root: Node
var rng := RandomNumberGenerator.new()

## Placed pipe segments [a, b, r] and a grid of them.
var _segs: Array = []
var _grid := {}
## Inside corners a bundle bent round: {xz: Vector2, low: {points, i, r}} (its lowest pipe).
var _corners: Array = []
## Output: Array of routes; a route is Array of pipe dicts (Hub2PipeRun fields + "view").
var routes: Array = []
var stats := {}


func _stat(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


# -- rays --------------------------------------------------------------------------------------------

func _hit(a: Vector3, b: Vector3) -> Dictionary:
	var r := ss.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	if not r.is_empty():
		r["map"] = map_root.is_ancestor_of(r["collider"])
		r["dist"] = a.distance_to(r["position"])
	return r


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z).normalized()


# -- bundles -----------------------------------------------------------------------------------------

## A horizontal bundle hung under a ceiling at ceil_y: pipes stacked down the wall.
func _bundle(ceil_y: float, count: int) -> Dictionary:
	var pipes: Array = []
	var off := 0.12
	var depth := 0.0
	var max_r := 0.0
	for k in count:
		var r := rng.randf_range(0.15, 0.6) if k == 0 else rng.randf_range(0.15, 0.4)
		pipes.append({"r": r, "o": r + 0.15, "y": ceil_y - (off + r)})
		off += 2.0 * r + 0.12
		depth = maxf(depth, r * 2.0 + 0.15)
		max_r = maxf(max_r, r)
	var top: float = pipes[0]["y"] + pipes[0]["r"]
	var bot: float = pipes[-1]["y"] - pipes[-1]["r"]
	return {"pipes": pipes, "top": top, "bot": bot, "depth": depth, "max_r": max_r,
		"top_c": pipes[0]["y"], "bot_c": pipes[-1]["y"]}


# -- walking -----------------------------------------------------------------------------------------

static func _line(q: Vector3, d: Vector3, w: Vector3) -> Dictionary:
	return {"q": Vector3(q.x, 0, q.z), "d": d, "w": w}


static func _at(line: Dictionary, s: float, o: float, y: float) -> Vector3:
	var p: Vector3 = line["q"] + line["d"] * s - line["w"] * o
	return Vector3(p.x, y, p.z)


## "ok" while the wall is beside the bundle at both its top and bottom pipe, "gone" when it falls away,
## "close" when something sticks out of it.
func _side(line: Dictionary, s: float, b: Dictionary) -> String:
	var back: float = b["depth"] + 0.6
	for y: float in [b["top_c"], b["bot_c"]]:
		var p := _at(line, s, back, y)
		var h := _hit(p, p + line["w"] * (back + 0.5))
		if h.is_empty():
			return "gone"
		if not h["map"]:
			return "close"
		var dist: float = h["dist"]
		if dist > back + 0.2 or (h["normal"] as Vector3).dot(-line["w"]) < 0.9:
			return "gone"
		if dist < back - 0.2:
			return "close"
	return "ok"


## Walks `line` from s0 to s_max. Returns the first event: {type: hit|pipe|gone|close|end, s, ...}.
func _walk(line: Dictionary, s0: float, s_max: float, b: Dictionary, side := true) -> Dictionary:
	var s := s0
	var depth: float = b["depth"]
	var mid_y: float = (b["top"] + b["bot"]) * 0.5
	var half: float = maxf(depth * 0.5, (b["top"] - b["bot"]) * 0.5) + 0.05
	while s < s_max - 0.001:
		var s1 := minf(s + STEP, s_max)
		var best := {}
		for o: float in [0.1, depth * 0.5, depth]:
			for y: float in [b["top"] - 0.02, mid_y, b["bot"]]:
				var a := _at(line, s, o, y)
				var h := _hit(a, a + line["d"] * (s1 - s + 0.05))
				if not h.is_empty() and (best.is_empty() or h["dist"] < best["dist"]):
					best = h
		if not best.is_empty():
			return {"type": "hit", "s": s + float(best["dist"]), "n": best["normal"], "p": best["position"], "map": best["map"]}
		if _pipe_near(_at(line, s, depth * 0.5, mid_y), _at(line, s1, depth * 0.5, mid_y), half):
			return {"type": "pipe", "s": s}
		if side:
			var st := _side(line, s1, b)
			if st != "ok":
				return {"type": st, "s": s1}
		s = s1
	return {"type": "end", "s": s_max}


## Walks one direction from the seed. {lines, end}: end = {kind: plane, p, n} or {kind: elbow, s, line}.
func _extend(line0: Dictionary, b: Dictionary, budget: int) -> Dictionary:
	var lines: Array = [line0]
	var line := line0
	var s0 := 0.0
	var s_min := 0.0
	var max_r: float = b["max_r"]
	var depth: float = b["depth"]
	for _guard in 16:
		var ev := _walk(line, s0, MAX_LINE, b)
		var t: String = ev["type"]
		if t == "hit":
			var n: Vector3 = ev["n"]
			var d: Vector3 = line["d"]
			if ev["map"] and absf(n.y) < 0.2 and n.dot(d) < -0.85:
				if budget > 0:
					var nl := _try_inside(line, ev, b)
					if not nl.is_empty():
						lines.append(nl)
						line = nl
						s0 = 0.3
						s_min = depth + 0.4
						budget -= 1
						_stat("turn_inside")
						continue
				_stat("end_wall_ahead")
				return {"lines": lines, "end": {"kind": "plane", "p": ev["p"], "n": n}}
			if ev["map"] and n.dot(d) < -0.5:
				_stat("end_surface")
				return {"lines": lines, "end": {"kind": "plane", "p": ev["p"], "n": n}}
			_stat("end_blocked")
			return _elbow_end(lines, line, float(ev["s"]) - (max_r * 1.5 + 0.8), s_min)
		if t == "gone":
			var se := _edge(line, float(ev["s"]) - STEP, float(ev["s"]), b)
			if budget > 0:
				var nl := _try_outside(line, se, b)
				if not nl.is_empty():
					lines.append(nl)
					line = nl
					s0 = 0.3
					s_min = 0.3
					budget -= 1
					_stat("turn_outside")
					continue
			_stat("end_before_edge")
			return _elbow_end(lines, line, se - (max_r * 1.5 + 0.6), s_min)
		if t == "end":
			_stat("end_max")
			return _elbow_end(lines, line, float(ev["s"]), s_min)
		_stat("end_" + t)
		return _elbow_end(lines, line, float(ev["s"]) - 1.0, s_min)
	return _elbow_end(lines, line, s0, s_min)


func _elbow_end(lines: Array, line: Dictionary, s: float, s_min: float) -> Dictionary:
	return {"lines": lines, "end": {"kind": "elbow", "s": maxf(s, s_min), "line": line}}


## Finds where the wall falls away between s_ok and s_gone.
func _edge(line: Dictionary, s_ok: float, s_gone: float, b: Dictionary) -> float:
	var lo := s_ok
	var hi := s_gone
	for _i in 7:
		var m := (lo + hi) * 0.5
		if _side(line, m, b) == "ok":
			lo = m
		else:
			hi = m
	return lo


func _try_inside(line: Dictionary, ev: Dictionary, b: Dictionary) -> Dictionary:
	var nh := _flat(ev["n"])
	var nd := nh.cross(Vector3.UP).normalized()
	if nd.dot(-line["w"]) < 0.0:
		nd = -nd
	if nd.dot(-line["w"]) < 0.7:
		return {}
	var q: Vector3 = line["q"]
	var d: Vector3 = line["d"]
	var p: Vector3 = ev["p"]
	var sc := Vector3(p.x - q.x, 0, p.z - q.z).dot(nh) / d.dot(nh)
	var nl := _line(q + d * sc, nd, -nh)
	if _walk(nl, 0.3, MIN_TURN, b)["type"] != "end":
		return {}
	return nl


func _try_outside(line: Dictionary, se: float, b: Dictionary) -> Dictionary:
	var d: Vector3 = line["d"]
	var w: Vector3 = line["w"]
	var mid_y: float = (b["top"] + b["bot"]) * 0.5
	var x := _at(line, se + 1.0, -1.0, mid_y)
	var h := _hit(x, x - d * 2.2)
	if h.is_empty() or not h["map"]:
		return {}
	var nh := _flat(h["normal"])
	if nh.dot(d) < 0.85 or absf((h["normal"] as Vector3).y) > 0.2:
		return {}
	var nd := nh.cross(Vector3.UP).normalized()
	if nd.dot(w) < 0.0:
		nd = -nd
	if nd.dot(w) < 0.7:
		return {}
	var q: Vector3 = line["q"]
	var p: Vector3 = h["position"]
	var sc := Vector3(p.x - q.x, 0, p.z - q.z).dot(nh) / d.dot(nh)
	# The bundle passes the edge by up to its depth before it bends: that stretch must be clear too.
	if _walk(line, se, sc + float(b["depth"]) + 0.3, b, false)["type"] != "end":
		return {}
	var nl := _line(q + d * sc, nd, -nh)
	if _walk(nl, 0.3, MIN_TURN, b)["type"] != "end":
		return {}
	return nl


# -- pipe registry -----------------------------------------------------------------------------------

func _cells(a: Vector3, b: Vector3, grow: float) -> Array:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * grow
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * grow
	var out: Array = []
	for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for y in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			for z in range(floori(lo.z / CELL), floori(hi.z / CELL) + 1):
				out.append(Vector3i(x, y, z))
	return out


func _add_seg(a: Vector3, b: Vector3, r: float) -> void:
	var i := _segs.size()
	_segs.append([a, b, r])
	for c: Vector3i in _cells(a, b, r):
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(i)


## True when a capsule a-b of radius r comes within reach of a placed pipe.
func _pipe_near(a: Vector3, b: Vector3, r: float, ignore := -1) -> bool:
	var seen := {}
	for c: Vector3i in _cells(a, b, r + 0.7):
		if not _grid.has(c):
			continue
		for i: int in _grid[c]:
			if seen.has(i) or i == ignore:
				continue
			seen[i] = true
			var s: Array = _segs[i]
			if seg_dist(a, b, s[0], s[1]) < r + float(s[2]) + 0.08:
				return true
	return false


## Closest distance between segments p1-q1 and p2-q2.
static func seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var den := a * e - bb * bb
			s = clampf((bb * f - c * e) / den, 0.0, 1.0) if den > 1e-9 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


# -- routes ------------------------------------------------------------------------------------------

## The frame at a crease point: {q (on the wall plane), d, w, ceil} or {} when it isn't a wall/ceiling
## crease with open room beside it.
func crease_frame(mid: Vector3, dir: Vector3) -> Dictionary:
	var d := _flat(dir)
	var perp := d.cross(Vector3.UP).normalized()
	for sgn: float in [1.0, -1.0]:
		var room := perp * sgn
		var p := mid + room * 1.0 + Vector3.DOWN * 0.8
		var wh := _hit(p, p - room * 1.6)
		if wh.is_empty() or not wh["map"] or (wh["normal"] as Vector3).dot(room) < 0.9 or absf(float(wh["dist"]) - 1.0) > 0.3:
			continue
		var ch := _hit(p, p + Vector3.UP * 1.6)
		if ch.is_empty() or not ch["map"] or (ch["normal"] as Vector3).y > -0.9:
			continue
		return {"q": wh["position"], "d": d, "w": -room, "ceil": (ch["position"] as Vector3).y}
	return {}


static func _flip(line: Dictionary) -> Dictionary:
	return {"q": line["q"], "d": -(line["d"] as Vector3), "w": line["w"]}


## 2D crossing of two lines (XZ); y from `y`.
static func _cross(qa: Vector3, da: Vector3, qb: Vector3, db: Vector3, y: float) -> Vector3:
	var den := da.x * db.z - da.z * db.x
	if absf(den) < 1e-6:
		return Vector3(qb.x, y, qb.z)
	var dx := qb.x - qa.x
	var dz := qb.z - qa.z
	var t := (dx * db.z - dz * db.x) / den
	return Vector3(qa.x + da.x * t, y, qa.z + da.z * t)


## Tries one route from a seed crease; places it and returns true when it is good.
func route_from(frame: Dictionary, services: Array, view: float) -> bool:
	var b := _bundle(frame["ceil"], rng.randi_range(1, 4))
	var turns := rng.randi_range(1, 4)
	var fwd_budget := rng.randi_range(0, turns)
	var seed_line := _line(frame["q"], frame["d"], frame["w"])
	# The seed spot itself must be clear.
	if _side(seed_line, 0.0, b) != "ok" or _walk(seed_line, -0.25, 0.25, b)["type"] != "end":
		_stat("seed_rejected")
		return false
	var fwd := _extend(seed_line, b, fwd_budget)
	var bwd := _extend(_flip(seed_line), b, turns - fwd_budget)
	var lines: Array = []
	for k in range(bwd["lines"].size() - 1, 0, -1):
		lines.append(_flip(bwd["lines"][k]))
	lines.append_array(fwd["lines"])
	var start_end: Dictionary = bwd["end"]
	if start_end["kind"] == "elbow":
		start_end = {"kind": "elbow", "s": start_end["s"], "line": _flip(start_end["line"])}
	var service: int = services[rng.randi() % services.size()]
	var pipes: Array = []
	var sag_k := (b["pipes"] as Array).size() - 1 if rng.randf() < 0.08 else -1
	for k in (b["pipes"] as Array).size():
		var pk: Dictionary = b["pipes"][k]
		var pd := _pipe_path(lines, start_end, fwd["end"], pk["o"], pk["y"])
		if pd.is_empty():
			_stat("route_bad_geometry")
			return false
		pd["radius"] = pk["r"]
		pd["service"] = service if k == 0 or rng.randf() < 0.6 else services[rng.randi() % services.size()]
		pd["mount_gap"] = pk["r"] + 0.15
		pd["sag"] = k == sag_k
		pd["view"] = view
		pipes.append(pd)
	# Long enough to be worth it (centre line of the top pipe).
	var total := 0.0
	var pts0: PackedVector3Array = pipes[0]["points"]
	for i in pts0.size() - 1:
		total += pts0[i].distance_to(pts0[i + 1])
	if total < 4.0:
		_stat("route_too_short")
		return false
	for pd: Dictionary in pipes:
		if not _ends_ok(pd):
			_stat("route_loose_end")
			return false
	for pd: Dictionary in pipes:
		var pts: PackedVector3Array = pd["points"]
		for i in pts.size() - 1:
			_add_seg(pts[i], pts[i + 1], pd["radius"])
	# Inside bends, for drops to tee into: the bundle's lowest pipe.
	var low: Dictionary = pipes[-1]
	var lp: PackedVector3Array = low["points"]
	var first := 1 if start_end["kind"] == "plane" else 2
	for j in lines.size() - 1:
		var la: Dictionary = lines[j]
		var lb: Dictionary = lines[j + 1]
		if (la["d"] as Vector3).dot(lb["w"]) > 0.7:
			var c := _cross(la["q"], la["d"], lb["q"], lb["d"], 0.0)
			_corners.append({"xz": Vector2(c.x, c.z), "points": lp, "i": first + j, "r": low["radius"]})
	routes.append(pipes)
	stats["route_len"] = float(stats.get("route_len", 0.0)) + total
	return true


## One pipe of a bundle along the route at wall offset o, height y. {} when the geometry folds back.
func _pipe_path(lines: Array, start: Dictionary, end: Dictionary, o: float, y: float) -> Dictionary:
	var pts := PackedVector3Array()
	var mounts := PackedVector3Array()
	var l0: Dictionary = lines[0]
	var res := {}
	# Start.
	if start["kind"] == "plane":
		pts.append(_plane_point(l0, o, y, start["p"], start["n"]))
		res["end_a_normal"] = start["n"]
	else:
		var sl: Dictionary = start["line"]
		var at := _at(sl, start["s"], 0.0, y)
		pts.append(at)
		pts.append(_at(sl, start["s"], o, y))
		mounts.append(sl["w"])
		res["end_a_normal"] = -(sl["w"] as Vector3)
	for j in lines.size() - 1:
		var la: Dictionary = lines[j]
		var lb: Dictionary = lines[j + 1]
		mounts.append(la["w"])
		pts.append(_cross((la["q"] as Vector3) - la["w"] * o, la["d"], (lb["q"] as Vector3) - lb["w"] * o, lb["d"], y))
	var ll: Dictionary = lines[-1]
	mounts.append(ll["w"])
	if end["kind"] == "plane":
		pts.append(_plane_point(ll, o, y, end["p"], end["n"]))
		res["end_b_normal"] = end["n"]
	else:
		var el: Dictionary = end["line"]
		pts.append(_at(el, end["s"], o, y))
		pts.append(_at(el, end["s"], 0.0, y))
		mounts.append(el["w"])
		res["end_b_normal"] = -(el["w"] as Vector3)
	# Every run along a line must go forward along it (no fold-backs from tight ends).
	var li := 0
	var i0 := 0 if start["kind"] == "plane" else 1
	for i in range(i0, pts.size() - 1 - (0 if end["kind"] == "plane" else 1)):
		var seg := pts[i + 1] - pts[i]
		if seg.dot(lines[li]["d"]) < 0.3:
			return {}
		li += 1
	res["points"] = pts
	res["mount_dirs"] = mounts
	res["end_a"] = Hub2PipeRun.End.WALL
	res["end_b"] = Hub2PipeRun.End.WALL
	return res


func _plane_point(line: Dictionary, o: float, y: float, p: Vector3, n: Vector3) -> Vector3:
	var a := _at(line, 0.0, o, y)
	var d: Vector3 = line["d"]
	var t := (p - a).dot(n) / d.dot(n)
	return a + d * t


# -- vertical drops ----------------------------------------------------------------------------------

## A drop in the wall-wall inside corner at `c` (a point on the corner line), `n` the corner line's
## inward normal on one face. Places it and returns true.
func drop_at(c: Vector3, n: Vector3, dir: Vector3, services: Array, view: float, chance_free: float, chance_tee: float) -> bool:
	var ng := _flat(n)
	var nf := Vector3.ZERO
	for cand: Vector3 in [_flat(dir.cross(n)), -_flat(dir.cross(n))]:
		var p := c + (cand + ng) * 1.0
		var hf := _hit(p, p - cand * 1.6)
		var hg := _hit(p, p - ng * 1.6)
		if hf.is_empty() or hg.is_empty() or not hf["map"] or not hg["map"]:
			continue
		if (hf["normal"] as Vector3).dot(cand) > 0.9 and (hg["normal"] as Vector3).dot(ng) > 0.9 \
				and absf(float(hf["dist"]) - 1.0) < 0.3 and absf(float(hg["dist"]) - 1.0) < 0.3:
			nf = cand
			# Snap the corner onto the two wall planes.
			var pf: Vector3 = hf["position"]
			var pg: Vector3 = hg["position"]
			c = Vector3(c.x, c.y, c.z)
			c += nf * (pf - c).dot(nf) + ng * (pg - c).dot(ng)
			break
	if nf == Vector3.ZERO:
		_stat("drop_no_corner")
		return false
	# A bundle bending in this corner?
	var host := {}
	for cr: Dictionary in _corners:
		if (cr["xz"] as Vector2).distance_to(Vector2(c.x, c.z)) < 0.4:
			var hp: PackedVector3Array = cr["points"]
			if hp[cr["i"]].y > c.y - 2.0 and (host.is_empty() or hp[cr["i"]].y < (host["points"] as PackedVector3Array)[host["i"]].y):
				host = cr
	if rng.randf() > (chance_tee if not host.is_empty() else chance_free):
		_stat("drop_skipped")
		return false
	var r: float
	var top: Vector3
	var end_a: Hub2PipeRun.End
	var end_a_normal: Vector3
	var tee_r := 0.3
	if not host.is_empty():
		var em := Hub2PipeRun.elbow_mid(host["points"], host["i"], host["r"])
		tee_r = host["r"]
		r = minf(rng.randf_range(0.12, 0.3), tee_r * 0.75)
		top = em[0]
		end_a = Hub2PipeRun.End.TEE
		end_a_normal = em[1]
	else:
		r = rng.randf_range(0.12, 0.35)
		var at := c + nf * (r + 0.15) + ng * (r + 0.15)
		var up := _hit(Vector3(at.x, c.y, at.z), Vector3(at.x, c.y + 60.0, at.z))
		if up.is_empty() or not up["map"] or (up["normal"] as Vector3).y > -0.5:
			_stat("drop_no_ceiling")
			return false
		top = up["position"]
		end_a = Hub2PipeRun.End.WALL
		end_a_normal = up["normal"]
	var from := top + Vector3.DOWN * (tee_r + 0.05 if end_a == Hub2PipeRun.End.TEE else 0.05)
	var down := _hit(from, from + Vector3.DOWN * 90.0)
	if down.is_empty() or not down["map"] or (down["normal"] as Vector3).y < 0.8:
		_stat("drop_no_floor")
		return false
	var bottom: Vector3 = down["position"]
	if top.y - bottom.y < 2.0:
		_stat("drop_too_short")
		return false
	# Clear of other pipes (the host's own bend excepted: start below it).
	if _pipe_near(bottom + Vector3.UP * 0.1, from + Vector3.DOWN * (r + 0.15), r):
		_stat("drop_blocked")
		return false
	var pd := {
		"points": PackedVector3Array([top, bottom]),
		"mount_dirs": PackedVector3Array([-nf]),
		"radius": r,
		"service": services[rng.randi() % services.size()],
		"mount_gap": (Vector2(top.x, top.z) - Vector2(c.x, c.z)).dot(Vector2(nf.x, nf.z)),
		"sag": false,
		"view": view,
		"end_a": end_a,
		"end_a_normal": end_a_normal,
		"end_b": Hub2PipeRun.End.WALL,
		"end_b_normal": down["normal"],
		"tee_radius": tee_r,
	}
	if not _ends_ok(pd):
		_stat("drop_loose_end")
		return false
	_add_seg(top, bottom, r)
	routes.append([pd])
	_stat("drop_tee" if end_a == Hub2PipeRun.End.TEE else "drop_ceiling")
	return true


# -- checks ------------------------------------------------------------------------------------------

## Both WALL ends of a pipe meet a map surface (TEE ends are checked once placed).
func _ends_ok(pd: Dictionary) -> bool:
	var pts: PackedVector3Array = pd["points"]
	for e in 2:
		if (pd["end_a"] if e == 0 else pd["end_b"]) != Hub2PipeRun.End.WALL:
			continue
		var p := pts[0] if e == 0 else pts[pts.size() - 1]
		var out := (p - (pts[1] if e == 0 else pts[pts.size() - 2])).normalized()
		var h := _hit(p - out * 0.5, p + out * 0.35)
		if h.is_empty() or not h["map"]:
			return false
	return true


## Every end of every placed pipe: WALL ends must meet a map surface, TEE ends another pipe. Returns the
## failures as strings.
func loose_ends() -> Array:
	var bad: Array = []
	for ri in routes.size():
		for pd: Dictionary in routes[ri]:
			var pts: PackedVector3Array = pd["points"]
			for e in 2:
				var p := pts[0] if e == 0 else pts[pts.size() - 1]
				var q := pts[1] if e == 0 else pts[pts.size() - 2]
				var out := (p - q).normalized()
				var kind: int = pd["end_a"] if e == 0 else pd["end_b"]
				if kind == Hub2PipeRun.End.WALL:
					var h := _hit(p - out * 0.5, p + out * 0.35)
					if h.is_empty() or not h["map"]:
						bad.append("route %d end %d at %s: no surface" % [ri, e, p])
				elif kind == Hub2PipeRun.End.TEE:
					if not _on_other_pipe(p, float(pd["tee_radius"])):
						bad.append("route %d end %d at %s: tee on nothing" % [ri, e, p])
				else:
					bad.append("route %d end %d at %s: open" % [ri, e, p])
	return bad


## True when p lies inside (within r + 0.05 of the axis of) a placed segment that doesn't end at p.
func _on_other_pipe(p: Vector3, r: float) -> bool:
	for c: Vector3i in _cells(p, p, r + 0.5):
		if not _grid.has(c):
			continue
		for i: int in _grid[c]:
			var sg: Array = _segs[i]
			if (sg[0] as Vector3).distance_to(p) < 0.01 or (sg[1] as Vector3).distance_to(p) < 0.01:
				continue
			if seg_dist(p, p, sg[0], sg[1]) < r + 0.05:
				return true
	return false
