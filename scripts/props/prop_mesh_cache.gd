class_name PropMeshCache
extends RefCounted

# Disk cache for hub2's code-built meshes (docs/specs/hub2-load-time.md). Building ~1,300 props and
# 400 pipe runs in code on every start took ~25 s; now each distinct mesh is built once, saved to
# res://assets/hub2_props/<tag>_<hash>.res and loaded from there on every later start.
#
# - Key = tag + the settings that decide the mesh; same settings, same file.
# - Stale-proofing: when the builder scripts change (their md5s are stored in _version.txt) the whole
#   folder is wiped on the next run from the editor, and everything rebuilds once.
# - Saving only happens when a game is run from the editor (not while editing a scene, not in an
#   exported game, which just loads what shipped).
# - Collision boxes ride on the mesh as meta `boxes`.

const DIR := "res://assets/hub2_props"
const VERSION_FILE := DIR + "/_version.txt"
## Scripts whose output is cached: any edit to one throws the cache away.
const SOURCES := [
	"res://scripts/props/prop_kit.gd",
	"res://scripts/props/hub2_prop_build.gd",
	"res://scripts/props/hub2_prop.gd",
	"res://scripts/props/hub2_pipe_run.gd",
	"res://scripts/props/hub2_crane.gd",
	"res://scripts/props/prop_mesh_cache.gd",
	"res://scripts/cargo_container.gd",
	"res://scripts/props/hub2_piece.gd",
	"res://scripts/props/hub2_piece_build.gd",
	"res://scripts/props/hub2_piece_build2.gd",
	"res://scripts/props/hub2_door.gd",
]

static var enabled := true
static var _checked := false
static var _mem: Dictionary = {}
static var _mats: Dictionary = {}
## Counters for tests / probes.
static var hits := 0
static var misses := 0


## {mesh: ArrayMesh, boxes: Array} for `key`; `builder` (no args) makes the same dictionary on a miss.
static func fetch(tag: String, key: Array, builder: Callable) -> Dictionary:
	if not enabled:
		return builder.call()
	var name := "%s_%s" % [tag, str(key).md5_text().substr(0, 20)]
	if _mem.has(name):
		return _mem[name]
	var editor := OS.has_feature("editor")
	if editor and not _checked:
		_check_version()
	var path := "%s/%s.res" % [DIR, name]
	var made: Dictionary
	var loaded: ArrayMesh = null
	if ResourceLoader.exists(path):
		loaded = ResourceLoader.load(path) as ArrayMesh
	if loaded != null:
		hits += 1
		for i in loaded.get_surface_count():
			loaded.surface_set_material(i, _shared(loaded.surface_get_material(i)))
		made = {"mesh": loaded, "boxes": loaded.get_meta(&"boxes", [])}
	else:
		misses += 1
		made = builder.call()
		if editor and not Engine.is_editor_hint():
			_save(made, path)
	_mem[name] = made
	return made


static func _save(made: Dictionary, path: String) -> void:
	var mesh := made["mesh"] as ArrayMesh
	if mesh == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	mesh.set_meta(&"boxes", made.get("boxes", []))
	var err := ResourceSaver.save(mesh, path)
	if err != OK:
		push_warning("PropMeshCache: could not save %s (%s)." % [path, error_string(err)])


## One material instance per distinct look, so thousands of loaded meshes don't mean thousands of materials.
static func _shared(m: Material) -> Material:
	if m == null:
		return null
	var key := material_key(m)
	if key == "":
		return m
	if not _mats.has(key):
		_mats[key] = m
	return _mats[key]


## What makes two materials look the same ("" = not comparable, treat as unique).
static func material_key(m: Material) -> String:
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		return str([&"std", s.albedo_color, s.vertex_color_use_as_albedo, s.shading_mode, s.blend_mode, s.cull_mode,
				s.emission_enabled, s.emission, s.emission_energy_multiplier, s.roughness, s.metallic_specular,
				s.transparency, s.albedo_texture])
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path != "":
		return "sh:" + (m as ShaderMaterial).shader.resource_path
	return ""


static func _check_version() -> void:
	_checked = true
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	for p: String in SOURCES:
		h.update(FileAccess.get_file_as_bytes(p))
	var now := h.finish().hex_encode()
	var old := ""
	if FileAccess.file_exists(VERSION_FILE):
		old = FileAccess.get_file_as_string(VERSION_FILE).strip_edges()
	if old == now:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".res"):
				d.remove(f)
	var w := FileAccess.open(VERSION_FILE, FileAccess.WRITE)
	if w != null:
		w.store_string(now)
