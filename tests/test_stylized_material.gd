extends "res://tests/test_case.gd"

const STYLIZED := "res://shaders/stylized.gdshader"

func test_stylized_compiles_and_exposes_albedo_and_band_tunables() -> void:
	var names := shader_uniform_names(STYLIZED)
	check(names.size() > 0, "%s did not compile (no uniforms exposed)" % STYLIZED)

	for required in [
		"albedo_color", "gradient_color", "gradient_strength",
		"band_count", "band_softness",
	]:
		check(names.has(required), "missing tunable uniform '%s' (have: %s)" % [required, ", ".join(names)])

# The spec calls these defaults out explicitly with reasons: the middle cel band
# is what makes slopes legible while piloting the mech ("do not default to 2"),
# the gradient is opt-in per-material, and the terminator is razor-thin so it
# reads as a hard step without shimmering in motion.
func test_stylized_ships_the_spec_defaults() -> void:
	eq(declared_default(STYLIZED, "band_count"), "3", "band_count must default to 3 (lit / mid / shadow)")
	approx(declared_default_float(STYLIZED, "gradient_strength"), 0.0, 0.0001, "gradient_strength must default to 0 (flat swatches)")
	approx(declared_default_float(STYLIZED, "band_softness"), 0.02, 0.0001, "band_softness must default to 0.02 (razor-thin terminator)")

# The darkest cel band returns literal zero, so a surface the key light never
# reaches is lit by the hemisphere ambient alone -- which is what crushed the hub
# interior to near-black. shadow_floor lifts the ramp without softening the band
# edges. It ships at 0 so existing materials keep the look they were tuned to;
# it is raised per-material (the hub) rather than globally.
func test_stylized_exposes_an_opt_in_shadow_floor() -> void:
	var names := shader_uniform_names(STYLIZED)
	check(names.has("shadow_floor"), "missing 'shadow_floor' uniform (have: %s)" % ", ".join(names))
	approx(declared_default_float(STYLIZED, "shadow_floor"), 0.0, 0.0001,
		"shadow_floor must ship at 0 so it cannot silently re-tune existing materials")

	var src := FileAccess.open(STYLIZED, FileAccess.READ)
	check(src != null, "could not read %s" % STYLIZED)
	if src == null:
		return
	var text := src.get_as_text()
	# Order matters: lifting before the halftone branch would let the dotting
	# overwrite the floor and put the shadow band back on black.
	var lift := text.find("banded = shadow_floor")
	var dots := text.find("banded = mix(next_level, 0.0, mask)")
	check(dots != -1 and lift != -1 and lift > dots,
		"shadow_floor must be applied after the halftone branch, not before it")

# The hub carries the raised floor, because it is the geometry with interiors:
# the sand ground is deliberately left crushing so the dune shadows stay hard.
func test_hub_material_lifts_its_shadow_band() -> void:
	var mat: ShaderMaterial = load("res://resources/stylized_material.tres")
	check(mat != null, "res://resources/stylized_material.tres failed to load")
	if mat == null:
		return
	var floor_value: float = mat.get_shader_parameter("shadow_floor")
	check(floor_value > 0.0, "the hub material must raise shadow_floor above 0 (got %f)" % floor_value)

# Spec: the shadow band renders as a screen-space ordered dot matrix, on by
# default at low density, with no UVs required so it works on the greybox hub
# immediately. dot_density itself is "TBD in editor" and deliberately not pinned.
func test_stylized_exposes_screen_space_halftone_dotting() -> void:
	var names := shader_uniform_names(STYLIZED)
	for required in ["dot_enabled", "dot_density", "dot_scale_px"]:
		check(names.has(required), "missing dotting uniform '%s' (have: %s)" % [required, ", ".join(names)])
	eq(declared_default(STYLIZED, "dot_enabled"), "true", "dotting must be on by default")

# Spec: a hard thresholded white blob, stepped like the cel bands so the
# compositor outlines it. Built now for Exia's "metal", shipped off.
func test_stylized_exposes_specular_blob_shipped_off() -> void:
	var names := shader_uniform_names(STYLIZED)
	for required in ["specular_enabled", "specular_threshold", "specular_color"]:
		check(names.has(required), "missing specular uniform '%s' (have: %s)" % [required, ", ".join(names)])
	eq(declared_default(STYLIZED, "specular_enabled"), "false", "specular blob must ship off")

# Godot's Environment only offers a single flat ambient colour, but the spec
# calls for a two-colour hemisphere: sky tint onto upward faces, warm ground
# bounce onto downward ones. The shader owns ambient so the split is possible,
# which means these uniforms are the ambient controls for the whole look.
func test_stylized_owns_the_two_colour_hemisphere_ambient() -> void:
	var names := shader_uniform_names(STYLIZED)
	for required in ["ambient_sky_color", "ambient_ground_color", "ambient_energy"]:
		check(names.has(required), "missing ambient uniform '%s' (have: %s)" % [required, ", ".join(names)])

	var src := FileAccess.open(STYLIZED, FileAccess.READ)
	check(src != null, "could not read %s" % STYLIZED)
	if src == null:
		return
	# Godot's own ambient must be off, or it competes with the hemisphere and
	# washes the cel bands out from underneath.
	check(src.get_as_text().contains("ambient_light_disabled"),
		"shader must declare ambient_light_disabled so engine ambient does not double up")
