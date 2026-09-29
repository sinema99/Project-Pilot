extends Control

# The frame every menu screen sits in: a fixed 1280 x 800 window with a header (title, optional
# tab strip), a rule, a scrolling middle and a hint bar. It never grows with its content - only
# `Scroll` does - which is the whole fix for "the scale is off and I cannot tab back": the old
# shell let its content push the header and footer out of shape. See docs/specs/menu-refresh.md,
# "The window".
#
# It owns presentation only. What the tabs are, which one is active and what the bodies do stay
# with the host (shell.gd, settings_screen.gd); the window reports clicks and draws the answer.

signal tab_selected(index: int)
## The close fade finished; the host may hide itself.
signal dismissed

const MenuRow := preload("res://scripts/ui/menu_row.gd")

const WINDOW_SIZE := Vector2(1280, 800)
const OPEN_TIME := 0.14
const OPEN_FROM_SCALE := 0.97
const CLOSE_TIME := 0.10
const UNDERLINE_TIME := 0.12
const SLIDE_TIME := 0.12
const SLIDE_DISTANCE := 16.0
const SLIDE_BASE := 16.0
const SCROLL_LEAD := 48.0
const SCROLL_TIME := 0.08

@onready var _title: Label = $Margin/Column/Header/Title
@onready var _tab_area: Control = $Margin/Column/Header/TabArea
@onready var _strip: HBoxContainer = $Margin/Column/Header/TabArea/Strip
@onready var _underline: ColorRect = $Margin/Column/Header/TabArea/Underline
@onready var _scroll: ScrollContainer = $Margin/Column/Scroll
@onready var _slide: MarginContainer = $Margin/Column/Scroll/Slide
@onready var _footer: HBoxContainer = $Margin/Column/Footer
@onready var _veil: Control = $Veil

var _tabs: Array[Button] = []
var _active_tab := -1
var _underline_tween: Tween
var _slide_tween: Tween
var _scroll_tween: Tween
var _fade_tween: Tween

func _ready() -> void:
	_strip.sort_children.connect(_place_underline)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	# A thin bar, drawn only when the content is taller than the view (ScrollContainer hides it
	# otherwise).
	_scroll.get_v_scroll_bar().custom_minimum_size.x = 4.0

# --- content -------------------------------------------------------------------

func set_title(text: String) -> void:
	_title.text = text

## Where a host parents its body scenes. Everything in here scrolls.
func content_root() -> Control:
	return _slide

func scroll() -> ScrollContainer:
	return _scroll

func set_hints(hints: Array) -> void:
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	for hint: Dictionary in hints:
		_footer.add_child(_build_hint(hint["key"], hint["label"]))

func _build_hint(key: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(make_keycap(key, &"HintKey"))
	var text := Label.new()
	text.theme_type_variation = &"HintLabel"
	text.text = label
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	return row

static func make_keycap(key: String, variation: StringName) -> Control:
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"Keycap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = key
	cap.add_child(label)
	return cap

# --- tabs ----------------------------------------------------------------------

## Q and E keycaps at the two ends, one MenuTab per label between them.
func set_tabs(labels: Array) -> void:
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	_tabs.clear()
	_strip.add_child(make_keycap("Q", &"HintKey"))
	for i in labels.size():
		var tab := MenuRow.new()
		tab.tab_mode = true
		tab.text = labels[i]
		tab.pressed.connect(func() -> void: tab_selected.emit(i))
		_strip.add_child(tab)
		_tabs.append(tab)
	_strip.add_child(make_keycap("E", &"HintKey"))
	_tab_area.visible = true
	_tab_area.custom_minimum_size = _strip.get_combined_minimum_size()
	_active_tab = -1

func tab_buttons() -> Array[Button]:
	return _tabs

## Marks `index` active and slides the underline to it. `animate` is false for the first placement.
func set_active_tab(index: int, animate := true) -> void:
	_active_tab = index
	for i in _tabs.size():
		_tabs[i].active = i == index
	_move_underline(animate)

func _tab_underline_rect(index: int) -> Rect2:
	var tab := _tabs[index]
	# The underline spans the label, not the button's padding.
	var pad := float(tab.get_theme_stylebox(&"normal").get_margin(SIDE_LEFT))
	return Rect2(_strip.position.x + tab.position.x + pad, _strip.position.y + tab.size.y - 4.0,
		maxf(tab.size.x - pad * 2.0, 0.0), 2.0)

func _move_underline(animate: bool) -> void:
	if _active_tab < 0 or _active_tab >= _tabs.size() or _tabs[_active_tab].size.x <= 0.0:
		return
	var rect := _tab_underline_rect(_active_tab)
	if _underline_tween != null:
		_underline_tween.kill()
	if not animate or _underline.size.x <= 0.0:
		_underline.position = rect.position
		_underline.size = rect.size
		return
	_underline_tween = _tween()
	_underline_tween.set_parallel(true)
	_underline_tween.tween_property(_underline, "position", rect.position, UNDERLINE_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_underline_tween.tween_property(_underline, "size", rect.size, UNDERLINE_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# The strip finished a layout pass: snap the underline to the active tab unless it is mid-slide.
func _place_underline() -> void:
	if _underline_tween != null and _underline_tween.is_running():
		return
	_move_underline(false)

## The bodies slide in `direction` (+1 = moved toward the right: content arrives from the right,
## -1 = from the left) and fade up. 0 is a plain fade.
func play_tab_switch(direction: int) -> void:
	if _slide_tween != null:
		_slide_tween.kill()
	var left := SLIDE_BASE + SLIDE_DISTANCE * float(maxi(direction, 0))
	var right := SLIDE_BASE + SLIDE_DISTANCE * float(maxi(-direction, 0))
	_set_slide_margins(0.0, left, right)
	_slide.modulate.a = 0.0
	_slide_tween = _tween()
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(_slide, "modulate:a", 1.0, SLIDE_TIME)
	_slide_tween.tween_method(_set_slide_margins.bind(left, right), 0.0, 1.0, SLIDE_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_slide_margins(t: float, left: float, right: float) -> void:
	_slide.add_theme_constant_override("margin_left", roundi(lerpf(left, SLIDE_BASE, t)))
	_slide.add_theme_constant_override("margin_right", roundi(lerpf(right, SLIDE_BASE, t)))

# --- scrolling -----------------------------------------------------------------

func scroll_position() -> int:
	return _scroll.scroll_vertical

func set_scroll_position(value: int) -> void:
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll.scroll_vertical = value

func _on_focus_changed(node: Control) -> void:
	if node == null or not is_ancestor_of(node) or not _scroll.is_ancestor_of(node):
		return
	# A row lit by the pointer is already under the pointer; scrolling to reveal it would move it
	# out from under the cursor and light its neighbour, which scrolls again.
	if MenuRow.last_hover_frame == Engine.get_process_frames():
		return
	_reveal.call_deferred(node)

## Where the scroll should go so a row spanning `top`..`bottom` (content coordinates) is inside a
## `view` tall window with SCROLL_LEAD to spare, moving as little as possible.
static func scroll_target(top: float, bottom: float, current: float, view: float,
		content_height: float) -> float:
	var target := current
	if top - SCROLL_LEAD < current:
		target = top - SCROLL_LEAD
	elif bottom + SCROLL_LEAD > current + view:
		target = bottom + SCROLL_LEAD - view
	return clampf(target, 0.0, maxf(content_height - view, 0.0))

## Scrolls the least amount that leaves `node` inside the view with SCROLL_LEAD to spare.
func _reveal(node: Control) -> void:
	if not is_instance_valid(node) or not _scroll.is_ancestor_of(node):
		return
	var top := 0.0
	var walker: Control = node
	while walker != null and walker != _slide:
		top += walker.position.y
		walker = walker.get_parent() as Control
	var current := float(_scroll.scroll_vertical)
	var target := scroll_target(top, top + node.size.y, current, _scroll.size.y, _slide.size.y)
	if is_equal_approx(target, current):
		return
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = _tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", roundi(target), SCROLL_TIME)

# --- presenting ----------------------------------------------------------------

func in_hologram() -> bool:
	return get_viewport() is SubViewport

## The flat open: fade in and scale 97 -> 100 %. Input is live immediately. In the hologram the
## panel's reveal wipe is the open, so the window just appears.
func present() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	process_mode = Node.PROCESS_MODE_INHERIT
	if in_hologram():
		modulate.a = 1.0
		scale = Vector2.ONE
		return
	modulate.a = 0.0
	scale = Vector2(OPEN_FROM_SCALE, OPEN_FROM_SCALE)
	_fade_tween = _tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 1.0, OPEN_TIME).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "scale", Vector2.ONE, OPEN_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## The flat close. Input goes dead at once (the game is already running underneath); the window
## fades over CLOSE_TIME and `dismissed` says it may be hidden.
func dismiss() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()
	process_mode = Node.PROCESS_MODE_DISABLED
	_fade_tween = _tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	_fade_tween.tween_callback(dismissed.emit)

## A confirm dialog is over this window: dim it a further ~30 %.
func set_behind_dialog(on: bool) -> void:
	_veil.visible = on

func _tween() -> Tween:
	var tween := create_tween()
	# The tree is paused while a menu is up; these must run anyway, and must not care whether the
	# window itself is disabled mid-fade.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween
