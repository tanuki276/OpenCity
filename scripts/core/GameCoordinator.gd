class_name GameCoordinator
extends Node
## Central state coordinator for Stage 1:
## - Spawns player & hero car in the fixed 5x5 city
## - Manages ON_FOOT <-> DRIVING transitions with proximity & safe exit checks
## - Coordinates CameraRig, HUDController, and street-level quality screenshot capture

enum GameMode { ON_FOOT, DRIVING }

const VEHICLE_INTERACT_RADIUS := 3.4

var current_mode: GameMode = GameMode.ON_FOOT
var _can_enter_vehicle: bool = false

@export var player_path: NodePath
@export var vehicle_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath

var _player: PlayerController
var _vehicle: RaycastVehicle
var _camera_rig: SpringCameraRig
var _hud: HUDController


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_vehicle = get_node_or_null(vehicle_path) as RaycastVehicle
	_camera_rig = get_node_or_null(camera_rig_path) as SpringCameraRig
	_hud = get_node_or_null(hud_path) as HUDController

	if _player != null:
		_player.global_transform = CityBuilder.get_player_spawn_transform()
		_player.set_control_active(true)
	if _vehicle != null:
		_vehicle.global_transform = CityBuilder.get_vehicle_spawn_transform()
		_vehicle.set_driver_active(false)
	if _camera_rig != null and _player != null and _vehicle != null:
		_camera_rig.configure_targets(_player, _vehicle)
	if _hud != null:
		_hud.set_game_mode(false, true)

	InputRouter.interact_pressed.connect(_on_interact_pressed)
	InputRouter.screenshot_requested.connect(_on_screenshot_requested)


func _process(_delta: float) -> void:
	if _player == null or _vehicle == null or _hud == null:
		return

	if current_mode == GameMode.ON_FOOT:
		var dist := _player.global_position.distance_to(_vehicle.global_position)
		var near := dist <= VEHICLE_INTERACT_RADIUS
		if near != _can_enter_vehicle:
			_can_enter_vehicle = near
			_hud.set_enter_prompt_visible(near)
	else:
		if _can_enter_vehicle:
			_can_enter_vehicle = false
			_hud.set_enter_prompt_visible(false)
		_hud.update_speed_kmh(_vehicle.get_speed_kmh())


func _on_interact_pressed() -> void:
	if _player == null or _vehicle == null:
		return
	if current_mode == GameMode.ON_FOOT:
		var dist := _player.global_position.distance_to(_vehicle.global_position)
		if dist <= VEHICLE_INTERACT_RADIUS:
			_enter_vehicle()
	else:
		_exit_vehicle()


func _enter_vehicle() -> void:
	current_mode = GameMode.DRIVING
	_can_enter_vehicle = false
	InputRouter.reset_touch_foot_inputs()
	_player.set_control_active(false)
	_vehicle.set_driver_active(true)
	if _camera_rig != null:
		_camera_rig.set_follow_mode(SpringCameraRig.FollowMode.VEHICLE, false)
	if _hud != null:
		_hud.set_enter_prompt_visible(false)
		_hud.set_game_mode(true, false)


func _exit_vehicle() -> void:
	current_mode = GameMode.ON_FOOT
	var exit_pos := _vehicle.find_safe_exit_position()
	_vehicle.set_driver_active(false)
	_player.global_position = exit_pos
	_player.velocity = Vector3.ZERO
	_player.set_control_active(true)
	if _camera_rig != null:
		_camera_rig.set_follow_mode(SpringCameraRig.FollowMode.FOOT, false)
	if _hud != null:
		_hud.set_game_mode(false, false)


func _on_screenshot_requested() -> void:
	# Street-level screenshot verification helper for docs/quality-standard.md review
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir_path := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var full_path := "%s/street_%s.png" % [dir_path, stamp]
	var err := img.save_png(full_path)
	if err == OK and _hud != null:
		_hud.show_toast("SCREENSHOT SAVED")
