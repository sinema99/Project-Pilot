extends "res://tests/test_case.gd"

const SKY := "res://shaders/gradient_sky.gdshader"

# Spec: banded sky is 3-4 hard colour bands with tunable colours AND tunable
# band heights, plus an optional soft sun disk. test.tscn's environment is
# dialled in through these uniform names, so they are the contract.
func test_gradient_sky_compiles_and_exposes_band_and_sun_tunables() -> void:
	var names := shader_uniform_names(SKY)
	check(names.size() > 0, "%s did not compile (no uniforms exposed)" % SKY)

	for required in [
		"horizon_color", "mid_color", "upper_color", "zenith_color",
		"horizon_height", "mid_height", "upper_height",
		"sun_enabled", "sun_size", "sun_softness", "sun_color",
	]:
		check(names.has(required), "missing tunable uniform '%s' (have: %s)" % [required, ", ".join(names)])
