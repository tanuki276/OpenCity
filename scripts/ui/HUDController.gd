class_name HUDController
extends CanvasLayer
## Unified Android Touch & PC HUD adhering strictly to docs/quality-standard.md §7:
## - Zero emojis anywhere (unified line-art SVG vector icons only)
## - Single consistent font family & structured spacing
## - Smooth Tween easing on every mode transition, prompt reveal, and button press

var _driving_mode: bool = false
var _enter_visible: bool = false
var _font: Font

var _foot_layer: Control
var _drive_layer: Control
var _enter_btn: Button
var _exit_btn: Button
var _speed_panel: PanelContainer
var _speed_value_label: Label
var _pc_hints_panel: PanelContainer
var _pc_hints_label: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _screenshot_btn: Button
var _foot_stick: VirtualStick
var _drive_stick: VirtualStick
var _mode_tween: Tween
var _enter_tween: Tween
var _toast_tween: Tween


func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/ui_sans.ttf"):
		_font = load("res://assets/fonts/ui_sans.ttf") as Font
	_build_hud()
	InputRouter.touch_ui_toggled.connect(_on_touch_ui_toggled)
	_apply_input_visibility()


func _make_panel_style(bg: Color, border: Color, radius: int = 12, pad_x: int = 14, pad_y: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


func _style_button(btn: Button, icon_path: String, accent: bool = false, radius: int = 16) -> void:
	var bg := Color(0.92, 0.56, 0.06, 0.90) if accent else Color(0.08, 0.11, 0.16, 0.72)
	var bg_hover := Color(0.98, 0.65, 0.12, 0.96) if accent else Color(0.13, 0.17, 0.24, 0.84)
	var bg_press := Color(0.78, 0.44, 0.04, 0.98) if accent else Color(0.18, 0.23, 0.32, 0.92)
	var border := Color(1.0, 0.85, 0.55, 0.85) if accent else Color(0.92, 0.95, 1.0, 0.32)

	btn.add_theme_stylebox_override("normal", _make_panel_style(bg, border, radius, 12, 10))
	btn.add_theme_stylebox_override("hover", _make_panel_style(bg_hover, border, radius, 12, 10))
	btn.add_theme_stylebox_override("pressed", _make_panel_style(bg_press, border, radius, 12, 10))
	btn.add_theme_stylebox_override("focus", _make_panel_style(bg, border, radius, 12, 10))
	btn.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = false

	if icon_path != "" and ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path) as Texture2D

	# Tactile short easing press animation (Quality Standard §7)
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.button_down.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(btn, "scale", Vector2(0.92, 0.92), 0.08)
	)
	btn.button_up.connect(func() -> void:
		var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.14)
	)


func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Top-Left Minimal Speedometer (Visible in Driving Mode) ---
	_speed_panel = PanelContainer.new()
	_speed_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.07, 0.09, 0.13, 0.78), Color(0.95, 0.97, 1.0, 0.24), 12, 18, 10)
	)
	_speed_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speed_panel.position = Vector2(24, 24)
	_speed_panel.modulate.a = 0.0
	_speed_panel.visible = false
	root.add_child(_speed_panel)

	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 10)
	_speed_panel.add_child(speed_hbox)

	var wheel_icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/icons/ic_steering_wheel.svg"):
		wheel_icon.texture = load("res://assets/icons/ic_steering_wheel.svg") as Texture2D
	wheel_icon.custom_minimum_size = Vector2(24, 24)
	wheel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wheel_icon.modulate = Color(0.96, 0.62, 0.07)
	speed_hbox.add_child(wheel_icon)

	_speed_value_label = Label.new()
	_speed_value_label.text = "0"
	if _font != null:
		_speed_value_label.add_theme_font_override("font", _font)
	_speed_value_label.add_theme_font_size_override("font_size", 28)
	_speed_value_label.add_theme_color_override("font_color", Color.WHITE)
	speed_hbox.add_child(_speed_value_label)

	var unit_lbl := Label.new()
	unit_lbl.text = "KM/H"
	if _font != null:
		unit_lbl.add_theme_font_override("font", _font)
	unit_lbl.add_theme_font_size_override("font_size", 12)
	unit_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	unit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	speed_hbox.add_child(unit_lbl)

	# --- Top-Right Utility Controls (Screenshot Capture & Exit Vehicle) ---
	var top_right := HBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -210
	top_right.offset_top = 24
	top_right.offset_right = -24
	top_right.offset_bottom = 76
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 12)
	root.add_child(top_right)

	_exit_btn = Button.new()
	_exit_btn.text = "EXIT"
	_exit_btn.custom_minimum_size = Vector2(104, 48)
	_style_button(_exit_btn, "res://assets/icons/ic_exit_car.svg", true, 12)
	_exit_btn.visible = false
	_exit_btn.pressed.connect(func() -> void: InputRouter.trigger_interact())
	top_right.add_child(_exit_btn)

	_screenshot_btn = Button.new()
	_screenshot_btn.custom_minimum_size = Vector2(48, 48)
	_screenshot_btn.tooltip_text = "Capture street-level screenshot (F12)"
	_style_button(_screenshot_btn, "res://assets/icons/ic_screenshot.svg", false, 12)
	_screenshot_btn.pressed.connect(func() -> void: InputRouter.trigger_screenshot())
	top_right.add_child(_screenshot_btn)

	# --- Center-Bottom Enter Car Proximity Prompt (Works on both Android Touch & PC) ---
	_enter_btn = Button.new()
	_enter_btn.text = "DRIVE  [F]"
	_enter_btn.custom_minimum_size = Vector2(168, 52)
	_style_button(_enter_btn, "res://assets/icons/ic_enter_car.svg", true, 14)
	_enter_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_enter_btn.offset_left = -84
	_enter_btn.offset_right = 84
	_enter_btn.offset_top = -124
	_enter_btn.offset_bottom = -72
	_enter_btn.visible = false
	_enter_btn.modulate.a = 0.0
	_enter_btn.pressed.connect(func() -> void: InputRouter.trigger_interact())
	root.add_child(_enter_btn)

	# --- PC Subtle Control Hint Strip (Hidden when Touch UI is active) ---
	_pc_hints_panel = PanelContainer.new()
	_pc_hints_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.07, 0.09, 0.13, 0.62), Color(1.0, 1.0, 1.0, 0.16), 10, 14, 7)
	)
	_pc_hints_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pc_hints_panel.offset_left = 24
	_pc_hints_panel.offset_bottom = -20
	_pc_hints_panel.offset_top = -54
	_pc_hints_panel.offset_right = 560
	root.add_child(_pc_hints_panel)

	_pc_hints_label = Label.new()
	if _font != null:
		_pc_hints_label.add_theme_font_override("font", _font)
	_pc_hints_label.add_theme_font_size_override("font_size", 12)
	_pc_hints_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.95))
	_pc_hints_panel.add_child(_pc_hints_label)
	_update_pc_hints()

	# --- Android Touch Layer: ON FOOT ---
	_foot_layer = Control.new()
	_foot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_foot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_foot_layer)

	_foot_stick = VirtualStick.new()
	_foot_stick.custom_minimum_size = Vector2(180, 180)
	_foot_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_foot_stick.offset_left = 36
	_foot_stick.offset_right = 216
	_foot_stick.offset_top = -216
	_foot_stick.offset_bottom = -36
	_foot_stick.stick_changed.connect(func(v: Vector2) -> void: InputRouter.touch_move_vector = v)
	_foot_layer.add_child(_foot_stick)

	var foot_actions := HBoxContainer.new()
	foot_actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot_actions.offset_left = -212
	foot_actions.offset_right = -36
	foot_actions.offset_top = -124
	foot_actions.offset_bottom = -44
	foot_actions.add_theme_constant_override("separation", 16)
	_foot_layer.add_child(foot_actions)

	var sprint_btn := Button.new()
	sprint_btn.text = "RUN"
	sprint_btn.custom_minimum_size = Vector2(78, 78)
	_style_button(sprint_btn, "res://assets/icons/ic_sprint.svg", false, 39)
	sprint_btn.button_down.connect(func() -> void: InputRouter.touch_sprint_held = true)
	sprint_btn.button_up.connect(func() -> void: InputRouter.touch_sprint_held = false)
	foot_actions.add_child(sprint_btn)

	var jump_btn := Button.new()
	jump_btn.text = "JUMP"
	jump_btn.custom_minimum_size = Vector2(78, 78)
	_style_button(jump_btn, "res://assets/icons/ic_jump.svg", false, 39)
	jump_btn.button_down.connect(func() -> void: InputRouter.queue_touch_jump())
	foot_actions.add_child(jump_btn)

	# --- Android Touch Layer: DRIVING ---
	_drive_layer = Control.new()
	_drive_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drive_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive_layer.visible = false
	_drive_layer.modulate.a = 0.0
	root.add_child(_drive_layer)

	# Left Steering Stick (horizontal thumbstick + ergonomic left/right feel)
	_drive_stick = VirtualStick.new()
	_drive_stick.horizontal_only = true
	_drive_stick.max_radius = 68.0
	_drive_stick.custom_minimum_size = Vector2(200, 140)
	_drive_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_drive_stick.offset_left = 34
	_drive_stick.offset_right = 234
	_drive_stick.offset_top = -182
	_drive_stick.offset_bottom = -42
	_drive_stick.stick_changed.connect(func(v: Vector2) -> void: InputRouter.touch_steer_axis = v.x)
	_drive_layer.add_child(_drive_stick)

	# Right Gas & Brake Pedals
	var pedals := HBoxContainer.new()
	pedals.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pedals.offset_left = -226
	pedals.offset_right = -36
	pedals.offset_top = -152
	pedals.offset_bottom = -38
	pedals.add_theme_constant_override("separation", 18)
	_drive_layer.add_child(pedals)

	var brake_btn := Button.new()
	brake_btn.text = "BRAKE"
	brake_btn.custom_minimum_size = Vector2(84, 96)
	_style_button(brake_btn, "res://assets/icons/ic_brake.svg", false, 16)
	brake_btn.button_down.connect(func() -> void: InputRouter.touch_brake_held = true)
	brake_btn.button_up.connect(func() -> void: InputRouter.touch_brake_held = false)
	pedals.add_child(brake_btn)

	var gas_btn := Button.new()
	gas_btn.text = "GAS"
	gas_btn.custom_minimum_size = Vector2(88, 114)
	_style_button(gas_btn, "res://assets/icons/ic_gas.svg", true, 16)
	gas_btn.button_down.connect(func() -> void: InputRouter.touch_gas_held = true)
	gas_btn.button_up.connect(func() -> void: InputRouter.touch_gas_held = false)
	pedals.add_child(gas_btn)

	# --- Transient Toast Banner (e.g. Screenshot Saved) ---
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.07, 0.09, 0.13, 0.86), Color(0.96, 0.62, 0.07, 0.72), 10, 18, 8)
	)
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_left = -110
	_toast_panel.offset_right = 110
	_toast_panel.offset_top = 24
	_toast_panel.offset_bottom = 60
	_toast_panel.visible = false
	_toast_panel.modulate.a = 0.0
	root.add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		_toast_label.add_theme_font_override("font", _font)
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.add_theme_color_override("font_color", Color.WHITE)
	_toast_panel.add_child(_toast_label)


func _on_touch_ui_toggled(_enabled: bool) -> void:
	_apply_input_visibility()


func _apply_input_visibility() -> void:
	var touch := InputRouter.touch_ui_enabled
	_pc_hints_panel.visible = not touch
	_enter_btn.text = "DRIVE" if touch else "DRIVE  [F]"
	_exit_btn.text = "EXIT" if touch else "EXIT  [F]"
	_foot_layer.visible = touch and not _driving_mode
	_drive_layer.visible = touch and _driving_mode
	if _foot_layer.visible:
		_foot_layer.modulate.a = 1.0
	if _drive_layer.visible:
		_drive_layer.modulate.a = 1.0


func _update_pc_hints() -> void:
	if _driving_mode:
		_pc_hints_label.text = "WASD Drive   |   SPACE Brake   |   F Exit Car   |   T Touch UI   |   F12 Shot"
	else:
		_pc_hints_label.text = "WASD Walk   |   SHIFT Sprint   |   SPACE Jump   |   F Enter Car   |   T Touch UI"


func set_game_mode(driving: bool, instant: bool = false) -> void:
	_driving_mode = driving
	_update_pc_hints()

	if instant:
		_speed_panel.visible = driving
		_speed_panel.modulate.a = 1.0 if driving else 0.0
		_exit_btn.visible = driving
		_exit_btn.modulate.a = 1.0 if driving else 0.0
		_apply_input_visibility()
		return

	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	_mode_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if driving:
		_speed_panel.visible = true
		_exit_btn.visible = true
		_mode_tween.tween_property(_speed_panel, "modulate:a", 1.0, 0.22)
		_mode_tween.tween_property(_exit_btn, "modulate:a", 1.0, 0.22)
		if InputRouter.touch_ui_enabled:
			_drive_layer.visible = true
			_mode_tween.tween_property(_foot_layer, "modulate:a", 0.0, 0.16)
			_mode_tween.tween_property(_drive_layer, "modulate:a", 1.0, 0.22)
			_mode_tween.chain().tween_callback(func() -> void: _foot_layer.visible = false)
	else:
		_mode_tween.tween_property(_speed_panel, "modulate:a", 0.0, 0.18)
		_mode_tween.tween_property(_exit_btn, "modulate:a", 0.0, 0.18)
		if InputRouter.touch_ui_enabled:
			_foot_layer.visible = true
			_mode_tween.tween_property(_drive_layer, "modulate:a", 0.0, 0.16)
			_mode_tween.tween_property(_foot_layer, "modulate:a", 1.0, 0.22)
		_mode_tween.chain().tween_callback(func() -> void:
			_speed_panel.visible = false
			_exit_btn.visible = false
			if InputRouter.touch_ui_enabled:
				_drive_layer.visible = false
		)


func set_enter_prompt_visible(show_prompt: bool) -> void:
	if _enter_visible == show_prompt:
		return
	_enter_visible = show_prompt
	if _enter_tween != null and _enter_tween.is_valid():
		_enter_tween.kill()
	_enter_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if show_prompt:
		_enter_btn.visible = true
		_enter_btn.scale = Vector2(0.92, 0.92)
		_enter_tween.set_parallel(true)
		_enter_tween.tween_property(_enter_btn, "modulate:a", 1.0, 0.18)
		_enter_tween.tween_property(_enter_btn, "scale", Vector2.ONE, 0.20)
	else:
		_enter_tween.tween_property(_enter_btn, "modulate:a", 0.0, 0.14)
		_enter_tween.tween_callback(func() -> void: _enter_btn.visible = false)


func update_speed_kmh(kmh: float) -> void:
	_speed_value_label.text = str(int(round(kmh)))


func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_panel.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.28)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)
