## Debug rig for the reflect spin: a post that throws balls at pilot. Nothing in the real game
## uses this - real enemies just have to meet the contract in reflect_projectile.gd.
##   F7  fire one ball at him.   F8  toggle auto-fire every `interval` seconds.
extends Node3D

const _Projectile := preload("res://scripts/reflect/reflect_projectile.gd")

@export_range(1.0, 60.0, 0.5) var ball_speed: float = 14.0
@export_range(0.5, 20.0, 0.1) var interval: float = 2.5
## Where on him it aims, metres above his feet.
@export var aim_height: float = 1.2
@export var auto_fire: bool = false

var _clock := 0.0


func _ready() -> void:
	# The post the balls come from, so there is something to be reflected back at.
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 2.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	box.material = mat
	post.mesh = box
	post.position = Vector3(0.0, 1.0, 0.0)
	post.name = &"Post"
	add_child(post)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F7:
		fire()
	elif event.physical_keycode == KEY_F8:
		auto_fire = not auto_fire
		_clock = 0.0


func _physics_process(delta: float) -> void:
	if not auto_fire:
		return
	_clock += delta
	if _clock >= interval:
		_clock = 0.0
		fire()


## One ball at the player, from the top of the post. Returns it, or null with no player to aim at.
func fire() -> Node3D:
	var target := _find_target()
	if target == null:
		return null
	var ball := _Projectile.new()
	ball.shooter = self
	get_tree().current_scene.add_child(ball)
	ball.global_position = global_position + Vector3.UP * 2.0
	var aim := target.global_position + Vector3.UP * aim_height - ball.global_position
	ball.velocity = aim.normalized() * ball_speed
	return ball


func _find_target() -> Node3D:
	var players := get_tree().get_nodes_in_group("reflect_target")
	return players[0] as Node3D if not players.is_empty() else null
