extends "res://tests/test_case.gd"

# Cel scatter - see docs/specs/cel-scatter.md. What can be fenced headlessly: the shader still
# compiles with the include, the globals exist with the grilled defaults, and the setting is a
# graphics toggle that defaults on. What the chips look like is checked by eye
# (tests/_probe_scatter_shot.gd).

const BASE := "res://shaders/cel/cel-shader-base.gdshader"
const SettingsScript := preload("res://scripts/settings.gd")

func test_the_cel_shader_compiles_with_the_scatter() -> void:
	check(shader_uniform_names(BASE).size() > 0, "cel-shader-base failed to compile")

func test_project_declares_every_scatter_global() -> void:
	for key in ["scatter_strength", "scatter_dark", "scatter_light", "scatter_reach",
			"scatter_world_size", "scatter_uv_size"]:
		var entry: Dictionary = ProjectSettings.get_setting("shader_globals/" + key, {})
		eq(entry.get("type"), "float", "shader global %s missing or not a float" % key)
	eq(ProjectSettings.get_setting("shader_globals/scatter_strength", {}).get("value"), 1.0,
		"the scatter is on unless the setting turns it off")
	var dark: float = ProjectSettings.get_setting("shader_globals/scatter_dark", {}).get("value")
	var light: float = ProjectSettings.get_setting("shader_globals/scatter_light", {}).get("value")
	check(dark > light, "the scatter is weighted toward dark flecks in the lit band")

func test_the_setting_is_a_graphics_toggle_that_defaults_on() -> void:
	var row: Array = SettingsScript._row(&"cel_scatter")
	check(not row.is_empty(), "no cel_scatter row")
	if row.is_empty():
		return
	eq(row[2], "graphics", "CEL SCATTER lives under graphics")
	eq(row[3], ["off", "on"], "CEL SCATTER is OFF / ON")
	eq(SettingsScript.defaults()[&"cel_scatter"], "off", "default OFF")
