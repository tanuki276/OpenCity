class_name PlayerAnimator
extends Node3D
## Articulated third-person PBR humanoid rig with gait-phase-locked animation
## (playback cadence strictly synchronized to actual ground speed -> zero foot sliding)
## and phase-synced asphalt footsteps + AO contact shadow.

const WALK_STRIDE_LENGTH := 1.48   # Distance covered per full left+right gait cycle (meters)
const SPRINT_STRIDE_LENGTH := 2.05

var _gait_phase: float = 0.0
var _prev_step_half: int = 0
var _idle_time: float = 0.0

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _forearm_l: Node3D
var _forearm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _contact_shadow: MeshInstance3D

var _step_player: AudioStreamPlayer3D
var _step_streams: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 9012
	_build_humanoid_rig()
	_setup_footstep_audio()


func _setup_footstep_audio() -> void:
	_step_player = AudioStreamPlayer3D.new()
	_step_player.name = "FootstepAudio"
	_step_player.unit_size = 6.0
	_step_player.max_distance = 22.0
	_step_player.volume_db = -7.0
	add_child(_step_player)

	for i in range(1, 4):
		var path := "res://assets/audio/footstep_asphalt_0%d.wav" % i
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			if s != null:
				_step_streams.append(s)


func _make_mat(color: Color, roughness: float = 0.78, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _build_humanoid_rig() -> void:
	# Realistic casual urban attire (olive denim jacket, off-white tee, dark indigo jeans, sneakers)
	var mat_jacket := _make_mat(Color(0.24, 0.31, 0.28), 0.84)
	var mat_shirt := _make_mat(Color(0.86, 0.84, 0.80), 0.86)
	var mat_jeans := _make_mat(Color(0.16, 0.22, 0.34), 0.88)
	var mat_skin := _make_mat(Color(0.82, 0.64, 0.52), 0.65)
	var mat_hair := _make_mat(Color(0.14, 0.11, 0.09), 0.72)
	var mat_shoe := _make_mat(Color(0.88, 0.88, 0.86), 0.60)
	var mat_sole := _make_mat(Color(0.14, 0.14, 0.16), 0.80)
	var mat_pack := _make_mat(Color(0.20, 0.19, 0.22), 0.78)

	# Ground Contact Shadow directly beneath feet
	_contact_shadow = MaterialLibrary.create_contact_shadow_quad(0.95, 0.95, 0.68)
	_contact_shadow.position = Vector3(0.0, 0.025, 0.0)
	add_child(_contact_shadow)

	# Pelvis / Hips root at y = 0.94m
	_hips = Node3D.new()
	_hips.position = Vector3(0.0, 0.94, 0.0)
	add_child(_hips)

	var pelv_m := BoxMesh.new()
	pelv_m.size = Vector3(0.32, 0.16, 0.21)
	_add_part(_hips, pelv_m, mat_jeans, Vector3(0.0, 0.0, 0.0))

	# Torso & Jacket
	_torso = Node3D.new()
	_torso.position = Vector3(0.0, 0.08, 0.0)
	_hips.add_child(_torso)

	var chest_m := BoxMesh.new()
	chest_m.size = Vector3(0.38, 0.44, 0.23)
	_add_part(_torso, chest_m, mat_jacket, Vector3(0.0, 0.24, 0.0))
	var tee_m := BoxMesh.new()
	tee_m.size = Vector3(0.14, 0.42, 0.24)
	_add_part(_torso, tee_m, mat_shirt, Vector3(0.0, 0.23, -0.005))
	# Slim urban daypack on back (+Z since character faces -Z)
	var pack_m := BoxMesh.new()
	pack_m.size = Vector3(0.28, 0.34, 0.12)
	_add_part(_torso, pack_m, mat_pack, Vector3(0.0, 0.24, 0.16))

	# Head & Hair
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.49, 0.0)
	_torso.add_child(_head)

	var neck_m := CylinderMesh.new()
	neck_m.top_radius = 0.055
	neck_m.bottom_radius = 0.06
	neck_m.height = 0.10
	_add_part(_head, neck_m, mat_skin, Vector3(0.0, 0.03, 0.0))

	var head_m := SphereMesh.new()
	head_m.radius = 0.115
	head_m.height = 0.25
	_add_part(_head, head_m, mat_skin, Vector3(0.0, 0.16, 0.0))

	var hair_m := SphereMesh.new()
	hair_m.radius = 0.122
	hair_m.height = 0.17
	_add_part(_head, hair_m, mat_hair, Vector3(0.0, 0.21, 0.015))

	# Arms (Upper + Forearm pivots)
	var upper_arm_m := CapsuleMesh.new()
	upper_arm_m.radius = 0.055
	upper_arm_m.height = 0.32
	var lower_arm_m := CapsuleMesh.new()
	lower_arm_m.radius = 0.046
	lower_arm_m.height = 0.29
	var hand_m := SphereMesh.new()
	hand_m.radius = 0.045
	hand_m.height = 0.09

	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.24, 0.42, 0.0)
	_torso.add_child(_arm_l)
	_add_part(_arm_l, upper_arm_m, mat_jacket, Vector3(0.0, -0.14, 0.0))
	_forearm_l = Node3D.new()
	_forearm_l.position = Vector3(0.0, -0.28, 0.0)
	_arm_l.add_child(_forearm_l)
	_add_part(_forearm_l, lower_arm_m, mat_jacket, Vector3(0.0, -0.13, 0.0))
	_add_part(_forearm_l, hand_m, mat_skin, Vector3(0.0, -0.27, 0.0))

	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.24, 0.42, 0.0)
	_torso.add_child(_arm_r)
	_add_part(_arm_r, upper_arm_m, mat_jacket, Vector3(0.0, -0.14, 0.0))
	_forearm_r = Node3D.new()
	_forearm_r.position = Vector3(0.0, -0.28, 0.0)
	_arm_r.add_child(_forearm_r)
	_add_part(_forearm_r, lower_arm_m, mat_jacket, Vector3(0.0, -0.13, 0.0))
	_add_part(_forearm_r, hand_m, mat_skin, Vector3(0.0, -0.27, 0.0))

	# Legs (Thigh + Shin + Sneaker pivots)
	var thigh_m := CapsuleMesh.new()
	thigh_m.radius = 0.075
	thigh_m.height = 0.46
	var shin_m := CapsuleMesh.new()
	shin_m.radius = 0.062
	shin_m.height = 0.44
	var shoe_m := BoxMesh.new()
	shoe_m.size = Vector3(0.11, 0.09, 0.24)
	var sole_m := BoxMesh.new()
	sole_m.size = Vector3(0.115, 0.03, 0.25)

	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.105, -0.05, 0.0)
	_hips.add_child(_leg_l)
	_add_part(_leg_l, thigh_m, mat_jeans, Vector3(0.0, -0.21, 0.0))
	_shin_l = Node3D.new()
	_shin_l.position = Vector3(0.0, -0.42, 0.0)
	_leg_l.add_child(_shin_l)
	_add_part(_shin_l, shin_m, mat_jeans, Vector3(0.0, -0.20, 0.0))
	_add_part(_shin_l, shoe_m, mat_shoe, Vector3(0.0, -0.43, -0.04))
	_add_part(_shin_l, sole_m, mat_sole, Vector3(0.0, -0.47, -0.04))

	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.105, -0.05, 0.0)
	_hips.add_child(_leg_r)
	_add_part(_leg_r, thigh_m, mat_jeans, Vector3(0.0, -0.21, 0.0))
	_shin_r = Node3D.new()
	_shin_r.position = Vector3(0.0, -0.42, 0.0)
	_leg_r.add_child(_shin_r)
	_add_part(_shin_r, shin_m, mat_jeans, Vector3(0.0, -0.20, 0.0))
	_add_part(_shin_r, shoe_m, mat_shoe, Vector3(0.0, -0.43, -0.04))
	_add_part(_shin_r, sole_m, mat_sole, Vector3(0.0, -0.47, -0.04))


func update_locomotion(delta: float, speed: float, sprinting: bool, on_floor: bool, vel_y: float) -> void:
	_idle_time += delta
	var smooth := clampf(delta * 14.0, 0.0, 1.0)

	# Hide/fade contact shadow slightly when jumping off ground
	if _contact_shadow != null:
		_contact_shadow.visible = on_floor

	if not on_floor:
		# Airborne jump pose
		var jump_t := clampf(vel_y / 6.5, -1.0, 1.0)
		_hips.position.y = lerpf(_hips.position.y, 0.96, smooth)
		_torso.rotation.x = lerpf(_torso.rotation.x, -0.10, smooth)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.45 * jump_t + 0.25, smooth)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.35, smooth)
		_shin_l.rotation.x = lerpf(_shin_l.rotation.x, -0.55, smooth)
		_shin_r.rotation.x = lerpf(_shin_r.rotation.x, -0.35, smooth)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.55, smooth)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.35, smooth)
		_forearm_l.rotation.x = lerpf(_forearm_l.rotation.x, 0.45, smooth)
		_forearm_r.rotation.x = lerpf(_forearm_r.rotation.x, 0.45, smooth)
		return

	if speed < 0.12:
		# Relaxed breathing idle pose
		var breath := sin(_idle_time * 2.1)
		_hips.position.y = lerpf(_hips.position.y, 0.94 + breath * 0.008, smooth)
		_torso.rotation.x = lerpf(_torso.rotation.x, 0.02 + breath * 0.015, smooth)
		_torso.rotation.y = lerpf(_torso.rotation.y, 0.0, smooth)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, smooth)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, smooth)
		_shin_l.rotation.x = lerpf(_shin_l.rotation.x, 0.0, smooth)
		_shin_r.rotation.x = lerpf(_shin_r.rotation.x, 0.0, smooth)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.05, smooth)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.05, smooth)
		_forearm_l.rotation.x = lerpf(_forearm_l.rotation.x, 0.14, smooth)
		_forearm_r.rotation.x = lerpf(_forearm_r.rotation.x, 0.14, smooth)
		return

	# Velocity-locked gait phase: feet travel backward at exact ground speed (zero foot sliding)
	var sprint_blend := clampf((speed - 6.2) / (9.5 - 6.2), 0.0, 1.0)
	var stride_len := lerpf(WALK_STRIDE_LENGTH, SPRINT_STRIDE_LENGTH, sprint_blend)
	_gait_phase += (speed / stride_len) * TAU * delta

	# Trigger synchronized footstep sound on every half-cycle foot plant
	var cur_half := int(floor(_gait_phase / PI))
	if cur_half != _prev_step_half:
		_prev_step_half = cur_half
		_play_footstep(sprint_blend)

	var s := sin(_gait_phase)
	var c := cos(_gait_phase)
	var amp := clampf(speed / 6.2, 0.25, 1.0) * lerpf(0.62, 0.96, sprint_blend)

	# Subtle hip bob (double frequency per cycle) + forward lean while sprinting
	var bob := absf(c) * lerpf(0.042, 0.082, sprint_blend)
	_hips.position.y = lerpf(_hips.position.y, 0.93 - bob, smooth)
	_torso.rotation.x = lerpf(_torso.rotation.x, lerpf(-0.06, -0.22, sprint_blend), smooth)
	_torso.rotation.y = s * lerpf(0.09, 0.18, sprint_blend)

	# Thigh swing + natural knee bend during forward recovery phase
	_leg_l.rotation.x = s * amp
	_leg_r.rotation.x = -s * amp
	_shin_l.rotation.x = -maxf(0.0, -c) * lerpf(0.65, 1.15, sprint_blend) - maxf(0.0, -s) * 0.25
	_shin_r.rotation.x = -maxf(0.0, c) * lerpf(0.65, 1.15, sprint_blend) - maxf(0.0, s) * 0.25

	# Counter-swinging arms + bent elbows when sprinting
	var arm_amp := amp * lerpf(0.75, 1.05, sprint_blend)
	_arm_l.rotation.x = -s * arm_amp
	_arm_r.rotation.x = s * arm_amp
	var elbow_base := lerpf(0.26, 0.95, sprint_blend)
	_forearm_l.rotation.x = elbow_base + maxf(0.0, -s) * 0.35
	_forearm_r.rotation.x = elbow_base + maxf(0.0, s) * 0.35


func _play_footstep(sprint_blend: float) -> void:
	if _step_player == null or _step_streams.is_empty():
		return
	var clip := _step_streams[_rng.randi_range(0, _step_streams.size() - 1)]
	_step_player.stream = clip
	_step_player.pitch_scale = _rng.randf_range(0.92, 1.08) + sprint_blend * 0.08
	_step_player.volume_db = lerpf(-11.0, -5.5, sprint_blend)
	_step_player.play()
