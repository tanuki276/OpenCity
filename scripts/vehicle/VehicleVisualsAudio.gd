class_name VehicleVisualsAudio
extends Node3D
## Drives car visual polish and audio:
## - Loads sculpted PBR car body + 4 alloy wheels
## - Spins all 4 wheels synced to road speed & steers front wheels with steering angle
## - Applies expressive chassis pitch (acceleration squat / brake dive) & cornering roll
## - Places AO contact shadow beneath chassis
## - Synthesizes RPM-pitched engine audio, door latch SFX, and collision bump SFX

const WHEEL_LOCAL_BASES := [
	Vector3(-0.86, 0.02, -1.34),  # FL
	Vector3(0.86, 0.02, -1.34),   # FR
	Vector3(-0.86, 0.02, 1.32),   # RL
	Vector3(0.86, 0.02, 1.32),    # RR
]

var _body_tilt_pivot: Node3D
var _wheel_steer_pivots: Array[Node3D] = []
var _wheel_spin_meshes: Array[Node3D] = []
var _taillight_mat: StandardMaterial3D
var _contact_shadow: MeshInstance3D

var _engine_audio: AudioStreamPlayer3D
var _sfx_audio: AudioStreamPlayer3D
var _door_stream: AudioStream
var _bump_stream: AudioStream

var _wheel_spin_rad: float = 0.0
var _engine_running: bool = false
var _smoothed_rpm: float = 0.0


func _ready() -> void:
	_build_vehicle_visuals()
	_setup_audio()


func _build_vehicle_visuals() -> void:
	# Ground AO contact shadow under the entire vehicle footprint
	_contact_shadow = MaterialLibrary.create_contact_shadow_quad(2.55, 5.05, 0.78)
	_contact_shadow.position = Vector3(0.0, -0.34, 0.0)
	add_child(_contact_shadow)

	# Body tilt pivot (for pitch/roll spring feel)
	_body_tilt_pivot = Node3D.new()
	_body_tilt_pivot.name = "BodyTiltPivot"
	_body_tilt_pivot.position = Vector3(0.0, -0.04, 0.0)
	add_child(_body_tilt_pivot)

	var body_inst := AssetResolver.instantiate_slot("car_body")
	MaterialLibrary.apply_pbr_and_variation(body_inst, Color.WHITE, true, 0.0)
	_body_tilt_pivot.add_child(body_inst)
	_find_taillight_material(body_inst)

	# 4 Independent Wheel Steer + Spin Pivots
	for i in range(4):
		var steer_pivot := Node3D.new()
		steer_pivot.name = "WheelPivot_%d" % i
		steer_pivot.position = WHEEL_LOCAL_BASES[i]
		add_child(steer_pivot)

		var spin_node := Node3D.new()
		spin_node.name = "WheelSpin_%d" % i
		steer_pivot.add_child(spin_node)

		var wheel_inst := AssetResolver.instantiate_slot("car_wheel")
		MaterialLibrary.apply_pbr_and_variation(wheel_inst, Color.WHITE, true, 0.0)
		spin_node.add_child(wheel_inst)

		_wheel_steer_pivots.append(steer_pivot)
		_wheel_spin_meshes.append(spin_node)


func _find_taillight_material(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in range(mi.mesh.get_surface_count()):
				var orig := mi.mesh.surface_get_material(s)
				if orig != null and orig.resource_name == "mat_taillight":
					var mat := mi.get_surface_override_material(s) as StandardMaterial3D
					if mat == null:
						mat = orig.duplicate() as StandardMaterial3D
						mi.set_surface_override_material(s, mat)
					mat.emission_enabled = true
					mat.emission = Color(0.95, 0.10, 0.06)
					mat.emission_energy_multiplier = 0.55
					_taillight_mat = mat
					return


func _setup_audio() -> void:
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.name = "EngineAudio"
	_engine_audio.unit_size = 10.0
	_engine_audio.max_distance = 45.0
	_engine_audio.volume_db = -18.0
	add_child(_engine_audio)

	var eng := load("res://assets/audio/engine_loop.wav") as AudioStreamWAV
	if eng != null:
		eng.loop_mode = AudioStreamWAV.LOOP_FORWARD
		eng.loop_begin = 0
		eng.loop_end = int(eng.get_length() * float(eng.mix_rate))
		_engine_audio.stream = eng

	_sfx_audio = AudioStreamPlayer3D.new()
	_sfx_audio.name = "VehicleSfx"
	_sfx_audio.unit_size = 8.0
	_sfx_audio.max_distance = 32.0
	add_child(_sfx_audio)

	if ResourceLoader.exists("res://assets/audio/car_door.wav"):
		_door_stream = load("res://assets/audio/car_door.wav") as AudioStream
	if ResourceLoader.exists("res://assets/audio/car_bump.wav"):
		_bump_stream = load("res://assets/audio/car_bump.wav") as AudioStream

	var parent_veh := get_parent() as RaycastVehicle
	if parent_veh != null:
		parent_veh.impact_occurred.connect(_on_vehicle_impact)


func set_engine_running(running: bool) -> void:
	_engine_running = running
	play_door_sfx()
	if _engine_audio == null or _engine_audio.stream == null:
		return
	if running:
		if not _engine_audio.playing:
			_engine_audio.pitch_scale = 0.85
			_engine_audio.volume_db = -12.0
			_engine_audio.play()
	else:
		_engine_audio.stop()


func play_door_sfx() -> void:
	if _sfx_audio != null and _door_stream != null:
		_sfx_audio.stream = _door_stream
		_sfx_audio.pitch_scale = 1.0
		_sfx_audio.volume_db = -4.0
		_sfx_audio.play()


func _on_vehicle_impact(intensity: float) -> void:
	if _sfx_audio != null and _bump_stream != null:
		_sfx_audio.stream = _bump_stream
		_sfx_audio.pitch_scale = lerpf(0.86, 1.12, intensity)
		_sfx_audio.volume_db = lerpf(-11.0, -2.0, intensity)
		_sfx_audio.play()


func update_visuals_and_audio(delta: float, veh: RaycastVehicle) -> void:
	# 1. Spin all 4 wheels strictly proportional to road distance covered
	_wheel_spin_rad -= (veh.forward_speed_mps / RaycastVehicle.WHEEL_RADIUS) * delta
	for i in range(4):
		var susp_y := (veh.wheel_compressions[i] - 0.45) * 0.16
		_wheel_steer_pivots[i].position.y = WHEEL_LOCAL_BASES[i].y + susp_y
		if i < 2:
			# Front wheels turn visibly with steering input
			_wheel_steer_pivots[i].rotation.y = veh.steer_angle_rad
		_wheel_spin_meshes[i].rotation.x = _wheel_spin_rad

	# 2. Expressive chassis pitch (squat on gas / dive on brake) & cornering roll
	var target_pitch := clampf(veh.longitudinal_accel_g * 0.048, -0.055, 0.055)
	var target_roll := clampf(
		veh.steer_angle_rad * clampf(veh.forward_speed_mps / 14.0, -1.0, 1.0) * 0.14 - veh.lateral_accel_g * 0.03,
		-0.075,
		0.075
	)
	_body_tilt_pivot.rotation.x = lerpf(_body_tilt_pivot.rotation.x, target_pitch, clampf(delta * 9.0, 0.0, 1.0))
	_body_tilt_pivot.rotation.z = lerpf(_body_tilt_pivot.rotation.z, target_roll, clampf(delta * 9.0, 0.0, 1.0))

	# 3. Brake light glow feedback
	if _taillight_mat != null:
		var target_glow := 2.4 if veh.is_braking_lights else (0.75 if _engine_running else 0.18)
		_taillight_mat.emission_energy_multiplier = lerpf(_taillight_mat.emission_energy_multiplier, target_glow, clampf(delta * 14.0, 0.0, 1.0))

	# 4. RPM-pitched engine audio (scales cleanly with speed & throttle load)
	if _engine_running and _engine_audio != null and _engine_audio.playing:
		var spd_norm := clampf(absf(veh.forward_speed_mps) / RaycastVehicle.MAX_FORWARD_SPEED, 0.0, 1.0)
		# Simulate 3-gear cadence so revving feels lively rather than monotonous
		var gear_saw := fmod(spd_norm * 2.6, 1.0)
		var target_rpm := clampf(0.18 + spd_norm * 0.55 + gear_saw * 0.25 + veh.throttle_input * 0.28, 0.12, 1.15)
		_smoothed_rpm = lerpf(_smoothed_rpm, target_rpm, clampf(delta * 7.0, 0.0, 1.0))
		_engine_audio.pitch_scale = lerpf(0.76, 2.25, _smoothed_rpm)
		_engine_audio.volume_db = lerpf(-13.5, -5.0, clampf(_smoothed_rpm * 0.8 + veh.throttle_input * 0.25, 0.0, 1.0))
