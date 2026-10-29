extends Node3D

# EXIA's footfall dust. See docs/specs/exia-sprint.md, "Footfall dust".
#
# The same puffs as pilot9's landing dust - Pilot9Vfx.dust_burst - scaled up to a machine: 4x the
# puff, a slower, wider ring. Built in code by mech.gd's _ready(), so a rebuild of mech.tscn
# cannot lose it. mech.gd decides WHEN (a footfall of the run or the sprint, a landing - MOVEMENT
# EFFECTS on) and how big: the run's dust is smaller.

const PUFF_SIZE := 1.8
const COUNT := 10
const LIFE := 0.8
const RADIAL_SPEED := 6.0
const COLOR := Color(0.64, 0.58, 0.5, 0.75)
## Bursts are freed this long after their lifetime, by timer: the dummy renderer never finishes
## a particle system.
const FREE_MARGIN := 0.5
const VISIBILITY := AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 10.0, 16.0))

var _puff: Texture2D = null

func _ready() -> void:
	_puff = Pilot9Vfx._radial([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])

## A dust ring on the floor at `world`, `scale` times the sprint's.
func footfall(world: Vector3, scale: float = 1.0) -> void:
	if _puff == null:
		_puff = Pilot9Vfx._radial([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var p := Pilot9Vfx.dust_burst("Footfall", COUNT, RADIAL_SPEED * scale, LIFE, Vector3.ZERO, 0.0,
		Vector3.ZERO, Vector3.UP, PUFF_SIZE * scale, COLOR, _puff)
	p.visibility_aabb = VISIBILITY
	p.top_level = true
	add_child(p, true)
	p.global_transform = Transform3D(Basis.IDENTITY, world)
	p.emitting = true
	if is_inside_tree():
		get_tree().create_timer(p.lifetime + FREE_MARGIN).timeout.connect(p.queue_free)
