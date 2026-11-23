class_name VirtualStick
extends Control
## Multi-touch-safe virtual thumbstick for Android pedestrian movement and vehicle steering.
## Drawn with crisp vector circles (no bitmap blur, no emojis) and highlights warm amber at sprint zone.

signal stick_changed(value: Vector2)

@export var max_radius: float = 64.0
@export var horizontal_only: bool = false

var value: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _knob_offset: Vector2 = Vector2.ZERO
var _is_pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed and _touch_index == -1:
			_touch_index = te.index
			_is_pressed = true
			_update_knob(te.position)
			accept_event()
		elif not te.pressed and te.index == _touch_index:
			_reset_stick()
			accept_event()
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _touch_index:
			_update_knob(de.position)
			accept_event()
	elif event is InputEventMouseButton and InputRouter.touch_ui_enabled:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_pressed = true
				_update_knob(mb.position)
			else:
				_reset_stick()
			accept_event()
	elif event is InputEventMouseMotion and _is_pressed and InputRouter.touch_ui_enabled:
		_update_knob((event as InputEventMouseMotion).position)
		accept_event()


func _update_knob(local_pos: Vector2) -> void:
	var center := size * 0.5
	var delta := local_pos - center
	if horizontal_only:
		delta.y = 0.0
	if delta.length() > max_radius:
		delta = delta.normalized() * max_radius
	_knob_offset = delta
	value = delta / max_radius
	stick_changed.emit(value)
	queue_redraw()


func _reset_stick() -> void:
	_touch_index = -1
	_is_pressed = false
	_knob_offset = Vector2.ZERO
	value = Vector2.ZERO
	stick_changed.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var outer_r := max_radius + 14.0
	var bg_col := Color(0.07, 0.09, 0.13, 0.52)
	var border_col := Color(0.95, 0.97, 1.0, 0.34 if not _is_pressed else 0.72)
	draw_circle(center, outer_r, bg_col)
	draw_arc(center, outer_r, 0.0, TAU, 48, border_col, 2.2, true)

	# Subtle crosshair guide ticks
	var tick_col := Color(1.0, 1.0, 1.0, 0.18)
	draw_line(center + Vector2(-outer_r + 8, 0), center + Vector2(-outer_r + 16, 0), tick_col, 1.6, true)
	draw_line(center + Vector2(outer_r - 16, 0), center + Vector2(outer_r - 8, 0), tick_col, 1.6, true)
	if not horizontal_only:
		draw_line(center + Vector2(0, -outer_r + 8), center + Vector2(0, -outer_r + 16), tick_col, 1.6, true)
		draw_line(center + Vector2(0, outer_r - 16), center + Vector2(0, outer_r - 8), tick_col, 1.6, true)

	# Thumb puck (shifts to warm amber in sprint outer zone)
	var sprinting := (not horizontal_only) and value.length() > 0.88
	var puck_col := Color(0.96, 0.62, 0.07, 0.92) if sprinting else Color(0.94, 0.96, 0.98, 0.88 if _is_pressed else 0.68)
	draw_circle(center + _knob_offset, 26.0, puck_col)
	draw_arc(center + _knob_offset, 26.0, 0.0, TAU, 32, Color(0.07, 0.09, 0.13, 0.45), 2.0, true)
