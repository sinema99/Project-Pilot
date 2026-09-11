class_name InteractionPrompt
extends CanvasLayer

# The one prompt row every InteractButton in the scene shares. See docs/specs/button-door.md.
#
# It is shared rather than per-button for one reason: a CanvasLayer inside each button's wrapper
# pastes perfectly and then draws two CenterContainers at the identical screen position the
# moment two buttons are in range at once - a door with a switch on each side, which is the
# second thing anybody builds with this.
#
# Found by group, and INSTANTIATED BY THE FIRST BUTTON THAT LOOKS FOR ONE - see acquire(). That
# is what lets a door be pasted into a scene that has never heard of this file. It is added
# WITHOUT an `owner`, exactly like the blockout boxes' generated geometry, so nothing reaches
# the .tscn and nothing can accumulate.
#
# Buttons do not show and hide it; they BID. Each offers itself with a distance every physics
# frame it is in range, this commits the closest one, and `current_source` is the answer to
# "am I the button being pointed at" that a button checks before acting on a keypress. Without
# that, `interact` with two buttons in range fires both.

## Set on the root node in the .tscn as well - both halves have to agree or acquire() builds a
## second prompt every time it is called.
const GROUP := &"interaction_prompt"

const SCENE_PATH := "res://scenes/ui/interaction_prompt.tscn"

## Shown when an action has no key bound at all, which is a misconfigured InputMap rather than
## a state the game can be in.
const NO_KEY := "?"


## The button the prompt is currently offering, or null. Read by InteractButton before it acts
## on a press: exactly one button responds however many are in range.
var current_source: Node = null

# This frame's best bid, cleared on every commit. Buttons bid in _physics_process at the
# default priority and this commits at 100, so every bid is in before it is read.
var _best_source: Node = null
var _best_distance := 0.0
var _best_action: StringName = &""
var _best_text := ""

@onready var _row: Control = $Prompt
@onready var _key_label: Label = $Prompt/Row/Key/KeyLabel
@onready var _text_label: Label = $Prompt/Row/Text


func _ready() -> void:
	# Higher runs later. The bids come in at the default 0, so this has to be above it or the
	# prompt commits a frame-old winner and lags a metre behind the player.
	process_physics_priority = 100
	set_physics_process(true)
	_row.visible = false


## The prompt for `context`'s scene, building one if there is none. Returns null only when
## there is no tree to build into, which is a headless caller outside the scene tree.
##
## Static, and reached through a preload rather than by class name - see button-door.md on why
## nothing in this project references a global class across files.
static func acquire(context: Node) -> Node:
	var tree := context.get_tree() if context != null else null
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found != null:
		return found
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_warning("InteractionPrompt: %s is missing - no prompt will be drawn." % SCENE_PATH)
		return null
	var made := packed.instantiate()
	# The current scene rather than the viewport root, so reloading the scene takes the prompt
	# with it. No owner is set: this is generated, and generated things stay out of the .tscn.
	var host: Node = tree.current_scene
	if host == null:
		host = tree.root
	host.add_child(made)
	return made


## A button's bid to be the one shown, `distance` metres from the player. Closest wins.
func offer(source: Node, distance: float, action: StringName, text: String) -> void:
	if _best_source != null and distance >= _best_distance:
		return
	_best_source = source
	_best_distance = distance
	_best_action = action
	_best_text = text


## Drops the prompt this instant rather than waiting for the next commit. What a button calls
## as it goes spent, so the row does not survive a frame past the press that killed it.
func clear_now() -> void:
	_best_source = null
	current_source = null
	if _row != null:
		_row.visible = false


func _physics_process(_delta: float) -> void:
	commit()


## Renders this frame's winner and resets the bidding. Separated from _physics_process so a
## test can step it without a physics server.
func commit() -> void:
	current_source = _best_source
	_best_source = null
	if _row == null:
		return
	if current_source == null:
		_row.visible = false
		return
	_key_label.text = key_label_for(_best_action)
	_text_label.text = _best_text
	_row.visible = true


## The keycap's text for an action, read off the InputMap rather than hardcoded, so rebinding
## `interact` cannot leave the cap lying. First key event wins; pad events have no cap.
static func key_label_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return NO_KEY
	for ev in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key == null:
			continue
		# Physical first: that is how `interact` is bound, and it is the one that survives a
		# non-QWERTY layout.
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	return NO_KEY
