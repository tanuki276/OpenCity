class_name PlayerController
extends CharacterBody3D
## Third-person pedestrian controller tuned to Stage 1 specification:
## Walk 6.2 m/s, Sprint 9.5 m/s, Jump 6.5 m/s, Gravity 18.5 m/s^2.

const WALK_SPEED := 6.2
const SPRINT_SPEED := 9.5
const JUMP_VELOCITY := 6.5
const GRAVITY := 18.5
const GROUND_ACCEL := 26.0
const GROUND_DECEL := 22.0
const AIR_ACCEL := 8.5
const TURN_SPEED := 12.0

var active_control: bool = true
var camera_yaw_basis: float = 0.0
var horizontal_speed: float = 0.0
var is_sprinting: bool = false

@onready var animator: PlayerAnimator = $VisualRoot/PlayerAnimator


func _ready() -> void:
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.22
	# Solid collision against WorldStatic (1), Vehicle (3), and Props (4)
	collision_layer = 2
	collision_mask = 1 | 4 | 8


func set_control_active(enabled: bool) -> void:
	active_control = enabled
	visible = enabled
	$CollisionShape3D.disabled = not enabled
	if not enabled:
		velocity = Vector3.ZERO
		horizontal_speed = 0.0
		is_sprinting = false


func _physics_process(delta: float) -> void:
	if not active_control:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if InputRouter.consume_jump_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Camera-relative movement direction
	var move_in := InputRouter.get_foot_move_vector()
	var cam_basis := Basis(Vector3.UP, camera_yaw_basis)
	var wish_dir := (cam_basis * Vector3(move_in.x, 0.0, move_in.y))
	wish_dir.y = 0.0
	var input_mag := minf(move_in.length(), 1.0)
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()

	is_sprinting = InputRouter.is_sprint_pressed() and input_mag > 0.45
	var target_speed := (SPRINT_SPEED if is_sprinting else WALK_SPEED) * input_mag
	var target_vel := wish_dir * target_speed

	var accel := (GROUND_ACCEL if input_mag > 0.05 else GROUND_DECEL) if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	move_and_slide()

	# Prevent walking onto unstable ledges or sinking below ground
	if global_position.y < -2.0:
		global_position = CityBuilder.get_player_spawn_transform().origin
		velocity = Vector3.ZERO

	var horiz := Vector2(velocity.x, velocity.z)
	horizontal_speed = horiz.length()

	# Smoothly rotate visual character toward travel direction
	if horizontal_speed > 0.25:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		$VisualRoot.rotation.y = lerp_angle($VisualRoot.rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))

	if animator != null:
		animator.update_locomotion(delta, horizontal_speed, is_sprinting, is_on_floor(), velocity.y)
