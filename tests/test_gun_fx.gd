extends "res://tests/test_case.gd"

# docs/specs/pilot9-gunplay-pass3.md. The shooting FX: the heat/smoke rule, tracer speed, and that every
# effect cleans itself up. How it looks is tests/_probe_gun_fx.gd and play.

const FX := preload("res://scripts/items/gun_fx.gd")
const DT := 1.0 / 60.0

var _root: Node3D

func _rig() -> Array:
	var loop := Engine.get_main_loop() as SceneTree
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		loop.root.add_child(_root)
	var fx: Node = FX.new()
	_root.add_child(fx)
	var muzzle := Node3D.new()
	_root.add_child(muzzle)
	return [fx, muzzle]

func _run(fx: Node, seconds: float) -> void:
	for i in int(seconds / DT):
		fx._process(DT)

func test_three_quick_rifle_shots_light_the_smoke_but_two_do_not() -> void:
	var r := _rig()
	var fx = r[0]
	var m: Node3D = r[1]
	fx.muzzle_flash(m, false)
	_run(fx, 0.35)
	fx.muzzle_flash(m, false)
	_run(fx, 0.35)
	_run(fx, 0.0)
	check(not fx.is_smoking(), "two shots: no sustained smoke")
	fx.muzzle_flash(m, false)
	fx._process(DT)
	check(fx.is_smoking(), "the third quick shot lights the barrel")
	_run(fx, 5.0)
	check(not fx.is_smoking(), "it stops smoking once the heat drains")
	fx.queue_free()

func test_slow_shots_never_build_smoke() -> void:
	var r := _rig()
	var fx = r[0]
	for i in 6:
		fx.muzzle_flash(r[1], false)
		_run(fx, 2.0)
	check(not fx.is_smoking(), "a shot every 2 s never smokes")
	fx.queue_free()

func test_revolver_smokes_on_its_longer_window() -> void:
	var r := _rig()
	var fx = r[0]
	for i in 3:
		fx.muzzle_flash(r[1], true)
		_run(fx, 0.35)
	fx.muzzle_flash(r[1], true)
	fx._process(DT)
	check(fx.is_smoking(), "revolver at its fire rate smokes within its window")
	fx.queue_free()

func test_tracer_is_a_fast_bullet() -> void:
	check(FX.TRACER_SPEED >= 800.0, "tracer head is bullet fast")
	var r := _rig()
	var fx = r[0]
	fx.tracer(Vector3.ZERO, Vector3(0, 0, -60.0), 1.0)
	_run(fx, 0.1)
	check(fx._tracers.size() == 1, "a 60 m shot has landed by 0.1 s but its trail lingers")
	_run(fx, 0.2)
	check(fx._tracers.is_empty(), "the trail is gone 0.3 s later")
	fx.queue_free()

func test_everything_cleans_itself_up() -> void:
	var r := _rig()
	var fx = r[0]
	for i in 6:
		fx.muzzle_flash(r[1], i % 2 == 0)
	fx.impact(Vector3(0, 0, -5), Vector3.UP, false)
	fx.impact(Vector3(1, 0, -5), Vector3.UP, true)
	check(fx._flash_nodes.size() == 6, "six flashes live")
	_run(fx, 30.0)
	check(fx._flash_nodes.is_empty(), "flashes done")
	check(fx._embers.is_empty(), "embers and sparks done")
	check(fx._anims.is_empty(), "smoke and puffs done")
	fx.queue_free()

func test_sprite_count_is_capped() -> void:
	var r := _rig()
	var fx = r[0]
	for i in 40:
		fx.impact(Vector3(0, 0, -5), Vector3.UP, false)
	check(fx._anims.size() <= FX.MAX_SPRITES, "never more than the sprite cap")
	fx.queue_free()
