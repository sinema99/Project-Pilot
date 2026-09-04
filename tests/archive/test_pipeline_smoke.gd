extends "res://tests/test_case.gd"

# A broken shader in Godot does not fail loudly -- it renders magenta, or
# silently drops the effect. This is the cheap standing check that every piece
# of the pipeline still loads and compiles.

const GDSHADERS := [
	"res://shaders/archive/stylized.gdshader",
	"res://shaders/archive/gradient_sky.gdshader",
]

func test_every_gdshader_compiles() -> void:
	for path in GDSHADERS:
		var sh: Shader = load(path)
		check(sh != null, "%s failed to load" % path)
		if sh == null:
			continue
		check(sh.get_shader_uniform_list().size() > 0,
			"%s exposes no uniforms, which means it failed to compile" % path)

# The compute shader's SPIR-V is built at import time, so its compile errors are
# readable here without a GPU or a live RenderingDevice.
func test_outline_compute_shader_compiles_to_spirv() -> void:
	var shader_file: RDShaderFile = load("res://shaders/archive/moebius_outline.glsl")
	check(shader_file != null, "res://shaders/archive/moebius_outline.glsl failed to load")
	if shader_file == null:
		return
	var spirv := shader_file.get_spirv()
	check(spirv != null, "no SPIR-V produced for moebius_outline.glsl")
	if spirv == null:
		return
	var err := spirv.compile_error_compute
	eq(err, "", "moebius_outline.glsl failed to compile")

# test.tscn is the whole deliverable: if it fails to load, or the applier's
# NodePaths do not resolve, the look silently does not happen at runtime and
# nothing reports it.
func test_test_scene_loads_and_its_stylized_targets_resolve() -> void:
	var packed: PackedScene = load("res://scenes/test.tscn")
	check(packed != null, "res://scenes/test.tscn failed to load")
	if packed == null:
		return

	var root := packed.instantiate()
	check(root != null, "res://scenes/test.tscn failed to instantiate")
	if root == null:
		return

	var applier := root.get_node_or_null("ApplyStylized")
	check(applier != null, "test.tscn has no ApplyStylized node")
	if applier != null:
		check(applier.material != null, "ApplyStylized has no material assigned")
		# Called directly: _ready does not fire on a detached instance.
		var count: int = applier.apply_now()
		check(count > 0, "ApplyStylized resolved its targets but found no meshes (count=%d)" % count)

	# The character is the one thing that ships with no material of its own, so
	# without an applier of her own she renders on Godot's default white PBR
	# material: blown out, no cel bands, and shadow-map acne straight through.
	var char_applier := root.get_node_or_null("ApplyStylizedCharacter")
	check(char_applier != null, "test.tscn has no ApplyStylizedCharacter node")
	if char_applier != null:
		check(char_applier.material != null, "ApplyStylizedCharacter has no material assigned")
		check(char_applier.material != root.get_node("ApplyStylized").material,
			"the character must not share the hub's swatch, or she vanishes against the walls")
		var char_count: int = char_applier.apply_now()
		check(char_count > 0, "ApplyStylizedCharacter found no meshes (count=%d)" % char_count)

	check(root.get_node_or_null("WorldEnvironment") != null, "test.tscn has no WorldEnvironment")
	check(root.get_node_or_null("SETSUNA") != null, "test.tscn does not instance SETSUNA")
	check(root.get_node_or_null("EXIA") == null, "test.tscn must not include EXIA in this phase")
	root.free()
