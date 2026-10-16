@tool
class_name HabitatParts
extends Habitat

# The habitat part library: every building block of the habitat (scripts/habitat_part.gd) laid out
# on a flat plane, in rows by category, each with a name label. Grab one to copy it into a level,
# or drag its scene out of scenes/habitat_parts/. See docs/specs/habitat-parts.md.
#
# The parts are real, owned child nodes (instances of scenes/habitat_parts/*.tscn), so they show in
# the scene tree and can be moved, copied, deleted. What this script generates, with no owner, is
# the floor (with a pit for the water tile), the category headings and the name labels. A part you
# add later gets its label on the next Rebuild.

const GROUND_COL := Color(0.34, 0.36, 0.34)
const MARGIN := 30.0


func _build() -> void:
	if not is_inside_tree():
		return
	_clear()
	_mats.clear()
	_hull = StaticBody3D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)

	var lay := HabitatPart.layout()
	var rect := (lay.rect as Rect2).grow(MARGIN)
	_floor(rect)
	for h: Array in lay.heads:
		var l := _label(h[0] as String, 0.09, 110)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.modulate = Color(0.75, 0.95, 0.7)
		l.position = h[1]
		_vis.add_child(l)
	for c in get_children():
		var part := c as HabitatPart
		if part == null or part.has_node("PartLabel"):
			continue
		var entry := HabitatPart.entry_for(part.kind)
		if entry.is_empty():
			continue
		var text := part.kind + ("" if entry[6] else "\n(no collision)")
		var l := _label(text, 0.03, 48)
		l.name = "PartLabel"
		l.position = Vector3(entry[4], 3.0, float(entry[5]) + float(entry[3]) * 0.5 + 3.0)
		part.add_child(l)

	_ambient()
	var probe := get_node("Ambient") as ReflectionProbe
	probe.position = Vector3(rect.get_center().x, 70.0, rect.get_center().y)
	probe.size = Vector3(rect.size.x, 200.0, rect.size.y)


## The flat floor, top just under y = 0 so a part's own ground tile reads against it. A square
## hole is left under the water tile so its lake bed can sit 8 m down.
func _floor(rect: Rect2) -> void:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	var top := -0.05
	var bottom := -14.0
	var pit := Rect2()
	for c in get_children():
		var part := c as HabitatPart
		if part and part.kind == "water_tile":
			pit = Rect2(part.position.x - 12.0, part.position.z - 12.0, 24.0, 24.0)
	if pit.size == Vector2.ZERO:
		_slab(x0, x1, z0, z1, top, bottom, GROUND_COL)
		return
	_slab(x0, pit.position.x, z0, z1, top, bottom, GROUND_COL)
	_slab(pit.end.x, x1, z0, z1, top, bottom, GROUND_COL)
	_slab(pit.position.x, pit.end.x, z0, pit.position.y, top, bottom, GROUND_COL)
	_slab(pit.position.x, pit.end.x, pit.end.y, z1, top, bottom, GROUND_COL)


func _label(text: String, pixel: float, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = pixel
	l.font_size = size
	l.outline_size = 14
	l.modulate = Color(1.0, 0.95, 0.6)
	l.outline_modulate = Color(0.0, 0.0, 0.0)
	return l
