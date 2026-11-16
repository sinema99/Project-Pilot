## One gun's numbers. A HeldItem that carries one is a gun: scripts/items/gunplay.gd reads it and
## nothing else, so tuning a gun later is editing a .tres, never code. See
## docs/specs/pilot9-gunplay.md.
class_name GunDef
extends Resource

## Shown above the ammo count.
@export var display_name: String = "GUN"
## Reported to take_hit() on whatever the shot lands on.
@export_range(0.0, 500.0, 1.0, "or_greater") var damage: float = 25.0
## Rounds in a full magazine.
@export_range(1, 200, 1, "or_greater") var magazine: int = 6
## Seconds between shots. Both guns are single fire: one click, one shot, never faster than this.
@export_range(0.05, 3.0, 0.01, "or_greater") var fire_interval: float = 0.35
## Seconds a reload from empty takes.
@export_range(0.1, 10.0, 0.05, "or_greater") var reload_time: float = 2.0
## How much narrower the lens gets at full aim: 0.1 is 10% off the field of view.
@export_range(0.0, 0.6, 0.01) var aim_fov_cut: float = 0.1
## Metres the ray reaches.
@export_range(10.0, 1000.0, 1.0, "or_greater") var range_m: float = 200.0
## A reload with rounds still in the mag takes this fraction of reload_time.
@export_range(0.3, 1.0, 0.05) var tactical_scale: float = 0.8
## Camera kick per shot, degrees up. The recoil: `recoil_keep` of it stays until the player pulls down.
@export_range(0.0, 10.0, 0.05) var recoil_pitch_deg: float = 2.2
## Random sideways kick per shot, +- degrees.
@export_range(0.0, 3.0, 0.05) var recoil_yaw_deg: float = 0.35
## The fraction of the kick that does NOT come back by itself.
@export_range(0.0, 1.0, 0.05) var recoil_keep: float = 0.3
## Seconds the recoverable part takes to come back.
@export_range(0.05, 2.0, 0.05) var recoil_recover_time: float = 0.4
## Bloom (cone half-angle, degrees) added per shot, and removed per second.
@export_range(0.0, 3.0, 0.05) var bloom_per_shot: float = 0.35
@export_range(0.1, 10.0, 0.1) var bloom_decay: float = 1.2
## Cone half-angle at rest, aimed and hip, and the ceiling bloom can reach.
@export_range(0.0, 5.0, 0.05) var spread_aim_deg: float = 0.1
@export_range(0.0, 8.0, 0.05) var spread_hip_deg: float = 1.2
@export_range(0.5, 10.0, 0.1) var bloom_max_deg: float = 3.5
## Hip-fire kicks this much harder than aimed fire.
@export_range(1.0, 3.0, 0.05) var hip_kick_scale: float = 1.6
## Camera shake per shot (degrees of roll at the peak).
@export_range(0.0, 3.0, 0.05) var shake_deg: float = 1.0
## Spent casings fly out of the ejection port as it fires (the rifle). The revolver keeps its
## brass until the reload.
@export var ejects_casings: bool = false
