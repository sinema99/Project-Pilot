extends Node

# Autoload `Settings`: the model, the file, the apply. See docs/specs/settings.md.
#
# The registry and every value operation are static functions with no tree
# behind them, the same discipline ui_manager.gd applies to resolve() and for
# the same reason: a row that clamps wrong at one end, a config that loads a
# stale key as garbage, a default that drifts from project.godot - all of them
# look exactly like a settings screen that works.
#
# This is the first thing in the project that remembers anything between
# launches. Settings only, not a save system - see the spec's Scope section.

const SAVE_PATH := "user://settings.cfg"
const SAVE_DEBOUNCE := 0.5
const PAINT_STRENGTH_ON := 0.5  # painted shading at half opacity; 1.0 was too noticeable
const CONFIG_VERSION := 1

## True under `--headless`, which means the test suite and the `--quit-after` smoke boot.
##
## Such a run neither reads nor writes user://settings.cfg. Autoloads load during headless
## runs, so without this the suite's verdict depends on a file outside the repo: a fresh clone
## passes, and the same commit fails on a machine where somebody once nudged a slider. That is
## not hypothetical - it is what turned test_pilot9_sprint_fov.gd red, on two tests that have
## nothing to do with settings. It also keeps a test run from overwriting real settings.
##
## The display server, not `OS.has_feature("headless")`, which is **false** under --headless -
## it reports export features, and a headless run of the editor binary is not an export. The
## driver is the thing that actually differs, and it reports "headless" rather than "windows".
static func is_test_run() -> bool:
	return DisplayServer.get_name() == "headless"

## True when playing inside the editor's Game tab. That window refuses every mode but windowed
## and every resize or move, so WINDOW MODE and RESOLUTION save there but cannot apply.
static func is_embedded() -> bool:
	return Engine.is_embedded_in_editor()

# key, label, section, values, default index
#
# The two continuous rows (BRIGHTNESS, both sensitivities) and FOV are written
# out as literal ranges rather than generated: GDScript const initializers must
# be constant expressions, so a helper function call is not allowed here.
const DEFS := [
	# BORDERLESS is borderless *fullscreen*, FULLSCREEN is exclusive - see the spec's Display Modes.
	[&"window_mode", "WINDOW MODE", "display",
		["windowed", "borderless", "fullscreen"], 0],
	[&"resolution", "RESOLUTION", "display",
		[Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
			Vector2i(2560, 1440), Vector2i(3840, 2160)], 2],
	[&"vsync", "VSYNC", "display", ["off", "on", "adaptive"], 1],
	[&"max_fps", "MAX FPS", "display", [0, 30, 60, 120, 144], 0],
	# 0.60 .. 1.40, step 0.05. Default index 8 = 1.00.
	[&"brightness", "BRIGHTNESS", "display", [
		0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00,
		1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40], 8],
	[&"render_scale", "RENDER SCALE", "graphics", [0.5, 0.75, 1.0], 2],
	[&"shadow_quality", "SHADOW QUALITY", "graphics", ["low", "medium", "high"], 2],
	[&"msaa", "ANTI-ALIASING", "graphics", ["off", "2x", "4x", "8x"], 2],
	# Window pixels per block of the low-res world, 0 = OFF; and levels per colour channel, 0 =
	# FULL. See docs/specs/pixel-world.md.
	[&"pixel_size", "PIXEL FILTER", "graphics", [0, 2, 3, 4, 6], 0],
	# The PIXEL look's own block size: no OFF, 4X by default. It has no row of its own - the PIXEL
	# FILTER row edits whichever look is on (pixel_filter_key()). See docs/specs/pixel-look.md.
	[&"pixel_look_size", "PIXEL FILTER", "graphics", [2, 3, 4, 6], 2],
	# CEL (today's ink look), PIXEL (stepped soft light, surface clumps, warm haze, no ink) or
	# RETRO (90s anime cel: coloured lines, flat fills, video softness). RETRO is the default
	# while it is being judged. See docs/specs/pixel-look.md and docs/specs/retro-look.md.
	[&"look", "LOOK", "graphics", ["cel", "pixel", "retro"], 2],
	# SMOOTH, or ANIME: characters' poses held and refreshed 12 times a second while the game stays
	# smooth. SMOOTH by default; U flips it in play. See docs/specs/anime-animation.md.
	[&"anime_animation", "ANIMATION", "graphics", ["smooth", "anime"], 0],
	[&"colour_depth", "COLOUR DEPTH", "graphics", [0, 32, 16, 8], 0],
	# Hand-painted patches inside each cel tone - see docs/specs/painted-shading.md.
	[&"painted_shading", "PAINTED SHADING", "graphics", ["off", "on"], 1],
	# Chipped, scattered band edges - see docs/specs/cel-scatter.md.
	[&"cel_scatter", "CEL SCATTER", "graphics", ["off", "on"], 0],
	# 0.25x .. 2.00x, step 0.05. Default index 15 = 1.00x.
	[&"mouse_sensitivity", "MOUSE SENSITIVITY", "controls", [
		0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70,
		0.75, 0.80, 0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.20,
		1.25, 1.30, 1.35, 1.40, 1.45, 1.50, 1.55, 1.60, 1.65, 1.70,
		1.75, 1.80, 1.85, 1.90, 1.95, 2.00], 15],
	[&"controller_sensitivity", "CONTROLLER SENSITIVITY", "controls", [
		0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70,
		0.75, 0.80, 0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.20,
		1.25, 1.30, 1.35, 1.40, 1.45, 1.50, 1.55, 1.60, 1.65, 1.70,
		1.75, 1.80, 1.85, 1.90, 1.95, 2.00], 15],
	# 60 .. 110, step 5. Default index 3 = 75.
	[&"fov", "FOV", "controls", [60, 65, 70, 75, 80, 85, 90, 95, 100, 105, 110], 3],
	# pilot9's run/sprint sway and landing dip - see docs/specs/pilot9-camera-sway.md.
	[&"camera_motion", "CAMERA MOTION", "controls", ["off", "on"], 1],
	# The pause menu as a projection from pilot9's visor - see docs/specs/pilot9-hologram-pause.md.
	[&"hologram_menu", "HOLOGRAM MENU", "controls", ["off", "on"], 0],
	# pilot9's sparks, dust and air - see docs/specs/pilot9-movement-vfx.md.
	[&"movement_effects", "MOVEMENT EFFECTS", "controls", ["off", "on"], 1],
]

## The size the UI is laid out at. With stretch aspect `keep` this is also the shape the 3D is
## letterboxed to, which is what scale_3d() measures a resolution against.
const BASE_SIZE := Vector2(1920, 1080)
## Title bar height to assume when the window has not been decorated yet (first boot, or coming
## out of fullscreen). Windows 10 at 100% scaling is 31; this errs a little large, towards
## maximizing rather than hanging a window under the taskbar.
const FALLBACK_TITLE_BAR := 40

var _values: Dictionary = {}
var _save_timer: Timer
## Bumped by every display apply, so a stale deferred resize from an earlier one gives up.
var _display_generation := 0

# --- static model, no tree behind it -------------------------------------------

static func _row(key: StringName) -> Array:
	for row: Array in DEFS:
		if row[0] == key:
			return row
	return []

static func defaults() -> Dictionary:
	var out: Dictionary = {}
	for row: Array in DEFS:
		var values: Array = row[3]
		out[row[0]] = values[row[4]]
	return out

## Total: an empty dictionary, a missing key, an unknown key, a value outside
## its list, and a wrong `version` each produce a complete, playable set of
## defaults. A config that half-loads must still give a game that is
## configured correctly rather than one that looks fine and is not.
static func sanitise(raw: Dictionary) -> Dictionary:
	if raw.get("version") != CONFIG_VERSION:
		return defaults()
	var out: Dictionary = {}
	for row: Array in DEFS:
		var key: StringName = row[0]
		var values: Array = row[3]
		var default_index: int = row[4]
		var value: Variant = raw.get(key, values[default_index])
		# EXCLUSIVE was renamed FULLSCREEN, not removed: an old save keeps the mode it picked.
		if key == &"window_mode" and value == "exclusive":
			value = "fullscreen"
		out[key] = value if values.has(value) else values[default_index]
	return out

## Clamps, does not wrap. Wrapping is right for the tab strip, where there are
## four destinations and you are cycling; it is wrong for an ordered scale,
## where holding a key to reach the end and having the value silently reappear
## at the other end is how you overshoot every time.
static func step(key: StringName, index: int, direction: int) -> int:
	var row := _row(key)
	if row.is_empty():
		return index
	var values: Array = row[3]
	return clampi(index + direction, 0, values.size() - 1)

static func index_of(key: StringName, value: Variant) -> int:
	var row := _row(key)
	if row.is_empty():
		return -1
	var values: Array = row[3]
	var i: int = values.find(value)
	return i if i >= 0 else row[4]

static func value_at(key: StringName, index: int) -> Variant:
	var row := _row(key)
	if row.is_empty():
		return null
	var values: Array = row[3]
	return values[clampi(index, 0, values.size() - 1)]

static func label_of(key: StringName) -> String:
	var row := _row(key)
	return String(row[1]) if not row.is_empty() else ""

static func section_of(key: StringName) -> String:
	var row := _row(key)
	return String(row[2]) if not row.is_empty() else ""

static func values_of(key: StringName) -> Array:
	var row := _row(key)
	return row[3] if not row.is_empty() else []

## Whether a WINDOWED window of `size` fits the desktop's usable area (the screen minus the
## taskbar) with its title bar on top. One that does not is maximized instead.
static func window_fits(size: Vector2i, usable: Rect2i, title_bar: int) -> bool:
	return size.x <= usable.size.x and size.y + title_bar <= usable.size.y

## Viewport.scaling_3d_scale for a `resolution` shown in a window of `window_size`. The 3D
## renders inside the 16:9 area the window letterboxes to, so the resolution is measured against
## that; in a window sized to the resolution this is 1 and RENDER SCALE is all that is left. In
## fullscreen it is the render-resolution half of the row. Capped at 1: a maximized window a
## little smaller than the resolution renders at window size rather than supersampling.
static func scale_3d(resolution_size: Vector2i, window_size: Vector2i, scale_factor: float) -> float:
	var content_width := minf(window_size.x, window_size.y * BASE_SIZE.x / BASE_SIZE.y)
	if content_width <= 0.0:
		return scale_factor
	return minf(resolution_size.x / content_width, 1.0) * scale_factor

## The key the PIXEL FILTER row (and PixelWorld's QA keys) edit: each look keeps its own block
## size, so I jumps between CEL's and PIXEL's. See docs/specs/pixel-look.md, "Reference pass".
static func pixel_filter_key(look_value: String) -> StringName:
	return &"pixel_look_size" if look_value == "pixel" else &"pixel_size"

## The block size PixelWorld draws at: the active look's own size. PIXEL's list has no OFF, so
## the PIXEL look is never shown unpixelated.
static func effective_pixel_size(pixel_size_value: int, pixel_look_size_value: int, look_value: String) -> int:
	if look_value == "pixel":
		return maxi(pixel_look_size_value, 1)
	return pixel_size_value

## Levels per channel the world and the screen pass band colour to; 0 is full colour. COLOUR
## DEPTH when set; otherwise the PIXEL look bands to PIXEL_LOOK_LEVELS (soft, wide steps in the
## sky and haze, as in the reference) and CEL is full. Never dithered.
static func colour_levels(look_value: String, colour_depth_value: int) -> int:
	if colour_depth_value > 0:
		return colour_depth_value
	return PIXEL_LOOK_LEVELS if look_value == "pixel" else 0

## Rendered texels per block side PixelWorld averages. The PIXEL look renders at twice the block
## resolution so blocks shade part-way instead of popping (the shimmer that made it rough on the
## eyes); CEL stays one texel per block so its ink lines stay solid black.
static func pixel_supersample(look_value: String) -> int:
	return PIXEL_LOOK_SUPERSAMPLE if look_value == "pixel" else 1

const PIXEL_LOOK_SUPERSAMPLE := 2
const PIXEL_LOOK_LEVELS := 24

static func keys() -> Array:
	var out: Array = []
	for row: Array in DEFS:
		out.append(row[0])
	return out

# --- the autoload ---------------------------------------------------------------

var window_mode: String:
	get: return _values.get(&"window_mode", "windowed")
var resolution: Vector2i:
	get: return _values.get(&"resolution", Vector2i(1920, 1080))
var vsync: String:
	get: return _values.get(&"vsync", "on")
var max_fps: int:
	get: return _values.get(&"max_fps", 0)
var brightness: float:
	get: return _values.get(&"brightness", 1.0)
var render_scale: float:
	get: return _values.get(&"render_scale", 1.0)
var shadow_quality: String:
	get: return _values.get(&"shadow_quality", "high")
var msaa: String:
	get: return _values.get(&"msaa", "4x")
var pixel_size: int:
	get: return _values.get(&"pixel_size", 0)
var pixel_look_size: int:
	get: return _values.get(&"pixel_look_size", 4)
var colour_depth: int:
	get: return _values.get(&"colour_depth", 0)
var look: String:
	get: return _values.get(&"look", "cel")
var anime_animation: bool:
	get: return _values.get(&"anime_animation", "smooth") == "anime"
var painted_shading: bool:
	get: return _values.get(&"painted_shading", "on") == "on"
var cel_scatter: bool:
	get: return _values.get(&"cel_scatter", "off") == "on"
var mouse_sensitivity: float:
	get: return _values.get(&"mouse_sensitivity", 1.0)
var controller_sensitivity: float:
	get: return _values.get(&"controller_sensitivity", 1.0)
var fov: float:
	get: return _values.get(&"fov", 75.0)
var camera_motion: bool:
	get: return _values.get(&"camera_motion", "on") == "on"
var hologram_menu: bool:
	get: return _values.get(&"hologram_menu", "off") == "on"
var movement_effects: bool:
	get: return _values.get(&"movement_effects", "on") == "on"

func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)
	# A WINDOWED window dragged to a new size keeps its 3D at the chosen resolution.
	get_viewport().size_changed.connect(_update_3d_scale)
	_load()

func get_value(key: StringName) -> Variant:
	return _values.get(key)

## Not named get_index(): that overrides Node's own method of the same name.
func index_for(key: StringName) -> int:
	return index_of(key, get_value(key))

## Applies, persists (debounced) and - for every row but the pixel filter -
## pushes straight to the engine. Called by a row stepping its value and by
## pixel_world.gd's own QA keys, so both ways of changing the filter agree.
func set_value(key: StringName, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply(key, value)
	_save_timer.start(SAVE_DEBOUNCE)

func step_value(key: StringName, direction: int) -> void:
	var new_index := step(key, index_for(key), direction)
	set_value(key, value_at(key, new_index))

func reset_to_defaults() -> void:
	_values = defaults()
	for row: Array in DEFS:
		_apply(row[0], _values[row[0]])
	_save_timer.start(SAVE_DEBOUNCE)

# --- persistence ------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := ERR_FILE_NOT_FOUND if is_test_run() else cfg.load(SAVE_PATH)
	if err != OK:
		# A missing file is not an error, it is a first launch: defaults are
		# used and nothing is written until something changes. A headless run
		# takes this path too - see is_test_run().
		_values = defaults()
	else:
		var raw: Dictionary = {"version": cfg.get_value("meta", "version")}
		for row: Array in DEFS:
			var key: StringName = row[0]
			# Guarded, or a key added since the file was written logs an error on load (a null
			# default counts as no default). Absent keys fall back in sanitise().
			if cfg.has_section_key(String(row[2]), String(key)):
				raw[key] = cfg.get_value(String(row[2]), String(key))
		_values = sanitise(raw)
	for row: Array in DEFS:
		_apply(row[0], _values[row[0]])

func _save() -> void:
	if is_test_run():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CONFIG_VERSION)
	for row: Array in DEFS:
		var key: StringName = row[0]
		cfg.set_value(String(row[2]), String(key), _values[key])
	cfg.save(SAVE_PATH)

# --- the applying half: DisplayServer, RenderingServer, the viewport, the ------
# --- gamma uniform. Deliberately not tested - see What The Test Fences. -------

func _apply(key: StringName, value: Variant) -> void:
	match key:
		&"window_mode", &"resolution", &"render_scale":
			# One apply for all three, from the current values rather than `value`: each depends
			# on the other two, and applying just the one that changed is how the mode and the
			# size drifted apart before.
			_apply_display()
		&"vsync":
			var modes := {
				"off": DisplayServer.VSYNC_DISABLED,
				"on": DisplayServer.VSYNC_ENABLED,
				"adaptive": DisplayServer.VSYNC_ADAPTIVE,
			}
			DisplayServer.window_set_vsync_mode(modes.get(value, DisplayServer.VSYNC_ENABLED))
		&"max_fps":
			Engine.max_fps = value
		&"brightness":
			Brightness.set_gamma(value)
		&"shadow_quality":
			var sizes := {"low": 2048, "medium": 4096, "high": 8192}
			var qualities := {
				"low": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
				"medium": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
				"high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
			}
			RenderingServer.directional_shadow_atlas_set_size(sizes.get(value, 8192), false)
			RenderingServer.directional_soft_shadow_filter_set_quality(
				qualities.get(value, RenderingServer.SHADOW_QUALITY_SOFT_HIGH))
		&"msaa":
			var modes := {
				"off": Viewport.MSAA_DISABLED,
				"2x": Viewport.MSAA_2X,
				"4x": Viewport.MSAA_4X,
				"8x": Viewport.MSAA_8X,
			}
			get_viewport().msaa_3d = modes.get(value, Viewport.MSAA_4X)
		&"painted_shading":
			RenderingServer.global_shader_parameter_set(&"paint_strength", PAINT_STRENGTH_ON if value == "on" else 0.0)
		&"cel_scatter":
			RenderingServer.global_shader_parameter_set(&"scatter_strength", 1.0 if value == "on" else 0.0)
		&"pixel_size", &"pixel_look_size", &"colour_depth", &"look":
			# The rows that do not drive a global - they reach into a PixelWorld
			# that may not exist (the main menu has none) via the group-lookup
			# convention ui-shell.md introduced with &"player". All at once, from
			# the current values: one node draws them all, and LOOK changes the
			# block size and the colour banding as well as the materials.
			var block := effective_pixel_size(pixel_size, pixel_look_size, look)
			var world := get_tree().get_first_node_in_group(&"pixel_world")
			if world:
				world.apply_settings(block, colour_levels(look, colour_depth),
					pixel_supersample(look))
			# The UI and menus get the PIXEL look too, from a pass over the whole screen; CEL
			# keeps them sharp. See docs/specs/pixel-look.md, "Whole screen".
			ScreenPixel.apply_settings(block if look == "pixel" else 0,
				colour_levels(look, colour_depth))
			if key == &"look":
				# The look being left lets go of its materials before the new one swaps them.
				var pixel_look := get_tree().get_first_node_in_group(&"pixel_look")
				var retro_look := get_tree().get_first_node_in_group(&"retro_look")
				if pixel_look and value != "pixel":
					pixel_look.apply_look(false)
				if retro_look and value != "retro":
					retro_look.apply_look(false)
				if pixel_look and value == "pixel":
					pixel_look.apply_look(true)
				if retro_look and value == "retro":
					retro_look.apply_look(true)
		&"mouse_sensitivity", &"controller_sensitivity", &"fov", &"camera_motion", &"hologram_menu", &"movement_effects", &"anime_animation":
			# No global to push to, because every consumer reads these off this
			# autoload at the point of use rather than caching them: both
			# _unhandled_input() handlers and pilot9's
			# _handle_controller_camera() multiply by the sensitivity every
			# frame they turn, and both cameras take their FOV from `fov` the
			# same way - pilot9 through base_fov, which is a property, and mech
			# in _process().
			#
			# That was the claim here before and it was only true of the two
			# sensitivity rows. FOV was captured into a field in pilot9's
			# _ready(), so it saved to disk, survived a relaunch, and did
			# nothing to a pilot who already existed. The fix was to delete the
			# field, not to add a push - see docs/specs/settings.md, FOV
			# Applies Live. Anything added here later must read live or say so.
			pass

## WINDOW MODE, RESOLUTION and RENDER SCALE together - see docs/specs/settings.md, Display
## Modes. Applies on boot too, from the editor as well as an export: what you last picked is
## what the next launch opens in.
func _apply_display() -> void:
	_display_generation += 1
	if is_test_run() or is_embedded():
		# No window to move under --headless, and the editor's Game tab refuses to move or resize
		# its (logging each refusal); the 3D scale is still worth keeping honest.
		get_viewport().scaling_3d_scale = render_scale
		return
	match window_mode:
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_update_3d_scale()
	# Sized and centred a frame later: coming out of fullscreen, Windows restores the old
	# windowed rect after window_set_mode() returns and would overwrite anything set now.
	_settle_window.call_deferred(_display_generation)

func _settle_window(generation: int) -> void:
	await get_tree().process_frame
	if generation != _display_generation:
		return
	if window_mode == "windowed":
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var title_bar := DisplayServer.window_get_size_with_decorations().y 			- DisplayServer.window_get_size().y
		if title_bar <= 0:
			title_bar = FALLBACK_TITLE_BAR
		if window_fits(resolution, usable, title_bar):
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			# window_set_position() places the client area, so the title bar is added back on.
			var outer := resolution + Vector2i(0, title_bar)
			@warning_ignore("integer_division")
			DisplayServer.window_set_position(
				usable.position + (usable.size - outer) / 2 + Vector2i(0, title_bar))
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	# Once more, now the window is the size it is going to be.
	_update_3d_scale()

func _update_3d_scale() -> void:
	get_viewport().scaling_3d_scale = scale_3d(resolution, DisplayServer.window_get_size(), render_scale)
