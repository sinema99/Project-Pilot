@tool
class_name HoloDisplay
extends Control

# What a cockpit hologram panel shows, drawn in 2D into its SubViewport: the user's green reference
# (translucent dark-green fill, bright mint outline with a soft glow, chamfered corners, thin-line
# UI). Live re-entry readouts, all from the shot time. No real words except WARNING; the rest is
# numbers and pseudo-text blocks. See docs/specs/cutscene-cockpit.md, "Atmosphere pass".

enum Kind { HORIZON, HEAT, RADAR, LOG, WARNING, ROUTE }

const MINT := Color(0.5, 1.0, 0.72)
const FILL := Color(0.01, 0.13, 0.08, 0.72)
const RED := Color(1.0, 0.2, 0.14)
## The WARNING panel's glass and its bright red line.
const RED_FILL := Color(0.16, 0.01, 0.01, 0.72)
const RED_LINE := Color(1.0, 0.3, 0.22)

## Florida and the coast north of it, (lon, lat): the radar's landmass (shot 1's target).
const FLORIDA: Array[Vector2] = [
	Vector2(-81.4, 33.0), Vector2(-81.4, 30.7), Vector2(-81.0, 29.5), Vector2(-80.6, 28.5),
	Vector2(-80.1, 27.0), Vector2(-80.0, 26.0), Vector2(-80.2, 25.3), Vector2(-80.6, 25.1),
	Vector2(-81.2, 25.2), Vector2(-81.7, 25.9), Vector2(-82.1, 26.7), Vector2(-82.7, 27.5),
	Vector2(-82.8, 28.2), Vector2(-82.6, 29.0), Vector2(-83.1, 29.2), Vector2(-83.7, 29.9),
	Vector2(-84.3, 30.0), Vector2(-85.3, 29.7), Vector2(-86.5, 30.4), Vector2(-87.5, 30.3),
	Vector2(-88.5, 30.4), Vector2(-88.5, 33.0),
]
const RADAR_CENTER := Vector2(-82.0, 28.3)
const RADAR_SPAN := 4.5
const TARGET := Vector2(-82.5, 27.9)
## The storm shot's route panel (docs/specs/cutscene-cockpit-storm.md): its two buttons' centres and
## size, as fractions of the drawing (x right, y down, as he sees it).
const ROUTE_BUTTONS: Array[Vector2] = [Vector2(0.73, 0.43), Vector2(0.73, 0.73)]
const ROUTE_BUTTON_SIZE := Vector2(0.36, 0.22)

@export var kind := Kind.HORIZON

## Shot time, seconds.
var t := 0.0
## 1.0 on a jolt, fading: the red warnings.
var flash := 0.0
## The horizon's extra roll and pitch from the shake, radians.
var roll := 0.0
var pitch := 0.0
## Shot time the ship answers the push (speed climbs, altitude drops faster). INF = never.
var surge_from := INF
## The route panel: how many buttons he has tapped, and the confirm flash on the last.
var route_taps := 0
var route_confirm := 0.0

var _u := 1.0


func _draw() -> void:
	_u = minf(size.x, size.y) / 100.0
	_frame(RED_LINE if kind == Kind.WARNING else MINT, RED_FILL if kind == Kind.WARNING else FILL)
	match kind:
		Kind.HORIZON: _draw_horizon()
		Kind.HEAT: _draw_heat()
		Kind.RADAR: _draw_radar()
		Kind.LOG: _draw_log()
		Kind.WARNING: _draw_warning()
		Kind.ROUTE: _draw_route()


## The readouts at shot time t. Pure, for tests.
static func altitude_at(time: float, surge := INF) -> float:
	return 98400.0 - time * 1850.0 - maxf(time - surge, 0.0) * 2800.0


## Bleeds off through the descent, then climbs once the sticks go forward.
static func speed_at(time: float, surge := INF) -> float:
	return 7.42 - time * 0.11 + maxf(time - surge, 0.0) * 0.6


static func heat_at(time: float, flash_: float) -> float:
	return clampf(0.5 + time * 0.05 + flash_ * 0.3, 0.0, 1.0)


# ------------------------------------------------------------------ panels

func _draw_horizon() -> void:
	var h := size.y
	var c := Vector2(h * 0.55, h * 0.56)
	var r := h * 0.34
	_header(Vector2(_u * 12.0, _u * 6.0), 4)
	_ring(c, r, MINT, 1.2)
	# The ball: horizon and a pitch ladder, banked by the shake plus a slow drift, nose down.
	var bank := roll + 0.06 * sin(t * 0.7)
	var nose := clampf(-0.15 + pitch, -0.8, 0.8)
	var along := Vector2(cos(bank), sin(bank))
	var across := Vector2(-sin(bank), cos(bank))
	for i in range(-3, 4):
		var d := (nose + i * 0.2) * r
		if absf(d) >= r * 0.98:
			continue
		var half := sqrt(r * r - d * d) if i == 0 else r * 0.22
		var mid := c + across * -d
		_line(mid - along * half, mid + along * half, MINT, 1.6 if i == 0 else 0.7)
	# Fixed reticle.
	var w := r * 0.28
	_polyline([c + Vector2(-w, 0), c + Vector2(-w * 0.4, 0), c + Vector2(0, w * 0.3),
			c + Vector2(w * 0.4, 0), c + Vector2(w, 0)], MINT, 1.2)
	# Bank scale over the top with a pointer.
	for k in range(-4, 5):
		var a := -PI * 0.5 + k * deg_to_rad(15.0)
		var dir := Vector2(cos(a), sin(a))
		_line(c + dir * (r + _u * 2.0), c + dir * (r + _u * (5.0 if k % 2 == 0 else 3.5)), MINT, 0.7)
	var pa := -PI * 0.5 + bank
	var pd := Vector2(cos(pa), sin(pa))
	_polyline([c + pd * (r - _u * 4.0) + pd.orthogonal() * _u * 2.0, c + pd * (r - _u * 0.5),
			c + pd * (r - _u * 4.0) - pd.orthogonal() * _u * 2.0], MINT, 1.0)

	# Altitude and speed counting down, each under a pseudo label.
	var x := h * 1.0
	_blocks(Vector2(x, h * 0.2), 3, 11.0, MINT * Color(1, 1, 1, 0.5))
	_number(Vector2(x, h * 0.36), "%06d" % int(altitude_at(t, surge_from)), 10.5, MINT)
	_blocks(Vector2(x, h * 0.48), 2, 17.0, MINT * Color(1, 1, 1, 0.5))
	_number(Vector2(x, h * 0.64), "%.2f" % speed_at(t, surge_from), 10.5, MINT)
	# Descent bar.
	var bar := Rect2(size.x - _u * 10.0, h * 0.18, _u * 3.5, h * 0.62)
	_rect_outline(bar, MINT, 0.8)
	var fill := 0.55 + 0.1 * sin(t * 3.1) + 0.2 * flash - 0.35 * clampf((t - surge_from) / 0.4, 0.0, 1.0)
	draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * (1.0 - fill)), Vector2(bar.size.x, bar.size.y * fill)),
			MINT * Color(1, 1, 1, 0.55))
	# Heading tape scrolling under the ball.
	var y := h * 0.94
	_line(Vector2(c.x - r, y), Vector2(c.x + r, y), MINT, 0.6)
	var step := _u * 6.0
	var off := fposmod(t * _u * 9.0, step)
	var tx := c.x - r + off
	var n := 0
	while tx < c.x + r:
		_line(Vector2(tx, y), Vector2(tx, y - _u * (3.0 if n % 3 == 0 else 1.5)), MINT, 0.6)
		tx += step
		n += 1


func _draw_heat() -> void:
	_header(Vector2(_u * 12.0, _u * 6.0), 3)
	var c := Vector2(size.x * 0.5, size.y * 0.52)
	var r := size.x * 0.31
	var heat := heat_at(t, flash)
	var segs := 16
	var a0 := deg_to_rad(150.0)
	var span := deg_to_rad(240.0)
	var lit_color := MINT.lerp(RED, clampf(flash * 1.3, 0.0, 1.0))
	for i in segs:
		var s0 := a0 + span * float(i) / segs + 0.025
		var s1 := a0 + span * float(i + 1) / segs - 0.025
		var lit := float(i) < heat * segs
		var col := lit_color if lit else MINT * Color(1, 1, 1, 0.18)
		draw_arc(c, r, s0, s1, 6, col * Color(1, 1, 1, 0.25), _u * 9.0, true)
		draw_arc(c, r, s0, s1, 6, col, _u * 5.0, true)
	draw_arc(c, r * 0.72, a0, a0 + span, 48, MINT * Color(1, 1, 1, 0.6), _u * 0.6, true)
	var na := a0 + span * heat
	_line(c, c + Vector2(cos(na), sin(na)) * r * 0.68, lit_color, 1.2)
	_number(c + Vector2(-_u * 14.0, _u * 16.0), "%d" % int(1600.0 + 900.0 * heat), 11.0, lit_color)
	# The WARNING block: dim and empty until a jolt, then blinking red.
	var box := Rect2(_u * 14.0, size.y - _u * 20.0, size.x - _u * 28.0, _u * 12.0)
	if flash > 0.03:
		var blink := 1.0 if fmod(t * 8.0, 1.0) < 0.65 else 0.45
		var a := clampf(flash * 1.5, 0.0, 1.0) * blink
		draw_rect(box, RED * Color(1, 1, 1, 0.35 * a))
		_rect_outline(box, RED * Color(1, 1, 1, a), 1.0)
		_number(box.position + Vector2(_u * 6.0, _u * 9.5), "WARNING", 8.5, Color(1.0, 0.75, 0.7, a))
	else:
		_rect_outline(box, MINT * Color(1, 1, 1, 0.35), 0.6)
		_blocks(box.position + Vector2(_u * 4.0, _u * 4.0), 3, 21.0, MINT * Color(1, 1, 1, 0.3))


func _draw_radar() -> void:
	_header(Vector2(_u * 12.0, _u * 6.0), 2)
	var c := size * 0.5 + Vector2(0, _u * 4.0)
	var r := minf(size.x, size.y) * 0.38
	# Land, clipped to the scope.
	var land := PackedVector2Array()
	for p in FLORIDA:
		land.append(_geo(p, c, r))
	var scope := PackedVector2Array()
	for i in 48:
		scope.append(c + Vector2.from_angle(TAU * i / 48.0) * r)
	for piece in Geometry2D.intersect_polygons(land, scope):
		draw_colored_polygon(piece, MINT * Color(1, 1, 1, 0.14))
		var closed := piece.duplicate()
		closed.append(piece[0])
		draw_polyline(closed, MINT * Color(1, 1, 1, 0.75), _u * 0.6, true)
	# Rings, crosshair, bezel ticks.
	for k in 3:
		_ring(c, r * (1.0 - k * 0.33), MINT * Color(1, 1, 1, 1.0 if k == 0 else 0.4), 1.0 if k == 0 else 0.5)
	_line(c - Vector2(r, 0), c + Vector2(r, 0), MINT * Color(1, 1, 1, 0.35), 0.4)
	_line(c - Vector2(0, r), c + Vector2(0, r), MINT * Color(1, 1, 1, 0.35), 0.4)
	for k in 36:
		var d := Vector2.from_angle(TAU * k / 36.0)
		_line(c + d * r, c + d * (r + _u * (3.0 if k % 3 == 0 else 1.5)), MINT, 0.5)
	# The sweep and its fading wake.
	var a := t * 2.2
	var wedge := PackedVector2Array([c])
	for i in 9:
		wedge.append(c + Vector2.from_angle(a - 0.7 * i / 8.0) * r)
	draw_colored_polygon(wedge, MINT * Color(1, 1, 1, 0.12))
	_line(c, c + Vector2.from_angle(a) * r, MINT, 1.0)
	# The landing target, pinging.
	var tp := _geo(TARGET, c, r)
	var ping := fmod(t, 1.0)
	_ring(tp, _u * (1.5 + ping * 8.0), MINT * Color(1, 1, 1, 1.0 - ping), 0.6)
	draw_circle(tp, _u * 1.4, MINT)


func _draw_log() -> void:
	var pad := _u * 8.0
	var rows := 6
	var row_h := (size.y - pad * 2.0) / rows
	var scroll := t * 3.0
	var first := int(floor(scroll))
	var x1 := size.x * 0.56
	for k in range(first, first + rows + 1):
		var y := pad + (k - scroll) * row_h + row_h * 0.75
		if y < pad + row_h * 0.6 or y > size.y - pad:
			continue
		_number(Vector2(pad + _u * 6.0, y), "%05d" % ((k * 7919) % 100000), 6.5, MINT * Color(1, 1, 1, 0.8))
		var x := pad + _u * 30.0
		var i := 0
		while x < x1 - _u * 6.0 and i < 6:
			var bw := _u * (4.0 + 14.0 * _hash(k * 13.0 + i))
			bw = minf(bw, x1 - _u * 6.0 - x)
			draw_rect(Rect2(x, y - _u * 4.0, bw, _u * 3.0), MINT * Color(1, 1, 1, 0.55))
			x += bw + _u * 3.0
			i += 1
	_line(Vector2(x1, pad), Vector2(x1, size.y - pad), MINT * Color(1, 1, 1, 0.5), 0.5)
	# Bars that jitter, harder on a jolt.
	var bars := 12
	var bx := x1 + _u * 8.0
	var bw2 := (size.x - pad - _u * 6.0 - bx) / bars
	var base := size.y - pad - _u * 2.0
	var top := pad + _u * 4.0
	_line(Vector2(bx, base), Vector2(size.x - pad - _u * 6.0, base), MINT, 0.7)
	for i in bars:
		var v := 0.35 + 0.25 * sin(t * (1.3 + i * 0.37) + i) + 0.2 * _hash(floor(t * 12.0) + i * 3.0) * (0.3 + flash)
		v = clampf(v, 0.05, 1.0)
		var hgt := (base - top) * v
		var rect := Rect2(bx + i * bw2 + bw2 * 0.15, base - hgt, bw2 * 0.7, hgt)
		draw_rect(rect, MINT * Color(1, 1, 1, 0.5))
		_rect_outline(rect, MINT, 0.5)


# The big-jolt warning: a blinking hazard triangle, WARNING, rows of pseudo-text and a hazard-stripe
# strip along the bottom. All red.
func _draw_warning() -> void:
	var w := size.x
	var h := size.y
	_header(Vector2(_u * 12.0, _u * 6.0), 3, RED_LINE)
	# Triangle on the left, about 3 blinks a second.
	var blink := 1.0 if fmod(t * 3.0, 1.0) < 0.62 else 0.3
	var col := RED_LINE * Color(1, 1, 1, blink)
	var c := Vector2(h * 0.5, h * 0.48)
	var r := h * 0.3
	var tri := [c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.65), c + Vector2(-r * 0.95, r * 0.65)]
	draw_colored_polygon(PackedVector2Array(tri), RED * Color(1, 1, 1, 0.3 * blink))
	_polyline(tri + [tri[0]], col, 1.8)
	_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.2), col, 2.4)
	draw_circle(c + Vector2(0, r * 0.42), _u * 1.8, col)
	# WARNING and the text rows to its right.
	var x := h * 0.92
	# Shrunk to fit inside the frame's right edge (it ran the G off the panel).
	_number(Vector2(x, h * 0.4), "WARNING", _fit_size("WARNING", 13.0, w - x - _u * 10.0),
			Color(1.0, 0.72, 0.66))
	_blocks(Vector2(x, h * 0.52), 4, 31.0, RED_LINE * Color(1, 1, 1, 0.6))
	_blocks(Vector2(x, h * 0.6), 3, 47.0, RED_LINE * Color(1, 1, 1, 0.45))
	_blocks(Vector2(x, h * 0.68), 4, 59.0, RED_LINE * Color(1, 1, 1, 0.45))
	# Hazard stripes, marching slowly.
	var band := Rect2(_u * 6.0, h - _u * 15.0, w - _u * 20.0, _u * 6.0)
	_rect_outline(band, RED_LINE, 0.6)
	var step := _u * 7.0
	var sx := band.position.x - step + fmod(t * _u * 10.0, step)
	while sx < band.end.x:
		var quad := PackedVector2Array([Vector2(sx, band.end.y), Vector2(sx + step * 0.5, band.position.y),
				Vector2(sx + step, band.position.y), Vector2(sx + step * 0.5, band.end.y)])
		var clipped := Geometry2D.intersect_polygons(quad, PackedVector2Array([band.position,
				Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]))
		for piece in clipped:
			draw_colored_polygon(piece, RED_LINE * Color(1, 1, 1, 0.75))
		sx += step


# The storm shot's route prompt: a small radar with a storm blob and the ship's route on the left,
# two big rounded buttons stacked on the right. The first tap bends the route round the storm; the
# second confirms (the whole panel flashes) before it folds away.
func _draw_route() -> void:
	var w := size.x
	var h := size.y
	_header(Vector2(_u * 12.0, _u * 6.0), 3)
	# The radar.
	var box := Rect2(w * 0.08, h * 0.24, w * 0.4, h * 0.64)
	_rect_outline(box, MINT * Color(1, 1, 1, 0.6), 0.6)
	var c := box.get_center()
	for k in 2:
		_ring(c, box.size.x * (0.42 - k * 0.18), MINT * Color(1, 1, 1, 0.3), 0.4)
	# The storm: a lumpy blob, slowly churning, hatched in.
	var blob := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var rr := box.size.x * (0.2 + 0.035 * sin(a * 3.0 + t * 1.3) + 0.02 * sin(a * 5.0 - t * 0.9))
		blob.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(blob, MINT * Color(1, 1, 1, 0.22))
	var closed := blob.duplicate()
	closed.append(blob[0])
	_polyline(closed, MINT * Color(1, 1, 1, 0.8), 0.6)
	# Ship at the bottom, target at the top; straight through the storm, then bent round it.
	var ship := Vector2(c.x, box.end.y - _u * 6.0)
	var target := Vector2(c.x, box.position.y + _u * 6.0)
	var route: Array = [ship, target]
	if route_taps >= 1:
		route = [ship, ship + Vector2(box.size.x * 0.34, -box.size.y * 0.25),
				target + Vector2(box.size.x * 0.34, box.size.y * 0.25), target]
	_dashed(route, MINT, 1.0)
	_polyline([ship + Vector2(-_u * 3.0, _u * 2.0), ship + Vector2(0, -_u * 3.0), ship + Vector2(_u * 3.0, _u * 2.0),
			ship + Vector2(-_u * 3.0, _u * 2.0)], MINT, 0.9)
	draw_circle(target, _u * 1.6, MINT)
	# The buttons.
	for i in ROUTE_BUTTONS.size():
		var bs := ROUTE_BUTTON_SIZE * size
		var r := Rect2(ROUTE_BUTTONS[i] * size - bs * 0.5, bs)
		var lit := route_taps > i
		var shape := _rounded(r, _u * 4.0)
		draw_colored_polygon(shape, MINT * Color(1, 1, 1, 0.75 if lit else 0.1))
		var ring := shape.duplicate()
		ring.append(shape[0])
		_polyline(ring, MINT, 1.2 if lit else 0.8)
		_blocks(r.position + Vector2(_u * 5.0, bs.y * 0.42), 2, 71.0 + i * 13.0,
				FILL * Color(1, 1, 1, 1.4) if lit else MINT * Color(1, 1, 1, 0.6))
	if route_confirm > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), MINT * Color(1, 1, 1, 0.45 * route_confirm))


# ------------------------------------------------------------------ pieces

func _dashed(pts: Array, col: Color, w: float) -> void:
	var dash := _u * 3.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var n := int(a.distance_to(b) / dash)
		for k in range(0, n, 2):
			_line(a.lerp(b, float(k) / n), a.lerp(b, float(mini(k + 1, n)) / n), col, w)


# A rectangle with rounded corners, as a polygon.
func _rounded(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - radius, r.position.y + radius), Vector2(r.end.x - radius, r.end.y - radius),
			Vector2(r.position.x + radius, r.end.y - radius), Vector2(r.position.x + radius, r.position.y + radius)]
	for k in 4:
		for i in 5:
			var a := -PI * 0.5 + PI * 0.5 * k + PI * 0.5 * i / 4.0
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * radius)
	return pts


# The panel: chamfered at top-left and bottom-right, tinted glass, glowing edge.
func _frame(line := MINT, fill := FILL) -> void:
	var c := _u * 8.0
	var w := size.x
	var h := size.y
	var e := _u * 1.5
	var pts := PackedVector2Array([Vector2(c + e, e), Vector2(w - e, e), Vector2(w - e, h - c - e),
			Vector2(w - c - e, h - e), Vector2(e, h - e), Vector2(e, c + e)])
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	_polyline(closed, line, 1.3)
	# A tab on the top edge and corner brackets, from the reference's framing.
	_line(Vector2(w * 0.62, e + _u * 2.0), Vector2(w - c, e + _u * 2.0), line * Color(1, 1, 1, 0.6), 0.6)


func _header(at: Vector2, count: int, col := MINT) -> void:
	_blocks(at, count, 5.0, col * Color(1, 1, 1, 0.7))


# A row of pseudo-text blocks.
func _blocks(at: Vector2, count: int, noise_seed: float, col: Color) -> void:
	var x := at.x
	for i in count:
		var bw := _u * (5.0 + 10.0 * _hash(noise_seed + i * 1.7))
		draw_rect(Rect2(x, at.y, bw, _u * 2.6), col)
		x += bw + _u * 2.5


# The largest size (in _u, up to size_u) at which text is no wider than max_width.
func _fit_size(text: String, size_u: float, max_width: float) -> float:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_u * size_u)).x
	return size_u * minf(1.0, max_width / width) if width > 0.0 else size_u


func _number(at: Vector2, text: String, size_u: float, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(_u * size_u)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col * Color(1, 1, 1, 0.3))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col * Color(1, 1, 1, 0.2), _u * w * 3.5, true)
	draw_line(a, b, col, _u * w, true)


func _polyline(pts: Array, col: Color, w: float) -> void:
	var p := PackedVector2Array(pts)
	draw_polyline(p, col * Color(1, 1, 1, 0.2), _u * w * 3.5, true)
	draw_polyline(p, col, _u * w, true)


func _ring(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_arc(c, r, 0.0, TAU, 64, col * Color(1, 1, 1, 0.2), _u * w * 3.5, true)
	draw_arc(c, r, 0.0, TAU, 64, col, _u * w, true)


func _rect_outline(r: Rect2, col: Color, w: float) -> void:
	_polyline([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position], col, w)


func _geo(lonlat: Vector2, c: Vector2, r: float) -> Vector2:
	var d := (lonlat - RADAR_CENTER) / RADAR_SPAN
	return c + Vector2(d.x * 0.88, -d.y) * r


static func _hash(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)
