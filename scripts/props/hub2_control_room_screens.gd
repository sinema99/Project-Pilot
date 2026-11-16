class_name Hub2ControlRoomScreens
extends RefCounted

# The drawn low-res images on the crane control room's screens and yard board
# (docs/specs/hub2-control-room.md): drawn in code with the 3x5 pixel font, like hub2_decal_atlas.gd.
# Phosphor green / amber on near black; shaders/hub2_screen.gdshader adds scanlines + flicker (and the
# blink of the alarm screen).

const GREEN := Color(0.30, 1.0, 0.42)
const AMBER := Color(1.0, 0.66, 0.18)
const RED := Color(1.0, 0.16, 0.10)
const CYAN := Color(0.35, 0.85, 1.0)
const DIM := Color(0.10, 0.28, 0.14)
const BG := Color(0.02, 0.05, 0.04)

## The yard (room B) in world metres, and the two bridge cranes drawn on every yard map.
const YARD_X := Vector2(-161.0, -62.0)
const YARD_Z := Vector2(-147.0, 42.0)
## [centre x, span, bridge z] per crane (tools/gen_hub2_dressing.gd).
const CRANES := [[-134.0, 44.0, -70.5], [-87.5, 26.0, -30.5]]

static var _cache: Dictionary = {}


static func image(kind: String) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	var img: Image
	match kind:
		"crane1":
			img = _crane(1)
		"crane2":
			img = _crane(2)
		"yard":
			img = _yard(64, 48, false)
		"board":
			img = _yard(160, 84, true)
		"power":
			img = _power()
		"alarm":
			img = _alarm()
		"text":
			img = _text_page()
		_:
			img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex


# -- drawing helpers -------------------------------------------------------------------------------------

static func _canvas(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func _frame(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	_rect(img, x, y, w, 1, c)
	_rect(img, x, y + h - 1, w, 1, c)
	_rect(img, x, y, 1, h, c)
	_rect(img, x + w - 1, y, 1, h, c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var guard := 0
	while guard < 4096:
		guard += 1
		_rect(img, x0, y0, 1, 1, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


static func _text(img: Image, x: int, y: int, t: String, c: Color) -> void:
	var cx := x
	for ch in t.to_upper():
		var g: Array = Hub2PieceBuild.FONT.get(ch, Hub2PieceBuild.FONT[" "])
		for row in 5:
			var line: String = g[row]
			for col in 3:
				if line[col] == "#":
					_rect(img, cx + col, y + row, 1, 1, c)
		cx += 4


static func _bar(img: Image, x: int, y: int, w: int, frac: float, c: Color) -> void:
	_frame(img, x, y, w, 5, c.darkened(0.4))
	_rect(img, x + 1, y + 1, int((w - 2) * clampf(frac, 0.0, 1.0)), 3, c)


# -- screens ------------------------------------------------------------------------------------------------

## Yard plan: containers as blocks, the two runways and bridges, the control room marked. `big` adds labels.
static func _yard(w: int, h: int, big: bool) -> Image:
	var img := _canvas(w, h)
	var top := 8 if big else 0
	var ph := h - top
	_frame(img, 0, top, w, ph, DIM)
	# Image u runs along the yard's z, v along its x.
	var fu := func(z: float) -> int: return int((z - YARD_Z.x) / (YARD_Z.y - YARD_Z.x) * (w - 2)) + 1
	var fv := func(x: float) -> int: return top + int((x - YARD_X.x) / (YARD_X.y - YARD_X.x) * (ph - 2)) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for c: Array in CRANES:
		var cx: float = c[0]
		var sp: float = c[1]
		# Container blocks under the crane: 2 columns of 3 Z blocks.
		for bx in [-1.0, 1.0]:
			for zb in [-140.0, -102.0, -64.0]:
				var v0: int = fv.call(cx + bx * 8.6 - 4.2)
				var v1: int = fv.call(cx + bx * 8.6 + 4.2)
				var u0: int = fu.call(zb)
				var u1: int = fu.call(zb + 31.0)
				var tone := AMBER if rng.randf() < 0.18 else GREEN.darkened(0.45)
				_rect(img, u0, v0, maxi(u1 - u0, 1), maxi(v1 - v0, 1), tone)
		# Runways, then the bridge across them with its trolley.
		for side in [-1.0, 1.0]:
			var v: int = fv.call(cx + side * sp * 0.5)
			_line(img, 1, v, w - 2, v, CYAN.darkened(0.2))
		var bu: int = fu.call(c[2])
		var v_a: int = fv.call(cx - sp * 0.5)
		var v_b: int = fv.call(cx + sp * 0.5)
		_line(img, bu, v_a, bu, v_b, RED if big else AMBER)
		_rect(img, bu - 1, (v_a + v_b) / 2 - 1, 3, 3, Color.WHITE)
	# The control room: east wall, x -72..-62, z -83..-22.
	var r0u: int = fu.call(-83.0)
	var r1u: int = fu.call(-22.0)
	var r0v: int = fv.call(-72.0)
	var r1v: int = fv.call(-62.0)
	_frame(img, r0u, r0v, maxi(r1u - r0u, 2), maxi(r1v - r0v, 2), Color.WHITE)
	if big:
		_text(img, 2, 1, "YARD B  CRANE POSITIONS", GREEN)
		_text(img, 4, top + 4, "CR1", CYAN)
		_text(img, 4, int(fv.call(-134.0)) - 8, "CR0", CYAN)
		_text(img, r0u, r1v + 3, "CTRL", Color.WHITE)
		_text(img, w - 44, h - 7, "RUNWAY LOCKED", AMBER)
	else:
		_text(img, 2, 2, "YARD", GREEN)
	return img


static func _crane(n: int) -> Image:
	var img := _canvas(64, 48)
	_frame(img, 0, 0, 64, 48, DIM)
	_text(img, 3, 3, "CRANE %d" % n, GREEN)
	_text(img, 40, 3, "E-PWR", AMBER)
	var rows := ["LOAD", "TROL", "HOOK", "SPAN"]
	var vals := [0.0, 0.42, 0.7, 0.33] if n == 1 else [0.0, 0.8, 0.25, 0.6]
	for i in 4:
		_text(img, 3, 12 + i * 8, rows[i], GREEN.darkened(0.2))
		_bar(img, 22, 11 + i * 8, 38, vals[i], AMBER if i == 0 else GREEN)
	_text(img, 3, 42, "STATUS", GREEN.darkened(0.2))
	_text(img, 27, 42, "LOCKED" if n == 1 else "FAULT", AMBER if n == 1 else RED)
	return img


static func _power() -> Image:
	var img := _canvas(64, 48)
	_frame(img, 0, 0, 64, 48, DIM)
	_text(img, 3, 3, "EMERG PWR", AMBER)
	var names := ["BATT", "GEN", "BUS A", "BUS B", "COMMS"]
	var vals := [0.41, 0.0, 0.0, 0.62, 0.9]
	for i in 5:
		_text(img, 3, 11 + i * 7, names[i], GREEN.darkened(0.2))
		_bar(img, 28, 10 + i * 7, 32, vals[i], RED if vals[i] <= 0.0 else (AMBER if vals[i] < 0.5 else GREEN))
	_text(img, 3, 43, "GRID OFFLINE", RED)
	return img


static func _alarm() -> Image:
	var img := _canvas(64, 48)
	_rect(img, 0, 0, 64, 48, Color(0.35, 0.02, 0.01))
	_frame(img, 1, 1, 62, 46, RED)
	_frame(img, 3, 3, 58, 42, RED.darkened(0.3))
	_text(img, 10, 10, "WARNING", RED.lightened(0.3))
	_text(img, 6, 20, "LOAD FAULT", Color(1.0, 0.85, 0.7))
	_text(img, 6, 28, "CRANE 2 ESTOP", Color(1.0, 0.85, 0.7))
	_text(img, 6, 37, "ACK  ---", RED.lightened(0.3))
	return img


static func _text_page() -> Image:
	var img := _canvas(64, 48)
	_frame(img, 0, 0, 64, 48, DIM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var words := ["LOG", "ERR", "CRANE", "LOCK", "BAY", "ARM", "TEST", "OK", "NO", "PWR", "DOOR", "SEQ"]
	for i in 7:
		var y := 4 + i * 6
		var line := ""
		for k in rng.randi_range(2, 4):
			line += "%s %d " % [words[rng.randi() % words.size()], rng.randi_range(0, 99)]
		_text(img, 3, y, line.substr(0, 15), GREEN if i % 4 != 2 else AMBER)
	_rect(img, 3, 45, 3, 2, GREEN)
	return img
