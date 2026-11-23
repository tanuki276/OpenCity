class_name SpringCameraRig
extends Node3D
## Third-person SpringArm3D camera rig shared across pedestrian and vehicle modes.
## Avoids building/terrain clipping, smooths transitions (lerp), adds gentle walk bob,
## and softly aligns behind the car while driving without fighting manual orbit.

enum FollowMode { FOOT, VEHICLE }

var mode: FollowMode = FollowMode.FOOT
var target_node: Node3D
var player_ref: PlayerController
var vehicle_ref: RaycastVehicle

var yaw: float = -0.55
var pitch: float = -0.26

var _bob_phase: float = 0.0
var _manual_orbit_timer: float = 0.0
var _current_arm_length: float = 4.6
var _current_height_offset: float = 1.62

@onready var _pitch_pivot: Node3D = $PitchPivot
@onready var _spring_arm: SpringArm3D = $PitchPivot/SpringArm3D
@onready var _camera: Camera3D = $PitchPivot/SpringArm3D/Camera3D


func _ready() -> void:
	_spring_arm.collision_mask = 1 | 8
	_spring_arm.margin = 0.28
	_spring_arm.spring_length = _current_arm_length
	_camera.fov = 66.0
	_camera.near = 0.12
	_camera.far = 260.0


func configure_targets(player: PlayerController, vehicle: RaycastVehicle) -> void:
	player_ref = player
	vehicle_ref = vehicle
	set_follow_mode(FollowMode.FOOT, true)


func set_follow_mode(new_mode: FollowMode, snap: bool = false) -> void:
	mode = new_mode
	target_node = player_ref if mode == FollowMode.FOOT else vehicle_ref
	if mode == FollowMode.VEHICLE and vehicle_ref != null:
		# Softly align behind car on enter
		yaw = vehicle_ref.global_rotation.y
		pitch = -0.22
	if snap and target_node != null:
		global_position = target_node.global_position + Vector3(0.0, _get_target_height(), 0.0)


func _get_target_height() -> float:
	return 1.58 if mode == FollowMode.FOOT else 1.72


func _get_target_arm_length() -> float:
	if mode == FollowMode.FOOT:
		return 4.55
	var spd_boost := 0.0
	if vehicle_ref != null:
		spd_boost = clampf(vehicle_ref.get_speed_kmh() / 90.0, 0.0, 1.0) * 1.15
	return 6.45 + spd_boost


func _process(delta: float) -> void:
	if target_node == null:
		return

	# Consume mouse / touch look delta
	var look := InputRouter.consume_look_delta()
	if look.length_squared() > 0.000001:
		yaw -= look.x
		pitch = clampf(pitch - look.y, deg_to_rad(-52.0), deg_to_rad(28.0))
		_manual_orbit_timer = 1.6
	else:
		_manual_orbit_timer = maxf(0.0, _manual_orbit_timer - delta)

	# Gentle auto-follow behind moving car when user is not manually orbiting
	if mode == FollowMode.VEHICLE and vehicle_ref != null and _manual_orbit_timer <= 0.0:
		if absf(vehicle_ref.forward_speed_mps) > 1.2:
			var car_yaw := vehicle_ref.global_rotation.y
			if vehicle_ref.forward_speed_mps < -1.5:
				car_yaw += PI
			yaw = lerp_angle(yaw, car_yaw, clampf(delta * 3.2, 0.0, 1.0))

	# Smoothly track player or vehicle world origin
	_current_height_offset = lerpf(_current_height_offset, _get_target_height(), clampf(delta * 6.5, 0.0, 1.0))
	var desired_pos := target_node.global_position + Vector3(0.0, _current_height_offset, 0.0)

	# Subtle walk head-bob on foot (gentle, never nausea-inducing)
	var bob_y := 0.0
	if mode == FollowMode.FOOT and player_ref != null and player_ref.is_on_floor():
		var spd := player_ref.horizontal_speed
		if spd > 0.35:
			_bob_phase += delta * clampf(spd * 1.55, 6.0, 13.5)
			var bob_amp := lerpf(0.025, 0.048, clampf((spd - 6.2) / 3.3, 0.0, 1.0))
			bob_y = sin(_bob_phase) * bob_amp
		else:
			_bob_phase = 0.0

	var follow_rate := 12.0 if mode == FollowMode.FOOT else 10.5
	global_position = global_position.lerp(desired_pos + Vector3(0.0, bob_y, 0.0), clampf(delta * follow_rate, 0.0, 1.0))

	# Smooth orientation & dynamic FOV / spring-arm length
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 16.0, 0.0, 1.0))
	_pitch_pivot.rotation.x = lerpf(_pitch_pivot.rotation.x, pitch, clampf(delta * 16.0, 0.0, 1.0))

	_current_arm_length = lerpf(_current_arm_length, _get_target_arm_length(), clampf(delta * 5.0, 0.0, 1.0))
	_spring_arm.spring_length = _current_arm_length

	var target_fov := 65.0
	if mode == FollowMode.VEHICLE and vehicle_ref != null:
		target_fov = 66.0 + clampf(vehicle_ref.get_speed_kmh() / 90.0, 0.0, 1.0) * 11.0
	elif mode == FollowMode.FOOT and player_ref != null and player_ref.is_sprinting:
		target_fov = 69.5
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * 5.5, 0.0, 1.0))

	if player_ref != null:
		player_ref.camera_yaw_basis = rotation.y
