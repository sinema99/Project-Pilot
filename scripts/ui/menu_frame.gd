extends Control

# The window's fill and rim: a dark panel with a 45 degree notch cut from the top-left and
# bottom-right corners. Drawn rather than a StyleBox because StyleBoxFlat cannot cut a corner.
# See docs/specs/menu-refresh.md, "The look".

@export var fill := Color(0.043, 0.071, 0.086, 0.88)
@export var rim := Color(0.251, 0.949, 0.902, 0.4)
@export var notch := 14.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

## The outline, clockwise from the end of the top-left cut. Public so a test can check the cuts.
func outline(rect_size: Vector2) -> PackedVector2Array:
	var n := notch
	return PackedVector2Array([
		Vector2(n, 0.0), Vector2(rect_size.x, 0.0),
		Vector2(rect_size.x, rect_size.y - n), Vector2(rect_size.x - n, rect_size.y),
		Vector2(0.0, rect_size.y), Vector2(0.0, n),
	])

func _draw() -> void:
	var points := outline(size)
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, rim, 1.0)
