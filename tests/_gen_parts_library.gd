extends SceneTree

# One-off generator: writes scenes/habitat_parts/<name>.tscn for every part and the library
# scenes/habitat_parts.tscn with the parts laid out. RE-RUNNING OVERWRITES any rearranging done in
# the library scene. Run:
#   godot --headless --path . --script tests/_gen_parts_library.gd

const PART_SCRIPT := "res://scripts/habitat_part.gd"
const LIB_SCRIPT := "res://scripts/habitat_parts.gd"
const DIR := "res://scenes/habitat_parts/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var part_script: GDScript = load(PART_SCRIPT)
	var lay: Dictionary = part_script.layout()
	var lib := Node3D.new()
	lib.set_script(load(LIB_SCRIPT))
	lib.name = "HabitatParts"
	for p: Array in part_script.PARTS:
		var n := Node3D.new()
		n.set_script(part_script)
		n.name = String(p[0]).to_pascal_case()
		n.set("kind", p[0])
		var ps := PackedScene.new()
		ps.pack(n)
		var path := DIR + String(p[0]) + ".tscn"
		print("save ", path, " ", ResourceSaver.save(ps, path))
		n.free()
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		lib.add_child(inst)
		inst.owner = lib
		inst.position = lay.pos[p[0]]
	var out := PackedScene.new()
	out.pack(lib)
	print("save library ", ResourceSaver.save(out, "res://scenes/habitat_parts.tscn"))
	lib.free()
	quit()
