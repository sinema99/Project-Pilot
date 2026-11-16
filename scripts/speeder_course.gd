extends Node3D

# The speeder test course (docs/specs/speeder1-pass4-driving.md, decision 7). Code-built under the
# node it is attached to, on its own slab (top at y = 0), so it cannot fight whatever else is in
# trial. Runs along +Z from the node's origin; Speeder2 waits at the start facing down it.
#
#   z   0..  60  a straight to get up to speed
#   z  70        two ramps side by side: 10 deg x 10 m (left) and 15 deg x 20 m (right)
#   z 120..200   a hill: 6 deg up 40 m, 6 deg down 40 m
#   z 215, 240   a slalom: staggered walls, one from each side
#   z 270..330   a scrape corridor (two long walls) ending in a head-on wall at z 340
#
# Every box is a BlockoutBox (the teal metre grid), so distances read against the jump grid.

const SLAB_SIZE := Vector3(240.0, 2.0, 420.0)
const SLAB_Z0 := -40.0
const SPEEDER_SCENE := preload("res://scenes/speeder.tscn")
const STASH_KEY := &"speeder_course"

## [x, z0 (low end), length, rise degrees, width, yaw degrees]
const RAMPS := [
	[-14.0, 70.0, 10.0, 10.0, 8.0, 0.0],
	[14.0, 70.0, 20.0, 15.0, 8.0, 0.0],
	[0.0, 120.0, 40.0, 6.0, 30.0, 0.0],
	[0.0, 200.0, 40.0, 6.0, 30.0, 180.0],
]
## [x, z, size x, size y, size z]
const WALLS := [
	[-12.0, 215.0, 20.0, 4.0, 1.0],
	[12.0, 240.0, 20.0, 4.0, 1.0],
	[-13.0, 300.0, 1.0, 5.0, 60.0],
	[13.0, 300.0, 1.0, 5.0, 60.0],
	[0.0, 340.0, 40.0, 5.0, 1.0],
]

var speeder: Node3D = null


func _ready() -> void:
	_box(Vector3(0.0, -SLAB_SIZE.y, SLAB_Z0 + SLAB_SIZE.z * 0.5), SLAB_SIZE, 0.0, Color(0.16, 0.2, 0.24))
	for r: Array in RAMPS:
		_ramp(float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4]), float(r[5]))
	for w: Array in WALLS:
		_box(Vector3(float(w[0]), 0.0, float(w[1])), Vector3(float(w[2]), float(w[3]), float(w[4])), 0.0)
	speeder = SPEEDER_SCENE.instantiate()
	speeder.name = &"Speeder2"
	speeder.stash_key = STASH_KEY
	speeder.position = Vector3(0.0, 0.45, 0.0)
	add_child(speeder)


## A wedge from a rotated box, its low end's top edge at ground level. `rise_deg` > 0 climbs along
## +Z (yawed by `yaw_deg`).
func _ramp(x: float, z0: float, length: float, rise_deg: float, width: float, yaw_deg: float) -> void:
	var a := deg_to_rad(rise_deg)
	var t := 0.5
	var origin := Vector3(x, 0.0, 0.0)
	origin.y = -t * cos(a) + length * 0.5 * sin(a)
	var local_z := length * 0.5 * cos(a) + t * sin(a)
	var yaw := deg_to_rad(yaw_deg)
	var around := Basis(Vector3.UP, yaw)
	origin = Vector3(x, 0.0, z0) + around * Vector3(0.0, 0.0, local_z) + Vector3(0.0, origin.y, 0.0)
	var box := _box(origin, Vector3(width, t, length), 0.0)
	box.basis = around * Basis(Vector3.RIGHT, -a)


func _box(at: Vector3, size: Vector3, yaw_deg: float, tint := Color(0.24, 0.62, 0.58)) -> BlockoutBox:
	var b := BlockoutBox.new()
	b.size = size
	b.tint = tint
	b.show_size_label = false
	b.position = at
	b.rotation.y = deg_to_rad(yaw_deg)
	add_child(b)
	return b
