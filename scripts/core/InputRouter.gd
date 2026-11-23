extends Node
## Unified input router for Android multitouch controls and PC keyboard/mouse.

signal interact_pressed
signal screenshot_requested
signal touch_ui_toggled(enabled: bool)

var is_mobile_platform: bool = false
var touch_ui_enabled: bool = false

# Touch state written by HUD controls
var touch_move_vector: Vector2 = Vector2.ZERO
var touch_sprint_held: bool = false
var touch_jump_queued: bool = false
var touch_gas_held: bool = false
var touch_brake_held: bool = false
var touch_steer_left: bool = false
var touch_steer_right: bool = false
var touch_steer_axis: float = 0.0

# Shared camera look delta (accumulated per frame, consumed by SpringCameraRig)
var _look_delta: Vector2 = Vector2.ZERO
var _mouse_captured: bool = false
var _camera_touch_id: int = -1

const MOUSE_SENSITIVITY := 0.0028
const TOUCH_LOOK_SENSITIVITY := 0.0046


func _ready() -> void:
	is_mobile_platform = OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")
	touch_ui_enabled = is_mobile_platform
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	# Auto-enable touch HUD on first real screen touch
	if event is InputEventScreenTouch:
		if not touch_ui_enabled:
			set_touch_ui_enabled(true)
		var te := event as InputEventScreenTouch
		var viewport_w := get_viewport().get_visible_rect().size.x
		if te.pressed:
			# Right half of screen controls camera drag when not intercepted by UI buttons
			if te.position.x >= viewport_w * 0.42 and _camera_touch_id == -1:
				_camera_touch_id = te.index
		else:
			if te.index == _camera_touch_id:
				_camera_touch_id = -1
		return

	if event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _camera_touch_id:
			_look_delta += de.relative * TOUCH_LOOK_SENSITIVITY
		return

	# PC Mouse look capture & release
	if event is InputEventMouseButton and not touch_ui_enabled:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mouse_captured = true
		return

	if event is InputEventMouseMotion and _mouse_captured and not touch_ui_enabled:
		var mm := event as InputEventMouseMotion
		_look_delta += mm.relative * MOUSE_SENSITIVITY
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
			return
		if event.is_action_pressed("interact"):
			interact_pressed.emit()
		elif event.is_action_pressed("capture_screenshot"):
			screenshot_requested.emit()
		elif event.is_action_pressed("toggle_touch_preview"):
			set_touch_ui_enabled(not touch_ui_enabled)


func set_touch_ui_enabled(enabled: bool) -> void:
	if touch_ui_enabled == enabled:
		return
	touch_ui_enabled = enabled
	if touch_ui_enabled and _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false
	touch_ui_toggled.emit(touch_ui_enabled)


func trigger_interact() -> void:
	interact_pressed.emit()


func trigger_screenshot() -> void:
	screenshot_requested.emit()


func queue_touch_jump() -> void:
	touch_jump_queued = true


func consume_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func get_foot_move_vector() -> Vector2:
	var kb := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	var combined := kb + touch_move_vector
	if combined.length() > 1.0:
		combined = combined.normalized()
	return combined


func is_sprint_pressed() -> bool:
	return Input.is_action_pressed("sprint") or touch_sprint_held or touch_move_vector.length() > 0.88


func consume_jump_pressed() -> bool:
	var kb_jump := Input.is_action_just_pressed("jump")
	var t_jump := touch_jump_queued
	touch_jump_queued = false
	return kb_jump or t_jump


func get_vehicle_throttle() -> float:
	var kb := Input.get_action_strength("move_forward")
	var t := 1.0 if touch_gas_held else 0.0
	return clampf(maxf(kb, t), 0.0, 1.0)


func get_vehicle_brake_reverse() -> float:
	var kb := maxf(Input.get_action_strength("move_backward"), Input.get_action_strength("jump"))
	var t := 1.0 if touch_brake_held else 0.0
	return clampf(maxf(kb, t), 0.0, 1.0)


func get_vehicle_handbrake() -> bool:
	return Input.is_action_pressed("jump")


func get_vehicle_steer() -> float:
	# Positive = steer left (+Y yaw), Negative = steer right (-Y yaw)
	var kb := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var btn := (1.0 if touch_steer_left else 0.0) - (1.0 if touch_steer_right else 0.0)
	var stick := -touch_steer_axis
	return clampf(kb + btn + stick, -1.0, 1.0)


func reset_touch_driving_inputs() -> void:
	touch_gas_held = false
	touch_brake_held = false
	touch_steer_left = false
	touch_steer_right = false
	touch_steer_axis = 0.0


func reset_touch_foot_inputs() -> void:
	touch_move_vector = Vector2.ZERO
	touch_sprint_held = false
	touch_jump_queued = false
