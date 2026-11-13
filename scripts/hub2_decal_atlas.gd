class_name Hub2DecalAtlas
extends RefCounted

# The hub2 decal sheet, drawn in code (docs/specs/hub2-industrial.md): vents, hazard stripes, warning
# triangles, arrows, data plates, pipes, stencil text, grime streaks, rust blobs, indicator lights.
# Two images in the same layout: `color` (RGBA, alpha 0 or 1 only, so the decal shader can cut it out
# without blending) and `glow` (what lights up: the amber and red lamps). 16 texels per metre, the same
# grid as the surface shader, so a 32 px vent is 2 m.
#
# build() returns { color: Image, glow: Image, sprites: Array[Dictionary] }, each sprite
#   { name, rect: Rect2i, rot_ok: bool, wall: float, floor: float, ceil: float }   (weights per surface kind)
# Deterministic: same sheet every call.

const SIZE := 512
const TEXELS_PER_METRE := 16.0

const STEEL_DARK := Color(0.10, 0.11, 0.13)
const STEEL_MID := Color(0.22, 0.24, 0.27)
const STEEL_LIGHT := Color(0.37, 0.39, 0.42)
const BLACK := Color(0.035, 0.035, 0.04)
const YELLOW := Color(0.80, 0.61, 0.10)
const YELLOW_DIM := Color(0.62, 0.47, 0.08)
const ORANGE := Color(0.80, 0.34, 0.08)
const WHITE_WORN := Color(0.72, 0.72, 0.68)
const RUST := Color(0.32, 0.15, 0.07)
const RUST_DARK := Color(0.20, 0.09, 0.05)
const GRIME := Color(0.04, 0.035, 0.03)
const AMBER := Color(1.0, 0.62, 0.10)
const RED := Color(1.0, 0.12, 0.08)

const LABELS: Array[String] = [
	"A-07", "B-12", "C-3", "D-18", "HUB 2", "SECTOR 3", "LEVEL 02", "GATE 5", "EXIT", "DANGER", "HV",
	"NO ENTRY", "LIFT 4", "BAY 9", "VENT 2", "PUMP", "E-44", "SERVICE", "WATCH STEP", "AUX 6",
]

# 3x5 stencil font, rows top to bottom, '#' = ink.
const FONT := {
	"A": ".#.|#.#|###|#.#|#.#", "B": "##.|#.#|##.|#.#|##.", "C": ".##|#..|#..|#..|.##",
	"D": "##.|#.#|#.#|#.#|##.", "E": "###|#..|##.|#..|###", "F": "###|#..|##.|#..|#..",
	"G": ".##|#..|#.#|#.#|.##", "H": "#.#|#.#|###|#.#|#.#", "I": "###|.#.|.#.|.#.|###",
	"J": "..#|..#|..#|#.#|.#.", "K": "#.#|#.#|##.|#.#|#.#", "L": "#..|#..|#..|#..|###",
	"M": "#.#|###|###|#.#|#.#", "N": "##.|#.#|#.#|#.#|#.#", "O": ".#.|#.#|#.#|#.#|.#.",
	"P": "##.|#.#|##.|#..|#..", "Q": ".#.|#.#|#.#|##.|.##", "R": "##.|#.#|##.|#.#|#.#",
	"S": ".##|#..|.#.|..#|##.", "T": "###|.#.|.#.|.#.|.#.", "U": "#.#|#.#|#.#|#.#|###",
	"V": "#.#|#.#|#.#|#.#|.#.", "W": "#.#|#.#|###|###|#.#", "X": "#.#|#.#|.#.|#.#|#.#",
	"Y": "#.#|#.#|.#.|.#.|.#.", "Z": "###|..#|.#.|#..|###",
	"0": "###|#.#|#.#|#.#|###", "1": ".#.|##.|.#.|.#.|###", "2": "##.|..#|.#.|#..|###",
	"3": "##.|..#|.#.|..#|##.", "4": "#.#|#.#|###|..#|..#", "5": "###|#..|##.|..#|##.",
	"6": ".##|#..|###|#.#|###", "7": "###|..#|.#.|.#.|.#.", "8": "###|#.#|###|#.#|###",
	"9": "###|#.#|###|..#|##.", "-": "...|...|###|...|...",
}

static func build() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var defs: Array[Dictionary] = []
	# name, w, h, rot_ok, weights (wall, floor, ceil)
	_def(defs, "vent_a", 32, 32, false, 3.0, 0.0, 1.5)
	_def(defs, "vent_b", 16, 16, false, 3.0, 0.0, 1.0)
	_def(defs, "vent_wide", 48, 16, false, 2.0, 0.0, 1.0)
	_def(defs, "vent_tall", 16, 40, false, 1.5, 0.0, 0.0)
	_def(defs, "vent_round", 24, 24, false, 1.6, 0.0, 1.5)
	_def(defs, "hazard_h", 64, 8, true, 1.6, 2.2, 0.0)
	_def(defs, "hazard_short", 32, 8, true, 1.0, 1.4, 0.0)
	_def(defs, "warn_tri", 16, 16, false, 1.2, 0.5, 0.0)
	_def(defs, "arrow", 16, 16, true, 0.8, 2.4, 0.0)
	_def(defs, "plate", 32, 16, false, 1.8, 0.0, 0.6)
	_def(defs, "pipe_a", 64, 8, true, 2.2, 0.0, 3.0)
	_def(defs, "pipe_b", 96, 8, true, 1.2, 0.0, 2.0)
	_def(defs, "lamps_amber", 16, 5, false, 1.2, 0.0, 0.8)
	_def(defs, "lamps_red", 16, 5, false, 0.8, 0.0, 0.5)
	_def(defs, "strip", 32, 3, false, 1.3, 0.0, 0.8)
	_def(defs, "strip_long", 64, 3, false, 0.8, 0.0, 0.5)
	_def(defs, "rust_blob_a", 24, 24, false, 1.6, 2.0, 1.2)
	_def(defs, "rust_blob_b", 40, 20, false, 1.0, 1.4, 0.8)
	_def(defs, "scuff_a", 32, 8, true, 0.0, 3.2, 0.0)
	_def(defs, "scuff_b", 24, 12, true, 0.0, 2.2, 0.0)
	for i in LABELS.size():
		var w := LABELS[i].length() * 8 - 2
		_def(defs, "text_%d" % i, w, 10, false, 0.5, 0.35, 0.0)
	_def(defs, "streak_a", 6, 32, false, 0.0, 0.0, 0.0)
	_def(defs, "streak_b", 10, 48, false, 0.0, 0.0, 0.0)

	var color := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var glow := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	color.fill(Color(0, 0, 0, 0))
	glow.fill(Color(0, 0, 0, 0))
	# Shelf packing, 1 px gaps.
	var x := 1
	var y := 1
	var shelf := 0
	for d in defs:
		var w: int = d["w"]
		var h: int = d["h"]
		if x + w + 1 > SIZE:
			x = 1
			y += shelf + 1
			shelf = 0
		d["rect"] = Rect2i(x, y, w, h)
		_draw(d, color, glow, rng)
		x += w + 1
		shelf = maxi(shelf, h)
	assert(y + shelf < SIZE, "decal sheet overflowed")
	return {"color": color, "glow": glow, "sprites": defs}


static func _def(defs: Array[Dictionary], sprite_name: String, w: int, h: int, rot_ok: bool,
		wall: float, floor_w: float, ceil_w: float) -> void:
	defs.append({"name": sprite_name, "w": w, "h": h, "rot_ok": rot_ok, "wall": wall, "floor": floor_w, "ceil": ceil_w})


static func _put(img: Image, r: Rect2i, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < r.size.x and y < r.size.y:
		img.set_pixel(r.position.x + x, r.position.y + y, Color(c.r, c.g, c.b, 1.0))


static func _fill(img: Image, r: Rect2i, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for yy in range(y0, y0 + h):
		for xx in range(x0, x0 + w):
			_put(img, r, xx, yy, c)


static func _draw(d: Dictionary, color: Image, glow: Image, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = d["rect"]
	var w := r.size.x
	var h := r.size.y
	var n: String = d["name"]
	if n.begins_with("vent_round"):
		_vent_round(color, r)
	elif n.begins_with("vent"):
		_vent(color, r)
	elif n.begins_with("hazard"):
		for yy in h:
			for xx in w:
				var edge := yy == 0 or yy == h - 1
				_put(color, r, xx, yy, BLACK if edge or ((xx + yy) / 4) % 2 == 1 else YELLOW)
	elif n == "warn_tri":
		_warn_tri(color, r)
	elif n == "arrow":
		for yy in h:
			for xx in w:
				var ax := absf(xx - 7.5)
				if absf(yy - (ax + 4.0)) < 2.1 and ax < 7.0:
					_put(color, r, xx, yy, YELLOW)
	elif n == "plate":
		_plate(color, r, rng)
	elif n.begins_with("pipe"):
		_pipe(color, r)
	elif n.begins_with("lamps"):
		var lit := AMBER if n == "lamps_amber" else RED
		for i in 3:
			var ox := 1 + i * 5
			_fill(color, r, ox, 0, 4, 5, BLACK)
			_fill(color, r, ox + 1, 1, 2, 3, lit * 0.45 if rng.randf() < 0.3 else lit)
			_fill(glow, r, ox + 1, 1, 2, 3, lit)
	elif n.begins_with("strip"):
		_fill(color, r, 0, 0, w, h, BLACK)
		var seg := 0
		while seg * 5 + 4 <= w:
			var roll := rng.randf()
			if roll < 0.55:
				var lit := AMBER if rng.randf() < 0.6 else RED
				_fill(color, r, seg * 5, 1, 4, 1, lit)
				_fill(glow, r, seg * 5, 1, 4, 1, lit)
			else:
				_fill(color, r, seg * 5, 1, 4, 1, STEEL_DARK)
			seg += 1
	elif n.begins_with("rust_blob"):
		_blob(color, r, rng)
	elif n.begins_with("scuff"):
		_scuff(color, r, rng)
	elif n.begins_with("text"):
		var idx := int(n.substr(5))
		var ink := YELLOW_DIM if LABELS[idx] in ["DANGER", "HV", "NO ENTRY", "WATCH STEP"] else WHITE_WORN
		_text(color, r, LABELS[idx], ink, rng)
	elif n.begins_with("streak"):
		_streak(color, r, rng)


static func _vent(img: Image, r: Rect2i) -> void:
	var w := r.size.x
	var h := r.size.y
	_fill(img, r, 0, 0, w, h, STEEL_DARK)
	_fill(img, r, 0, 0, w, 1, STEEL_MID)
	_fill(img, r, 0, 0, 1, h, STEEL_MID)
	_fill(img, r, 0, h - 1, w, 1, BLACK)
	_fill(img, r, w - 1, 0, 1, h, BLACK)
	var m := 3
	_fill(img, r, m, m, w - m * 2, h - m * 2, BLACK)
	var yy := m
	while yy + 3 <= h - m:
		_fill(img, r, m, yy, w - m * 2, 1, STEEL_LIGHT)
		_fill(img, r, m, yy + 1, w - m * 2, 2, STEEL_MID)
		yy += 4
	for p in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		_put(img, r, p.x, p.y, STEEL_LIGHT)


static func _vent_round(img: Image, r: Rect2i) -> void:
	var s := r.size.x
	var c := (s - 1) * 0.5
	var rad := s * 0.5
	for yy in s:
		for xx in s:
			var dx := xx - c
			var dy := yy - c
			var dist := sqrt(dx * dx + dy * dy)
			if dist > rad:
				continue
			if dist > rad - 2.0:
				_put(img, r, xx, yy, STEEL_MID if dx + dy < 0.0 else STEEL_DARK)
			elif dist < 3.0:
				_put(img, r, xx, yy, STEEL_LIGHT)
			else:
				var blade := int(floor((atan2(dy, dx) + PI) / TAU * 8.0)) % 2
				_put(img, r, xx, yy, STEEL_MID if blade == 0 else BLACK)


static func _warn_tri(img: Image, r: Rect2i) -> void:
	for yy in range(1, 15):
		var half := (yy - 1) * 0.5 + 0.5
		for xx in 16:
			var ax := absf(xx - 7.5)
			if ax <= half:
				var edge := ax > half - 1.0 or yy >= 14
				_put(img, r, xx, yy, BLACK if edge else YELLOW)
	for yy in range(6, 11):
		_put(img, r, 7, yy, BLACK)
		_put(img, r, 8, yy, BLACK)
	_put(img, r, 7, 12, BLACK)
	_put(img, r, 8, 12, BLACK)


static func _plate(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var w := r.size.x
	var h := r.size.y
	_fill(img, r, 0, 0, w, h, STEEL_DARK)
	_fill(img, r, 0, 0, w, 1, STEEL_MID)
	_fill(img, r, 0, h - 1, w, 1, BLACK)
	for p in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		_put(img, r, p.x, p.y, STEEL_LIGHT)
	for row in [4, 7, 10]:
		var x := 4
		var end := 4 + rng.randi_range(10, w - 9)
		while x < end:
			var run := rng.randi_range(2, 5)
			_fill(img, r, x, row, mini(run, end - x), 1, STEEL_MID.lerp(STEEL_LIGHT, 0.5))
			x += run + 1


static func _pipe(img: Image, r: Rect2i) -> void:
	var w := r.size.x
	for xx in w:
		_put(img, r, xx, 1, STEEL_LIGHT)
		_put(img, r, xx, 2, STEEL_MID)
		_put(img, r, xx, 3, STEEL_MID)
		_put(img, r, xx, 4, STEEL_DARK)
		_put(img, r, xx, 5, STEEL_DARK)
		_put(img, r, xx, 6, BLACK)
	var bx := 14
	while bx + 3 <= w:
		_fill(img, r, bx, 0, 3, 8, STEEL_DARK)
		_put(img, r, bx + 1, 3, STEEL_LIGHT)
		bx += 32


static func _hash(x: int, y: int, salt: int) -> float:
	var hh := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	hh = (hh ^ (hh >> 13)) * 1274126177
	return float(hh & 0xffff) / 65535.0


static func _blob(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var salt := rng.randi() & 0xffff
	var w := r.size.x
	var h := r.size.y
	for yy in h:
		for xx in w:
			var nx := (xx - w * 0.5) / (w * 0.5)
			var ny := (yy - h * 0.5) / (h * 0.5)
			var fall := 1.0 - sqrt(nx * nx + ny * ny)
			var cell := _hash(xx / 3, yy / 3, salt) * 0.6 + _hash(xx, yy, salt + 5) * 0.4
			if fall + (cell - 0.5) * 0.9 > 0.25:
				_put(img, r, xx, yy, RUST if _hash(xx / 2, yy / 2, salt + 9) > 0.45 else RUST_DARK)


static func _scuff(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var w := r.size.x
	var h := r.size.y
	for strand in 3:
		var yy := rng.randf_range(1.0, h - 2.0)
		var slope := rng.randf_range(-0.25, 0.25)
		var x0 := rng.randi_range(0, w / 3)
		for xx in range(x0, w - rng.randi_range(0, w / 3)):
			yy += slope
			if rng.randf() < 0.82:
				_put(img, r, xx, int(round(yy)), GRIME)


static func _streak(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var w := r.size.x
	var h := r.size.y
	for xx in w:
		var run_len := rng.randi_range(h / 3, h)
		var salt := rng.randi() & 0xffff
		for yy in run_len:
			var t := 1.0 - float(yy) / float(run_len)
			if _hash(xx, yy, salt) < pow(t, 0.9) * 0.95:
				_put(img, r, xx, yy, RUST_DARK if _hash(xx, yy, salt + 3) < 0.25 else GRIME)


static func _text(img: Image, r: Rect2i, text: String, ink: Color, rng: RandomNumberGenerator) -> void:
	var x := 0
	for ch in text:
		if ch != " " and FONT.has(String(ch)):
			var rows: PackedStringArray = String(FONT[String(ch)]).split("|")
			for ry in 5:
				for rx in 3:
					if rows[ry][rx] == "#":
						for sy in 2:
							for sx in 2:
								if rng.randf() > 0.12:
									_put(img, r, x + rx * 2 + sx, ry * 2 + sy, ink)
		x += 8
