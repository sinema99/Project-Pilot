extends SceneTree

# Throwaway probe, WINDOWED: builds Hub2Piece / Hub2Door kinds in rows and shoots each row up close
# so the meshes can be reviewed before they are placed (docs/specs/hub2-final-pass.md).
#   godot --path . --script tests/_probe_hub2_gallery.gd -- <out_dir> [row]

const K := Hub2Piece.Kind
# rows: [name, spacing, [[kind, variant, state, size, text, powered, yaw]...]]
var ROWS := [
	["freight", 9.0, [[K.BOX20, 0, 0], [K.BOX20, 1, 1], [K.BOX20, 2, 2], [K.BOX20, 3, 3], [K.BOX20, 4, 4], [K.REEFER, 0, 0]]],
	["freight2", 10.0, [[K.BOX40, 0, 1], [K.POD, 0, 0], [K.POD, 3, 0], [K.LOADER, 0, 0], [K.LOADER, 1, 0], [K.LOADER, 3, 0]]],
	["machines", 5.0, [[K.EXOFRAME, 0, 0], [K.EXOFRAME, 1, 0], [K.DRONE_RACK, 0, 0], [K.GENERATOR, 0, 0], [K.FUEL_TANK, 0, 0], [K.PUMP, 0, 0], [K.TANK_V, 0, 0, Vector3(1.5, 5, 1)]]],
	["rubble", 4.0, [[K.SLAB, 0, 0, Vector3(3, 0.4, 2)], [K.CEIL_PANEL, 0, 0, Vector3(3, 1, 1.5)], [K.CABLE_TRAY, 0, 0, Vector3(4, 1, 1)], [K.DEBRIS, 0, 0, Vector3(3, 1, 2)], [K.SANDBAGS, 0, 0, Vector3(3, 1.1, 1)], [K.JERSEY, 2, 0], [K.SHEET, 1, 0, Vector3(2.5, 1, 1.2)], [K.REBAR, 0, 0]]],
	["rooms", 3.0, [[K.LOCKERS, 0, 1, Vector3(3, 1, 1)], [K.BENCH, 0, 0], [K.VENDING, 0, 0], [K.TABLE, 1, 0], [K.DESK, 1, 0], [K.BOARD, 0, 0], [K.BEDROLL, 0, 0], [K.CAMPFIRE, 0, 0, Vector3.ONE, "", true], [K.DRUM, 0, 2, Vector3.ONE, "", true]]],
	["rooms2", 4.0, [[K.WEAPON_RACK, 0, 0], [K.SCANNER_ARCH, 0, 0], [K.BOOTH, 0, 0], [K.INSPECT_TABLE, 0, 0], [K.VEHICLE_LIFT, 1, 0], [K.TOOL_WALL, 0, 0], [K.BODY, 0, 0], [K.HOLO_RING, 0, 0]]],
	["small", 1.6, [[K.CONE, 0, 0], [K.BOLLARD, 0, 0], [K.PAPERS, 0, 0, Vector3(1, 1, 1)], [K.CANS, 0, 0], [K.CHAIR, 1, 0], [K.DRUM, 1, 1], [K.CHEMLIGHT, 0, 0, Vector3.ONE, "", true], [K.KEYPAD, 1, 0], [K.EMERGENCY_LAMP, 0, 0, Vector3.ONE, "", true], [K.EMERGENCY_LAMP, 3, 0, Vector3.ONE, "", true]]],
	["signs", 4.0, [[K.STENCIL, 0, 0, Vector3(0.1, 1, 1), "BAY B-04"], [K.TAG, 0, 0], [K.TAG, 2, 1], [K.TAG, 3, 2], [K.TAG, 5, 3, Vector3.ONE, "NO WAY"], [K.BAY_NUMBER, 0, 0, Vector3(0.25, 1, 1), "B4", true], [K.LED_STRIP, 0, 0, Vector3(3, 1, 1), "", true], [K.PUDDLE, 0, 0, Vector3(3, 1, 2)]]],
	["structure", 7.0, [[K.RAILING, 1, 0, Vector3(6, 1, 1)], [K.STAIR, 0, 0, Vector3(1.4, 3.0, 4.5)], [K.DECK, 0, 0, Vector3(4, 2, 3)], [K.CABIN, 0, 0], [K.CABIN, 1, 1], [K.SHED, 0, 0, Vector3(6, 4, 5)]]],
	["structure2", 8.0, [[K.FENCE, 1, 0, Vector3(6, 1, 1)], [K.SHUTTER, 0, 1, Vector3(5, 5, 1), "CS-03"], [K.BULKHEAD, 0, 0, Vector3(8, 7.3, 0), "B-2"], [K.BULKHEAD, 2, 0, Vector3(8, 7.3, 0)], [K.COLD_CAGE, 0, 0, Vector3(7, 4, 6)], [K.TARP, 0, 0, Vector3(3, 1.4, 2)]]],
	["doors", 9.0, [["door", 0], ["door", 1], ["door", 2], [K.CARRIER, 0, 0], [K.GIRDER_FALLEN, 0, 0, Vector3(14, 1, 1)]]],
]

var _f := 0
var _row := 0
var _out := ""
var _cam: Camera3D
var _holder: Node3D
var _only := -1


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	if a.size() > 1:
		_only = int(a[1])
		_row = _only
	PropMeshCache.enabled = false
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.32, 0.33)
	floor_mi.material_override = fm
	w.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 55
	w.add_child(_cam)
	_cam.current = true
	_holder = Node3D.new()
	w.add_child(_holder)


func _spawn_row(r: Array) -> void:
	for c in _holder.get_children():
		c.free()
	var spacing: float = r[1]
	var items: Array = r[2]
	for i in items.size():
		var it: Array = items[i]
		var x := (i - (items.size() - 1) * 0.5) * spacing
		var n: Node3D
		if it[0] is String:
			var d := Hub2Door.new()
			d.type = it[1]
			d.width = 4.2 if it[1] == 1 else 7.0
			d.height = 4.4 if it[1] == 1 else 6.3
			n = d
		else:
			var p := Hub2Piece.new()
			p.kind = it[0]
			p.variant = it[1]
			p.state = it[2]
			if it.size() > 3:
				p.size = it[3]
			if it.size() > 4:
				p.text = it[4]
			if it.size() > 5:
				p.powered = it[5]
			n = p
			if p.kind == K.CARRIER:
				n.position.y = 7.0
		n.position.x = x
		_holder.add_child(n)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_spawn_row(ROWS[_row])
		var r: Array = ROWS[_row]
		var span: float = r[1] * (r[2] as Array).size()
		_cam.position = Vector3(span * 0.05, span * 0.16 + 1.5, span * 0.36 + 2.5)
		_cam.look_at(Vector3(0, 1.2, 0))
	if _f == 12:
		root.get_texture().get_image().save_png("%s/g_%02d_%s.png" % [_out, _row, ROWS[_row][0]])
		_row += 1
		_f = 0
		if _only >= 0 or _row >= ROWS.size():
			return true
	return false
