@tool
class_name BlockoutBox
extends StaticBody3D

# One box of map blockout: a solid you can select, duplicate, move and resize in the editor,
# built to be measured against the jump grid ruler standing next to it.
# See docs/specs/blockout-boxes.md.
#
# The ruler in scripts/jump_grid.gd is generated and untouchable on purpose - every lane on it
# is a claim about pilot9's numbers, and a lane somebody dragged is a lane that lies. This is
# the other half: geometry that is YOURS, in the same units, in a colour that says so.
#
# ONE property is the box. `size` drives the BoxMesh and the BoxShape3D together and they are
# never given different values - the thing you look at and the thing you land on cannot be
# allowed to drift apart, which is the invariant tests/test_pilot9_jump_grid_platform.gd reads
# the ruler's colliders for.
#
# The node's `scale` stays exactly 1, always. shaders/metre_grid.gdshader is a world-space
# triplanar grid: a scaled node's normals come out non-unit and its metre lines stop being
# metres, so a box resized by scaling would quietly stop counting itself. The scale gizmo is
# still allowed - see _bake_scale(), which folds it into `size` on mouse release.
#
# Mesh, collider and label are added WITHOUT an `owner`, exactly like the ruler's: what the
# .tscn stores is four properties per box and no geometry at all.

const GRID_SHADER := "res://shaders/metre_grid.gdshader"

## Teal, against the ruler's warm/cyan/grey. Warm is what you clear, cyan is what you grab,
## grey is the instrument - and this is yours. One glance separates the two.
const COLOUR_BLOCKOUT := Color(0.24, 0.62, 0.58)

## Nothing thinner than a hand. A zero-thickness box has no collider worth standing on and
## no face left to grab a handle by.
const MIN_SIZE := 0.1

## Names this node generates for itself and throws away on every rebuild. A duplicate() carries
## copies of them across; clearing by name is what stops a duplicated box owning two meshes.
const GENERATED := ["Mesh", "Shape", "SizeLabel"]

const LABEL_FONT_SIZE := 48
const LABEL_PIXEL_SIZE := 0.012
const LABEL_LIFT := 0.6


## Metres, and the only description of the box there is. The origin is the centre of the BASE:
## the box spans y from 0 to size.y, so raising this grows it upward off whatever it was stood
## on. Matches pilot9's own origin at his soles and the jump grid's at its walking surface.
@export var size := Vector3(4.0, 1.0, 4.0):
	set(value):
		size = Vector3(
			maxf(value.x, MIN_SIZE), maxf(value.y, MIN_SIZE), maxf(value.z, MIN_SIZE))
		_rebuild()
		if Engine.is_editor_hint() and is_inside_tree():
			update_gizmos()

## What a face handle drag and a baked scale round to. Per-box and exported, so one box that
## needs 0.1 m increments does not force them on the rest. Zero or less means no snapping.
@export var snap := 0.5

@export var tint := COLOUR_BLOCKOUT:
	set(value):
		tint = value
		_rebuild()

## The billboard reading "4 x 1 x 6" over the box. Off for a screenshot.
@export var show_size_label := true:
	set(value):
		show_size_label = value
		_rebuild()


func _ready() -> void:
	_rebuild()
	# Editor only: the scale watch below is a gizmo convenience and has no business running a
	# per-frame check in the game.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_bake_scale()


# --- the geometry ---------------------------------------------------------

func _rebuild() -> void:
	# Setters fire while the scene file is still being read, before there is a tree to add
	# children to. _ready() runs this again once there is.
	if not is_inside_tree():
		return
	_clear()

	var mat := _material()
	# Mesh and shape are offset by half a height rather than sitting on the origin, which is
	# what puts the origin on the base. Both get the SAME Vector3 and the same offset.
	var centre := Vector3(0.0, size.y * 0.5, 0.0)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = centre
	mesh.material_override = mat
	# Unshaded, so a shadow cast onto this could not be seen on it anyway. Same call the
	# ruler makes.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = centre
	add_child(shape)

	if show_size_label:
		var label := Label3D.new()
		label.name = "SizeLabel"
		label.text = size_text()
		label.position = Vector3(0.0, size.y + LABEL_LIFT, 0.0)
		label.font_size = LABEL_FONT_SIZE
		label.pixel_size = LABEL_PIXEL_SIZE
		label.outline_size = LABEL_FONT_SIZE / 4
		label.modulate = tint
		label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Discard rather than blend, or a field of these sorts against itself and flickers as
		# the camera turns - the same fix the ruler's captions needed.
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		add_child(label)


func _clear() -> void:
	for nm in GENERATED:
		var child := get_node_or_null(NodePath(nm))
		if child:
			remove_child(child)
			child.queue_free()


func _material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load(GRID_SHADER) as Shader
	mat.set_shader_parameter("base_color", tint)
	return mat


# --- the scale gizmo ------------------------------------------------------

# The scale gizmo is the tool a person's hands already know, so it is allowed - it just does
# not get to leave a scale behind. Whatever it wrote is multiplied into `size` and the node
# goes back to 1.
#
# ON MOUSE RELEASE, and not per frame. The editor computes a drag against the transform it
# captured when the drag started, so a node that rewrites its own scale mid-drag has the whole
# accumulated delta applied to the already-grown value on the next frame, and the box runs away
# under the cursor. Waiting for the button costs one line and cannot glitch.
func _bake_scale() -> void:
	if scale.is_equal_approx(Vector3.ONE):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var s := scale.abs()
	scale = Vector3.ONE
	size = snapped_size(Vector3(size.x * s.x, size.y * s.y, size.z * s.z))


## `size` rounded to `snap`, or unchanged when snapping is off. Shared with the face handles in
## addons/blockout so both routes to a size land on the same increments.
func snapped_size(v: Vector3) -> Vector3:
	if snap <= 0.0:
		return v
	return Vector3(
		maxf(snappedf(v.x, snap), snap),
		maxf(snappedf(v.y, snap), snap),
		maxf(snappedf(v.z, snap), snap))


# --- text -----------------------------------------------------------------

## "4 x 1 x 6". Read by the label and by tests/test_blockout.gd.
func size_text() -> String:
	return "%s x %s x %s" % [_metres(size.x), _metres(size.y), _metres(size.z)]


# "7" for a whole metre, "4.5" otherwise - the same rule the ruler's captions use.
func _metres(m: float) -> String:
	if absf(m - roundf(m)) < 0.001:
		return str(int(round(m)))
	return String.num(m, 2).rstrip("0").rstrip(".")
