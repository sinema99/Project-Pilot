class_name FiringRange
extends Node3D

## The firing range: a flat slab with a training dummy on it. The dummy sleeps until pilot steps
## on, and sleeps again when he leaves. This is the place combat is tested. See
## docs/specs/firing-range.md.
##
## GENERATED, like the pipe hall: every child is added without an `owner`, so trial.tscn stores one
## instanced node and a transform. LOCAL SPACE: the origin is the middle of the slab's walking
## surface (y = 0); the causeway to the rest of the world leaves the +Z edge.
##   F9  reset the stats    F10  fire one bolt now    F11  freeze / unfreeze the dummy

const _Dummy := preload("res://scripts/range/range_dummy.gd")
const _Stats := preload("res://scripts/range/range_stats.gd")
const CEL_BASE := "res://resources/cel_ground.tres"

const HALF := 25.0
const THICKNESS := 1.0
const RIM_HEIGHT := 0.5
const RIM_THICKNESS := 0.6
const CAUSEWAY_LENGTH := 85.0
const CAUSEWAY_WIDTH := 8.0

const C_FLOOR := Color(0.30, 0.32, 0.36)
const C_RIM := Color(0.62, 0.50, 0.14)
const C_MARK := Color(0.85, 0.85, 0.9)
const C_PAD := Color(0.22, 0.45, 0.6)

signal pilot_entered
signal pilot_left

var stats = _Stats.new()
var dummy: AnimatableBody3D = null
var trigger: Area3D = null
var pilot_on_slab := false

var _pilot: Node = null
var _hud_layer: CanvasLayer = null
var _hud: Label = null
var _mats: Dictionary = {}


func _ready() -> void:
	_build_slab()
	_build_dummy()
	_build_trigger()
	_build_hud()


# --- building ---------------------------------------------------------------------------------

func _cel(col: Color) -> Material:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var base := load(CEL_BASE) as ShaderMaterial
	if base == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = col
		_mats[key] = plain
		return plain
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	_mats[key] = m
	return m


## A box with a collider (or without), centred at `pos`.
func _box(name_: String, size: Vector3, pos: Vector3, col: Color, solid: bool) -> Node3D:
	var holder: Node3D
	if solid:
		holder = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		holder.add_child(cs)
	else:
		holder = Node3D.new()
	holder.name = name_
	holder.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _cel(col)
	holder.add_child(mi)
	add_child(holder)
	return holder


func _build_slab() -> void:
	var span := HALF * 2.0
	_box("Slab", Vector3(span, THICKNESS, span), Vector3(0.0, -THICKNESS * 0.5, 0.0), C_FLOOR, true)
	var rim_y := RIM_HEIGHT * 0.5
	var inset := HALF - RIM_THICKNESS * 0.5
	_box("RimNorth", Vector3(span, RIM_HEIGHT, RIM_THICKNESS), Vector3(0.0, rim_y, -inset), C_RIM, true)
	_box("RimWest", Vector3(RIM_THICKNESS, RIM_HEIGHT, span), Vector3(-inset, rim_y, 0.0), C_RIM, true)
	_box("RimEast", Vector3(RIM_THICKNESS, RIM_HEIGHT, span), Vector3(inset, rim_y, 0.0), C_RIM, true)
	# The entrance side, split to leave the causeway's gap.
	var gap := CAUSEWAY_WIDTH * 0.5
	var seg := HALF - gap
	for sign_ in [-1.0, 1.0]:
		_box("RimSouth%s" % ("W" if sign_ < 0.0 else "E"),
			Vector3(seg, RIM_HEIGHT, RIM_THICKNESS),
			Vector3(sign_ * (gap + seg * 0.5), rim_y, inset), C_RIM, true)
	_box("Causeway", Vector3(CAUSEWAY_WIDTH, THICKNESS, CAUSEWAY_LENGTH + 1.0),
		Vector3(0.0, -THICKNESS * 0.5, HALF + CAUSEWAY_LENGTH * 0.5 - 0.5), C_FLOOR, true)
	# Floor markings: a centre cross and the pad pilot enters on. Dressing, no colliders.
	_box("MarkX", Vector3(span - 4.0, 0.02, 0.2), Vector3(0.0, 0.011, 0.0), C_MARK, false)
	_box("MarkZ", Vector3(0.2, 0.02, span - 4.0), Vector3(0.0, 0.011, 0.0), C_MARK, false)
	_box("EntryPad", Vector3(8.0, 0.02, 8.0), Vector3(0.0, 0.012, HALF - 6.0), C_PAD, false)


func _build_dummy() -> void:
	dummy = _Dummy.new()
	dummy.name = &"Dummy"
	dummy.bounds_half = HALF
	add_child(dummy)
	dummy.position = Vector3(0.0, 0.0, -10.0)
	dummy.centre = global_position
	dummy.hit.connect(_on_dummy_hit)


func _build_trigger() -> void:
	trigger = Area3D.new()
	trigger.name = &"Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF * 2.0 - 2.0, 60.0, HALF * 2.0 - 2.0)
	cs.shape = shape
	cs.position = Vector3(0.0, 28.0, 0.0)
	trigger.add_child(cs)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = &"RangeHud"
	_hud_layer.layer = 12
	_hud_layer.visible = false
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.position = Vector2(24.0, 24.0)
	_hud.add_theme_font_size_override(&"font_size", 18)
	_hud.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	_hud.add_theme_constant_override(&"outline_size", 6)
	_hud_layer.add_child(_hud)


# --- waking and sleeping ----------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"reflect_target"):
		enter(body)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"reflect_target"):
		leave()


## Pilot is on the slab: wake the dummy, show the HUD, start listening to him.
func enter(pilot: Node) -> void:
	if pilot_on_slab:
		return
	pilot_on_slab = true
	_pilot = pilot
	if pilot.has_signal(&"hit_taken") and not pilot.hit_taken.is_connected(_on_pilot_hit):
		pilot.hit_taken.connect(_on_pilot_hit)
	var spin = pilot.get("reflect_spin")
	if spin != null and not spin.reflected.is_connected(_on_reflected):
		spin.reflected.connect(_on_reflected)
	dummy.wake()
	_hud_layer.visible = true
	pilot_entered.emit()


## Pilot left: the dummy goes dormant and its bolts are cleared. The totals stay.
func leave() -> void:
	if not pilot_on_slab:
		return
	pilot_on_slab = false
	dummy.frozen = false
	dummy.sleep()
	_hud_layer.visible = false
	pilot_left.emit()


# --- events -----------------------------------------------------------------------------------

func _on_dummy_hit(amount: float, kind: StringName, point: Vector3) -> void:
	stats.record_dummy_hit(amount, _now())
	var perfect := kind == &"reflect_perfect"
	if _pilot != null and _pilot.has_method(&"spark_burst"):
		var out: Vector3 = (_pilot.global_position + Vector3.UP - point).normalized()
		_pilot.spark_burst(point, out, 28 if perfect else 12, 8.0 if perfect else 5.0, Color.WHITE)
	_float_number(point, amount, perfect)


func _on_pilot_hit(_amount: float, _kind: StringName, _point: Vector3) -> void:
	stats.record_pilot_hit()


func _on_reflected(projectile: Node, perfect: bool, _point: Vector3) -> void:
	if projectile.is_in_group(&"range_bolt"):
		stats.record_reflect(perfect)


## A damage number that rises above the hit and fades. "PERFECT" for a perfect reflect.
func _float_number(point: Vector3, amount: float, perfect: bool) -> void:
	var label := Label3D.new()
	label.text = ("PERFECT  %d" if perfect else "%d") % int(round(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0014
	label.font_size = 64 if perfect else 48
	label.modulate = Color(0.4, 1.0, 0.6) if perfect else Color(1.0, 0.95, 0.5)
	label.outline_size = 12
	add_child(label)
	label.global_position = point + Vector3.UP * 0.8
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.8)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)


# --- per frame --------------------------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if _hud_layer != null and _hud_layer.visible:
		_hud.text = hud_text(stats, _now(), dummy.frozen)


func _unhandled_input(event: InputEvent) -> void:
	if not pilot_on_slab or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F9:
			stats.reset()
		KEY_F10:
			dummy.force_fire()
		KEY_F11:
			dummy.frozen = not dummy.frozen


## The HUD's text. Static so a test can read it without a screen.
static func hud_text(s, now: float, frozen: bool) -> String:
	return "FIRING RANGE%s\nDamage dealt   %d\nHits on dummy  %d\nHits taken     %d\nReflects       %d perfect / %d normal\nDPS            %.1f\n[F9] reset   [F10] fire   [F11] freeze" % [
		"  (FROZEN)" if frozen else "", int(s.damage_dealt), s.hits_on_dummy, s.hits_taken,
		s.reflects_perfect, s.reflects_normal, s.dps(now)]
