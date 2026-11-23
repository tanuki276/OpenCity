class_name RaycastVehicle
extends RigidBody3D
## Custom 4-wheel RayCast3D arcade vehicle built for Stage 1:
## Stable at low & high speeds, corners cleanly around 90-degree city intersections,
## never clips into walls/buildings, and exposes live telemetry for wheel/chassis visuals & RPM audio.

signal impact_occurred(intensity: float)

const MAX_FORWARD_SPEED := 25.5     # ~92 km/h (fun & controllable on 133m city grid)
const MAX_REVERSE_SPEED := 9.0      # ~32 km/h
const ENGINE_ACCEL_FORCE := 15500.0
const REVERSE_FORCE := 9200.0
const BRAKE_FORCE := 23000.0
const COAST_DRAG := 1450.0
const LATERAL_GRIP := 13.5

const WHEEL_RADIUS := 0.35
const SUSP_REST_LENGTH := 0.44
const SUSP_STIFFNESS := 30000.0
const SUSP_DAMPING := 4200.0
const MAX_STEER_DEG := 32.0

var driver_active: bool = false
var current_speed_mps: float = 0.0
var forward_speed_mps: float = 0.0
var steer_angle_rad: float = 0.0
var throttle_input: float = 0.0
var brake_input: float = 0.0
var is_braking_lights: bool = false
var lateral_accel_g: float = 0.0
var longitudinal_accel_g: float = 0.0
var wheel_compressions: Array[float] = [0.5, 0.5, 0.5, 0.5]
var grounded_wheels: int = 0

var _prev_forward_speed: float = 0.0
var _prev_lateral_speed: float = 0.0
var _impact_cooldown: float = 0.0

@onready var _rays: Array[RayCast3D] = [
	$WheelRays/RayFL,
	$WheelRays/RayFR,
	$WheelRays/RayRL,
	$WheelRays/RayRR,
]
@onready var visuals_audio: VehicleVisualsAudio = $VisualsAudio


func _ready() -> void:
	mass = 1350.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.24, 0.0)
	linear_damp = 0.18
	angular_damp = 3.2

	# Collide solidly with WorldStatic (1), Player (2), Vehicle (4), Props (8)
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8

	for ray in _rays:
		ray.target_position = Vector3(0.0, -(SUSP_REST_LENGTH + WHEEL_RADIUS), 0.0)
		ray.collision_mask = 1
		ray.add_exception(self)

	body_entered.connect(_on_body_entered)


func set_driver_active(active: bool) -> void:
	driver_active = active
	if not active:
		throttle_input = 0.0
		brake_input = 0.0
		is_braking_lights = false
		InputRouter.reset_touch_driving_inputs()
	if visuals_audio != null:
		visuals_audio.set_engine_running(active)


func get_speed_kmh() -> float:
	return absf(forward_speed_mps) * 3.6


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)

	# Safety recovery if ever pushed out of bounds
	if global_position.y < -3.0:
		global_transform = CityBuilder.get_vehicle_spawn_transform()
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return

	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var up := global_transform.basis.y

	forward_speed_mps = linear_velocity.dot(fwd)
	var lateral_speed := linear_velocity.dot(right)
	current_speed_mps = Vector2(linear_velocity.x, linear_velocity.z).length()

	# Smoothed accelerations for chassis pitch/roll visuals
	var raw_long := (forward_speed_mps - _prev_forward_speed) / maxf(delta, 0.001) / 9.81
	var raw_lat := (lateral_speed - _prev_lateral_speed) / maxf(delta, 0.001) / 9.81
	longitudinal_accel_g = lerpf(longitudinal_accel_g, clampf(raw_long, -1.2, 1.2), clampf(delta * 8.0, 0.0, 1.0))
	lateral_accel_g = lerpf(lateral_accel_g, clampf(raw_lat, -1.2, 1.2), clampf(delta * 8.0, 0.0, 1.0))
	_prev_forward_speed = forward_speed_mps
	_prev_lateral_speed = lateral_speed

	# Read driver inputs
	var raw_steer := 0.0
	if driver_active:
		throttle_input = InputRouter.get_vehicle_throttle()
		brake_input = InputRouter.get_vehicle_brake_reverse()
		raw_steer = InputRouter.get_vehicle_steer()
	else:
		throttle_input = 0.0
		brake_input = 0.0
		raw_steer = 0.0

	# Speed-sensitive steering (tight at intersections, stable at full speed)
	var speed_ratio := clampf(absf(forward_speed_mps) / MAX_FORWARD_SPEED, 0.0, 1.0)
	var max_rad := deg_to_rad(lerpf(MAX_STEER_DEG, 14.5, speed_ratio * 0.85))
	var target_steer := raw_steer * max_rad
	steer_angle_rad = move_toward(steer_angle_rad, target_steer, delta * 3.8)

	# 4-Wheel RayCast Suspension
	grounded_wheels = 0
	for i in range(4):
		var ray := _rays[i]
		ray.force_raycast_update()
		if ray.is_colliding():
			grounded_wheels += 1
			var hit_pt := ray.get_collision_point()
			var dist := ray.global_position.distance_to(hit_pt) - WHEEL_RADIUS
			var comp := clampf(SUSP_REST_LENGTH - dist, 0.0, SUSP_REST_LENGTH)
			wheel_compressions[i] = comp / SUSP_REST_LENGTH

			var wheel_offset := ray.global_position - global_position
			var point_vel := linear_velocity + angular_velocity.cross(wheel_offset)
			var susp_vel := point_vel.dot(up)
			var force_mag := clampf(comp * SUSP_STIFFNESS - susp_vel * SUSP_DAMPING, 0.0, 18000.0)
			apply_force(up * force_mag, wheel_offset)
		else:
			wheel_compressions[i] = lerpf(wheel_compressions[i], 0.0, delta * 10.0)

	# Traction, Braking, Lateral Grip & Steering when wheels touch road
	if grounded_wheels > 0:
		var grip_factor := float(grounded_wheels) / 4.0

		# Determine forward drive vs braking vs reverse
		var drive_force := 0.0
		is_braking_lights = false

		if driver_active:
			if throttle_input > 0.02:
				if forward_speed_mps < -0.6:
					# Braking out of reverse
					drive_force = BRAKE_FORCE * throttle_input
					is_braking_lights = true
				elif forward_speed_mps < MAX_FORWARD_SPEED:
					var taper := clampf(1.0 - (forward_speed_mps / MAX_FORWARD_SPEED) * 0.65, 0.25, 1.0)
					drive_force = ENGINE_ACCEL_FORCE * throttle_input * taper
			elif brake_input > 0.02:
				is_braking_lights = true
				if forward_speed_mps > 0.6:
					# Crisp arcade braking
					drive_force = -BRAKE_FORCE * brake_input
				elif forward_speed_mps > -MAX_REVERSE_SPEED:
					# Smooth reverse gear
					drive_force = -REVERSE_FORCE * brake_input
			else:
				# Natural rolling resistance
				if absf(forward_speed_mps) > 0.08:
					drive_force = -signf(forward_speed_mps) * COAST_DRAG
				else:
					linear_velocity.x = lerpf(linear_velocity.x, 0.0, delta * 10.0)
					linear_velocity.z = lerpf(linear_velocity.z, 0.0, delta * 10.0)
		else:
			# Parked auto-brake when player exits
			if absf(forward_speed_mps) > 0.15:
				drive_force = -signf(forward_speed_mps) * BRAKE_FORCE * 0.85
			else:
				linear_velocity.x = lerpf(linear_velocity.x, 0.0, delta * 12.0)
				linear_velocity.z = lerpf(linear_velocity.z, 0.0, delta * 12.0)

		apply_central_force(fwd * drive_force * grip_factor)

		# Strong arcade lateral tire friction (eliminates sloppy sliding & wall scraping)
		var lat_kill := -lateral_speed * mass * LATERAL_GRIP * grip_factor
		apply_central_force(right * lat_kill)

		# Smooth arcade yaw steering proportional to wheel steer angle and velocity
		var speed_for_turn := clampf(absf(forward_speed_mps) / 3.2, 0.0, 1.0)
		if speed_for_turn > 0.02:
			var dir_sign := 1.0 if forward_speed_mps >= -0.05 else -1.0
			var desired_yaw_rate := (steer_angle_rad / deg_to_rad(MAX_STEER_DEG)) * dir_sign * speed_for_turn * lerpf(2.35, 1.55, speed_ratio)
			var yaw_err := desired_yaw_rate - angular_velocity.y
			apply_torque(up * yaw_err * mass * 2.8)
		else:
			apply_torque(up * -angular_velocity.y * mass * 2.0)

	# Upright stabilization (prevents flipping over curbs)
	var upright_axis := up.cross(Vector3.UP)
	apply_torque(upright_axis * mass * 16.0)

	if visuals_audio != null:
		visuals_audio.update_visuals_and_audio(delta, self)


func find_safe_exit_position() -> Vector3:
	## Tests left door -> right door -> rear -> roof using a player-sized capsule query
	## so exiting next to any building or streetlight never clips the player inside geometry.
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.65

	var local_candidates := [
		Vector3(-1.85, 0.95, -0.15),  # Driver side (left)
		Vector3(1.85, 0.95, -0.15),   # Passenger side (right)
		Vector3(-2.45, 0.95, 0.6),    # Driver rear wide
		Vector3(0.0, 0.95, 3.05),     # Behind trunk
		Vector3(0.0, 2.35, 0.0),      # Roof fallback
	]
	for local_off in local_candidates:
		var world_pos := global_transform * local_off
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, world_pos)
		query.collision_mask = 1 | 4 | 8
		query.exclude = [get_rid()]
		var hits := space.intersect_shape(query, 1)
		if hits.is_empty():
			# Drop feet cleanly toward road/sidewalk height
			return Vector3(world_pos.x, maxf(global_position.y - 0.1, 0.16), world_pos.z)

	return global_position + Vector3(0.0, 1.9, 0.0)


func _on_body_entered(body: Node) -> void:
	if _impact_cooldown > 0.0:
		return
	if body is StaticBody3D:
		var spd := current_speed_mps
		if spd > 2.2:
			_impact_cooldown = 0.35
			impact_occurred.emit(clampf(spd / 16.0, 0.25, 1.0))
