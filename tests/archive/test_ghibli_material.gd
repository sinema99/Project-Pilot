extends "res://tests/test_case.gd"

# Contract + wiring for the Ghibli/BOTW pass. See docs/specs/ghibli-pass.md.
#
# These prove the prototype collapsed cleanly (one ramp, no halftone) and that
# scenes/test2.tscn was repointed and re-rigged correctly. They do NOT judge the
# look -- that is the developer's play-test.

const GHIBLI := "res://shaders/archive/stylized_ghibli.gdshader"
const SCENE := "res://scenes/test2.tscn"
const DEAD_SWITCH := "res://scripts/archive/ghibli_mode_switch.gd"

func test_ghibli_compiles_and_exposes_its_tunables() -> void:
	var names := shader_uniform_names(GHIBLI)
	check(names.size() > 0, "%s did not compile (no uniforms exposed)" % GHIBLI)
	for required in [
		"albedo_color", "gradient_color", "gradient_strength",
		"soft_terminator", "lit_tint", "shadow_tint", "warm_cool_strength",
		"shadow_floor", "band_softness",
		"breakup_strength", "breakup_scale",
		"rim_enabled", "rim_color", "rim_threshold", "rim_strength",
	]:
		check(names.has(required), "missing tunable uniform '%s' (have: %s)" % [required, ", ".join(names)])

# The prototype carried three ramp modes and the inherited halftone. HYBRID was
# chosen; the file must collapse to it, or a stale uniform sits on every
# material and the "one ramp" claim is a lie.
func test_ghibli_dropped_the_prototype_scaffolding() -> void:
	var names := shader_uniform_names(GHIBLI)
	for gone in ["ramp_mode", "soft_band_count", "dot_enabled", "dot_density", "dot_scale_px"]:
		check(not names.has(gone), "uniform '%s' should have been removed in the collapse (have: %s)" % [gone, ", ".join(names)])

	var src := FileAccess.open(GHIBLI, FileAccess.READ)
	check(src != null, "could not read %s" % GHIBLI)
	if src == null:
		return
	var text := src.get_as_text()
	check(not text.contains("halftone"), "halftone code should be gone from the Ghibli shader")
	check(not text.contains("ramp_mode"), "ramp_mode branching should be gone from the Ghibli shader")
	# The in-shader hemisphere ambient was stripped when test2 moved to an HDR
	# panorama sky; engine sky-source ambient fills the shadow side now.
	check(not text.contains("ambient_sky_color") and not text.contains("ambient_light_disabled"),
		"the in-shader hemisphere ambient (and ambient_light_disabled) should have been removed")

# Expected values are from the spec, not read back from the file.
func test_ghibli_ships_the_spec_defaults() -> void:
	approx(declared_default_float(GHIBLI, "soft_terminator"), 0.38, 0.0001,
		"soft_terminator must default to 0.38 (the Sable<->Ghibli hardness dial)")
	approx(declared_default_float(GHIBLI, "breakup_strength"), 0.18, 0.0001,
		"breakup_strength must default to 0.18")
	approx(declared_default_float(GHIBLI, "band_softness"), 0.02, 0.0001,
		"band_softness must default to 0.02")
	eq(declared_default(GHIBLI, "rim_enabled"), "false",
		"the rim must ship off; it is enabled per-material on Setsuna in test2")

# test2 lights ambient from the HDR panorama sky, so the shader must NOT declare
# ambient_light_disabled -- that would block the sky fill it now depends on.
func test_ghibli_lets_engine_sky_ambient_through() -> void:
	var src := FileAccess.open(GHIBLI, FileAccess.READ)
	check(src != null, "could not read %s" % GHIBLI)
	if src == null:
		return
	check(not src.get_as_text().contains("ambient_light_disabled"),
		"shader must NOT disable engine ambient -- test2's HDR sky is the fill light now")

# --- test2.tscn wiring --------------------------------------------------------

func _scene_shader_materials() -> Array:
	var out: Array = []
	var ps := load(SCENE) as PackedScene
	check(ps != null, "%s failed to load" % SCENE)
	if ps == null:
		return out
	var st := ps.get_state()
	var seen: Dictionary = {}
	for n in st.get_node_count():
		for p in st.get_node_property_count(n):
			_harvest(st.get_node_property_value(n, p), seen)
	out.assign(seen.keys())
	return out

func _harvest(val: Variant, seen: Dictionary) -> void:
	if val is ShaderMaterial:
		seen[val] = true
	elif val is Dictionary:
		for k in (val as Dictionary):
			_harvest((val as Dictionary)[k], seen)
	elif val is Array:
		for e in (val as Array):
			_harvest(e, seen)

func test_test2_materials_all_point_at_the_ghibli_shader() -> void:
	var mats := _scene_shader_materials()
	check(mats.size() == 6, "expected 6 ShaderMaterials in test2.tscn, found %d" % mats.size())
	for m in mats:
		var sm := m as ShaderMaterial
		check(sm.shader != null and sm.shader.resource_path == GHIBLI,
			"a test2 ShaderMaterial points at '%s', not the Ghibli shader" %
			(sm.shader.resource_path if sm.shader else "<null>"))

# Spec: rim on Setsuna's three body materials only -- off on the ground, the hub,
# and the black screen bezel (a glowing bezel eats the screen).
func test_test2_rim_is_on_for_setsuna_only() -> void:
	var mats := _scene_shader_materials()
	var rim_on := 0
	var rim_off := 0
	for m in mats:
		var sm := m as ShaderMaterial
		var rim := bool(sm.get_shader_parameter("rim_enabled"))
		if rim:
			rim_on += 1
		else:
			rim_off += 1
		var a: Color = sm.get_shader_parameter("albedo_color")
		if a != null and a.r < 0.02 and a.g < 0.02 and a.b < 0.02:
			check(not rim, "the pure-black Highlights bezel must not have rim_enabled")
			check(float(sm.get_shader_parameter("breakup_strength")) == 0.0,
				"the black bezel must keep breakup_strength at 0 (flat black stays flat)")
	eq(rim_on, 3, "exactly the 3 Setsuna body materials should have rim_enabled")
	eq(rim_off, 3, "the ground, hub and bezel materials should have rim off")

func test_the_prototype_switch_is_gone() -> void:
	check(not FileAccess.file_exists(DEAD_SWITCH),
		"%s should have been deleted with the prototype" % DEAD_SWITCH)
	var f := FileAccess.open(SCENE, FileAccess.READ)
	check(f != null, "could not read %s" % SCENE)
	if f == null:
		return
	check(not f.get_as_text().contains("ghibli_mode_switch"),
		"test2.tscn still references ghibli_mode_switch -- the throwaway node was left in")
