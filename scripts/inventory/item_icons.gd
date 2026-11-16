extends Node

# Renders each wearable item's grid icon once from its real model: the hat's meshes, the staff and
# revolver scenes, and a small blockout coat. One offscreen SubViewport per icon, three-quarter view
# under a key light, kept as an ImageTexture. Child of the Inventory autoload; `icon_for()` returns
# null until the render has landed (the screen draws the colour block meanwhile) and also under
# --headless, where nothing renders. See docs/specs/equipment-slots.md.

const _CowboyHatMesh := preload("res://scripts/items/cowboy_hat_mesh.gd")

## Icon pixels per grid cell. The screen draws it nearest into 16 texels per cell.
const PX_PER_CELL := 32
## Three-quarter view: yaw and pitch of the item toward the camera, degrees.
const VIEW_YAW := -35.0
const VIEW_PITCH := 22.0
## Share of the icon the item fills.
const FILL := 0.86

# id -> Texture2D, or null while the render is under way.
var _icons := {}


func icon_for(def: ItemDef) -> Texture2D:
	if def == null or def.id == &"" or DisplayServer.get_name() == "headless":
		return null
	if not _icons.has(def.id):
		_icons[def.id] = null
		_render.call_deferred(def)
	return _icons[def.id]


func _render(def: ItemDef) -> void:
	var root := _build(def)
	if root == null or not is_inside_tree():
		return
	var px := def.size * PX_PER_CELL
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.74)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	vp.add_child(key)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(root)
	var box := _frame(pivot, root, float(px.x) / float(px.y))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = box["size"]
	cam.near = 0.05
	cam.far = 50.0
	cam.position = Vector3(box["center"].x, box["center"].y, 10.0)
	vp.add_child(cam)
	cam.current = true
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img != null and not img.is_empty():
		_icons[def.id] = ImageTexture.create_from_image(img)


## Turns `root` so its longest axis stands up, tips it toward the camera, and returns the camera's
## ortho height and the centre to aim at. All in `pivot` space (the camera looks down -Z).
func _frame(pivot: Node3D, root: Node3D, aspect: float) -> Dictionary:
	var raw := _bounds(root, Transform3D.IDENTITY)
	var lift := Basis()
	var ext := raw.size
	if ext.x >= ext.y and ext.x >= ext.z and ext.x > ext.y * 1.6:
		lift = Basis(Vector3.BACK, deg_to_rad(90.0))
	elif ext.z >= ext.y and ext.z >= ext.x and ext.z > ext.y * 1.6:
		lift = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	var view := Basis(Vector3.RIGHT, deg_to_rad(VIEW_PITCH)) * Basis(Vector3.UP, deg_to_rad(VIEW_YAW)) * lift
	pivot.basis = view
	var box := _bounds(root, Transform3D(view, Vector3.ZERO))
	var h := maxf(box.size.y, box.size.x / aspect) / FILL
	return {"size": h, "center": box.get_center()}


## The union of every mesh's box under `n`, transformed by `to_here`.
func _bounds(n: Node3D, to_here: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for node in [n] + n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var rel := to_here * (n.global_transform.affine_inverse() * mi.global_transform) if mi.is_inside_tree() \
			else to_here * _local_to(n, mi)
		var b := rel * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _local_to(top: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != top:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t


# --- the models --------------------------------------------------------------------------------

func _build(def: ItemDef) -> Node3D:
	match def.id:
		&"cowboy_hat":
			var hat := Node3D.new()
			hat.add_child(_mesh_node(_CowboyHatMesh.build_felt(), Color(0.27, 0.16, 0.09)))
			hat.add_child(_mesh_node(_CowboyHatMesh.build_band(), Color(0.11, 0.065, 0.04)))
			return hat
		&"trench_coat":
			return _build_coat()
		&"backpack":
			var wrapper := Node3D.new()
			wrapper.add_child(_backpack_node(false))
			return wrapper
	if def.held_item != null and def.held_item.scene != null:
		var n := def.held_item.scene.instantiate() as Node3D
		if n != null:
			var wrapper := Node3D.new()
			wrapper.add_child(n)
			return wrapper
	return null


## The backpack's own mesh in its colours (docs/specs/pilot9-backpack.md). `cel` = pilot9's cel
## material (the ground copy); else plain lit colours (the icon).
static func _backpack_node(cel: bool) -> Node3D:
	var mesh_script := preload("res://scripts/items/backpack_mesh.gd")
	var mats := []
	for i in mesh_script.COLOURS.size():
		var c: Color = mesh_script.COLOURS[i]
		var glows: bool = i == mesh_script.THRUSTER
		if cel:
			mats.append(preload("res://scripts/items/backpack_holder.gd")._tinted(c, 4.0 if glows else 0.0))
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = c
			mat.roughness = 0.9
			if glows:
				mat.emission_enabled = true
				mat.emission = c
			mats.append(mat)
	return mesh_script.build_node(mats)


func _mesh_node(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


func _box(size: Vector3, at: Vector3, color: Color, tilt_z: float = 0.0) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := _mesh_node(m, color)
	mi.position = at
	mi.rotation.z = deg_to_rad(tilt_z)
	return mi


## A blockout trench coat: skirt, chest, collar, two sleeves.
func _build_coat() -> Node3D:
	var leather := Color(0.36, 0.22, 0.12)
	var lining := Color(0.16, 0.10, 0.06)
	var coat := Node3D.new()
	coat.add_child(_box(Vector3(0.52, 0.55, 0.26), Vector3(0.0, -0.32, 0.0), leather))
	coat.add_child(_box(Vector3(0.44, 0.5, 0.24), Vector3(0.0, 0.2, 0.0), leather))
	coat.add_child(_box(Vector3(0.16, 0.48, 0.02), Vector3(0.0, 0.2, 0.125), lining))
	coat.add_child(_box(Vector3(0.34, 0.08, 0.28), Vector3(0.0, 0.48, 0.0), leather))
	coat.add_child(_box(Vector3(0.14, 0.62, 0.15), Vector3(-0.34, 0.12, 0.0), leather, -14.0))
	coat.add_child(_box(Vector3(0.14, 0.62, 0.15), Vector3(0.34, 0.12, 0.0), leather, 14.0))
	return coat
