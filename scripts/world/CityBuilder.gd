class_name CityBuilder
extends Node3D
## Builds the fixed-layout 5x5 grid American urban & suburban town (~133m x 133m).
## Enforces real PBR textures, architectural variety, central landmark plaza,
## per-instance prop variance (+/-10% scale, rotation, +/-5% tint), contact shadows,
## and exact static collision for both player and vehicle.

const GRID_HALF := 2                # -2..+2 => 5x5 blocks
const ROAD_WIDTH := 9.6             # Two 4.8m driving lanes
const BLOCK_SIZE := 15.2            # Sidewalk + building/plaza footprint
const CELL_PITCH := 24.8            # BLOCK_SIZE + ROAD_WIDTH
const SIDEWALK_HEIGHT := 0.14
const SIDEWALK_MARGIN := 2.1

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261122
	_build_ground_and_roads()
	_build_all_blocks()
	_build_intersections_and_signals()
	_build_outer_boulevard_boundary()


static func get_player_spawn_transform() -> Transform3D:
	# Sidewalk on the southeast corner of the central landmark plaza, looking at the car & avenue
	var pos := Vector3(6.2, SIDEWALK_HEIGHT + 0.05, 8.8)
	return Transform3D(Basis.from_euler(Vector3(0.0, -0.55, 0.0)), pos)


static func get_vehicle_spawn_transform() -> Transform3D:
	# Parked cleanly in the northbound right lane of the main central avenue (x = 12.4 + 2.3)
	var pos := Vector3(14.7, 0.48, 5.0)
	return Transform3D(Basis.IDENTITY, pos)


func _build_ground_and_roads() -> void:
	var total_span := (GRID_HALF * 2 + 1) * CELL_PITCH + ROAD_WIDTH + 28.0

	# Base solid road collider (continuous y = 0.0 driving plane)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollider"
	road_body.collision_layer = 1
	road_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(total_span, 1.0, total_span)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	road_body.add_child(col)
	add_child(road_body)

	# Continuous base asphalt surface
	var base_mesh := MeshInstance3D.new()
	base_mesh.name = "AsphaltBase"
	var plane := PlaneMesh.new()
	plane.size = Vector2(total_span, total_span)
	base_mesh.mesh = plane
	base_mesh.material_override = MaterialLibrary.get_road_material("plain", Vector2(total_span / 8.0, total_span / 8.0))
	base_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base_mesh)

	# Textured two-lane road strips with double-yellow centerlines & crosswalks between intersections
	var lane_mat_ns := MaterialLibrary.get_road_material("lane", Vector2(1.0, BLOCK_SIZE / 6.0))
	var lane_mat_ew := MaterialLibrary.get_road_material("lane", Vector2(1.0, BLOCK_SIZE / 6.0))
	var xwalk_mat := MaterialLibrary.get_road_material("crosswalk", Vector2(1.0, 1.0))

	# 6 North-South avenues (i = 0..5) x 5 block segments (bz = -2..2)
	for i in range(6):
		var rx := (float(i) - 2.5) * CELL_PITCH
		for bz in range(-GRID_HALF, GRID_HALF + 1):
			var cz := float(bz) * CELL_PITCH
			_add_road_strip(Vector3(rx, 0.012, cz), Vector2(ROAD_WIDTH, BLOCK_SIZE), 0.0, lane_mat_ns)
			# Crosswalks at north & south ends of each segment
			_add_road_strip(Vector3(rx, 0.018, cz - BLOCK_SIZE * 0.5 + 1.3), Vector2(ROAD_WIDTH - 0.6, 2.4), 0.0, xwalk_mat)
			_add_road_strip(Vector3(rx, 0.018, cz + BLOCK_SIZE * 0.5 - 1.3), Vector2(ROAD_WIDTH - 0.6, 2.4), 0.0, xwalk_mat)

	# 6 East-West streets (j = 0..5) x 5 block segments (bx = -2..2)
	for j in range(6):
		var rz := (float(j) - 2.5) * CELL_PITCH
		for bx in range(-GRID_HALF, GRID_HALF + 1):
			var cx := float(bx) * CELL_PITCH
			_add_road_strip(Vector3(cx, 0.014, rz), Vector2(ROAD_WIDTH, BLOCK_SIZE), PI * 0.5, lane_mat_ew)
			_add_road_strip(Vector3(cx - BLOCK_SIZE * 0.5 + 1.3, 0.018, rz), Vector2(ROAD_WIDTH - 0.6, 2.4), PI * 0.5, xwalk_mat)
			_add_road_strip(Vector3(cx + BLOCK_SIZE * 0.5 - 1.3, 0.018, rz), Vector2(ROAD_WIDTH - 0.6, 2.4), PI * 0.5, xwalk_mat)


func _add_road_strip(pos: Vector3, size: Vector2, yaw: float, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_all_blocks() -> void:
	for bx in range(-GRID_HALF, GRID_HALF + 1):
		for bz in range(-GRID_HALF, GRID_HALF + 1):
			var center := Vector3(float(bx) * CELL_PITCH, 0.0, float(bz) * CELL_PITCH)
			if bx == 0 and bz == 0:
				_build_central_landmark_plaza(center)
			else:
				_build_district_block(bx, bz, center)


func _add_raised_slab(center: Vector3, width: float, depth: float, height: float, mat: StandardMaterial3D, with_collider: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, depth)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center + Vector3(0.0, height * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	if with_collider:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, height, depth)
		cs.shape = shape
		sb.position = mi.position
		sb.add_child(cs)
		add_child(sb)


func _build_central_landmark_plaza(center: Vector3) -> void:
	# Intentional civic square with interlocking stone pavers, stepped curb, clock-fountain, benches & trees
	_add_raised_slab(center, BLOCK_SIZE, BLOCK_SIZE, SIDEWALK_HEIGHT, MaterialLibrary.get_sidewalk_material(Vector2(5.0, 5.0)), true)
	var plaza_top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(BLOCK_SIZE - 1.6, BLOCK_SIZE - 1.6)
	plaza_top.mesh = pm
	plaza_top.material_override = MaterialLibrary.get_plaza_material(Vector2(4.5, 4.5))
	plaza_top.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.012, 0.0)
	plaza_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plaza_top)

	# Central Clock-Fountain Monument
	var monument := AssetResolver.instantiate_slot("landmark_fountain")
	monument.position = center + Vector3(0.0, SIDEWALK_HEIGHT, 0.0)
	MaterialLibrary.apply_pbr_and_variation(monument, Color.WHITE, true, 0.0)
	add_child(monument)
	_add_box_collider(center + Vector3(0.0, SIDEWALK_HEIGHT + 1.5, 0.0), Vector3(6.2, 3.0, 6.2), 1)

	# Contact shadow around fountain base
	var f_shadow := MaterialLibrary.create_contact_shadow_quad(7.6, 7.6, 0.58)
	f_shadow.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.025, 0.0)
	add_child(f_shadow)

	# 4 Benches facing inward around the plaza
	var bench_offsets := [
		[Vector3(0.0, 0.0, 4.8), PI],
		[Vector3(0.0, 0.0, -4.8), 0.0],
		[Vector3(4.8, 0.0, 0.0), -PI * 0.5],
		[Vector3(-4.8, 0.0, 0.0), PI * 0.5],
	]
	for entry in bench_offsets:
		_place_prop("prop_bench", center + entry[0] + Vector3(0.0, SIDEWALK_HEIGHT, 0.0), entry[1], true, Vector2(2.1, 1.1), 58.0, Vector3(1.8, 0.9, 0.7))

	# 4 Corner shade trees with natural variance
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tp := center + Vector3(sx * 5.2, SIDEWALK_HEIGHT, sz * 5.2)
			_place_prop("prop_tree", tp, _rng.randf_range(0.0, TAU), true, Vector2(2.4, 2.4), 95.0, Vector3(0.7, 3.5, 0.7))


func _build_district_block(bx: int, bz: int, center: Vector3) -> void:
	# Determine district flavor so no two blocks look identical
	var dist_center := maxi(absi(bx), absi(bz))
	var is_pocket_plaza := (bx == -2 and bz == 0) or (bx == 2 and bz == -1)
	var is_suburban := (dist_center == 2 and not is_pocket_plaza and (bz <= -1 or bx <= -1))
	var is_downtown := (dist_center == 1)

	# Raised concrete sidewalk platform
	_add_raised_slab(center, BLOCK_SIZE, BLOCK_SIZE, SIDEWALK_HEIGHT, MaterialLibrary.get_sidewalk_material(Vector2(5.0, 5.0)), true)

	if is_pocket_plaza:
		_build_pocket_plaza(center)
		_populate_block_sidewalk_props(bx, bz, center, "plaza")
		return

	if is_suburban:
		# Lush sunlit suburban lawn inside sidewalk curb
		var yard := MeshInstance3D.new()
		var ym := PlaneMesh.new()
		ym.size = Vector2(BLOCK_SIZE - 2.6, BLOCK_SIZE - 2.6)
		yard.mesh = ym
		yard.material_override = MaterialLibrary.get_grass_material(Vector2(3.5, 3.5))
		yard.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.012, 0.0)
		yard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(yard)

		# Concrete front walkway & driveway apron
		var drive := MeshInstance3D.new()
		var dm := PlaneMesh.new()
		dm.size = Vector2(3.2, 4.0)
		drive.mesh = dm
		drive.material_override = MaterialLibrary.get_sidewalk_material(Vector2(1.2, 1.5))
		drive.position = center + Vector3(2.4, SIDEWALK_HEIGHT + 0.018, 4.4)
		drive.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drive)

		var yaw := float(_rng.randi_range(0, 3)) * PI * 0.5
		var house_tints := [
			Color(1.00, 0.98, 0.94),
			Color(0.92, 0.98, 0.93),
			Color(0.94, 0.96, 1.02),
			Color(1.03, 0.93, 0.87),
		]
		var tint: Color = house_tints[absi(bx * 7 + bz * 13) % house_tints.size()]
		_place_building("bldg_suburban", center + Vector3(0.0, SIDEWALK_HEIGHT, 0.0), yaw, tint, Vector3(9.0, 6.5, 8.6), false)

		# Yard trees for warm suburban silhouette
		_place_prop("prop_tree", center + Vector3(-4.6, SIDEWALK_HEIGHT, -4.4), _rng.randf_range(0.0, TAU), true, Vector2(2.2, 2.2), 95.0, Vector3(0.7, 3.5, 0.7))
		if (bx + bz) % 2 == 0:
			_place_prop("prop_tree", center + Vector3(4.7, SIDEWALK_HEIGHT, -4.2), _rng.randf_range(0.0, TAU), true, Vector2(2.1, 2.1), 95.0, Vector3(0.7, 3.5, 0.7))
		_populate_block_sidewalk_props(bx, bz, center, "suburban")
		return

	# Urban Downtown or Commercial Avenue block
	var slot_key := "bldg_brick"
	var col_size := Vector3(10.0, 10.5, 9.4)
	var pattern := absi(bx * 5 + bz * 3 + 11) % 4
	if is_downtown:
		match pattern:
			0:
				slot_key = "bldg_downtown"
				col_size = Vector3(10.6, 15.0, 10.6)
			1:
				slot_key = "bldg_brick"
				col_size = Vector3(9.9, 10.4, 9.3)
			2:
				slot_key = "bldg_corner"
				col_size = Vector3(9.5, 6.6, 8.9)
			_:
				slot_key = "bldg_downtown" if (bx + bz) % 2 == 0 else "bldg_brick"
				col_size = Vector3(10.5, 14.5, 10.5) if slot_key == "bldg_downtown" else Vector3(9.9, 10.4, 9.3)
	else:
		match pattern:
			0, 2:
				slot_key = "bldg_diner"
				col_size = Vector3(10.4, 5.2, 7.6)
			1:
				slot_key = "bldg_corner"
				col_size = Vector3(9.5, 6.6, 8.9)
			_:
				slot_key = "bldg_brick"
				col_size = Vector3(9.9, 10.4, 9.3)

	# Paved courtyard border around commercial buildings (never empty dirt)
	var apron := MeshInstance3D.new()
	var am := PlaneMesh.new()
	am.size = Vector2(BLOCK_SIZE - 2.2, BLOCK_SIZE - 2.2)
	apron.mesh = am
	apron.material_override = MaterialLibrary.get_plaza_material(Vector2(3.5, 3.5))
	apron.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.01, 0.0)
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)

	var b_yaw := float((absi(bx * 3 + bz * 5)) % 4) * PI * 0.5
	var urban_tints := [
		Color(1.00, 1.00, 1.00),
		Color(0.95, 0.97, 1.02),
		Color(1.03, 0.97, 0.92),
		Color(0.94, 0.93, 0.96),
		Color(1.02, 1.00, 0.94),
	]
	var b_tint: Color = urban_tints[absi(bx * 11 + bz * 17) % urban_tints.size()]
	var mirror_x := ((bx + bz) % 3 == 0)
	_place_building(slot_key, center + Vector3(0.0, SIDEWALK_HEIGHT, 0.0), b_yaw, b_tint, col_size, mirror_x)
	_populate_block_sidewalk_props(bx, bz, center, "downtown" if is_downtown else "commercial")


func _build_pocket_plaza(center: Vector3) -> void:
	# Intentional neighborhood seating plaza with pavers, shade trees, benches, vending & trash bin
	var pave := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(BLOCK_SIZE - 1.6, BLOCK_SIZE - 1.6)
	pave.mesh = pm
	pave.material_override = MaterialLibrary.get_plaza_material(Vector2(4.0, 4.0))
	pave.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.014, 0.0)
	pave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pave)

	# Central raised stone planter bed
	_add_raised_slab(center + Vector3(0.0, SIDEWALK_HEIGHT, 0.0), 4.6, 4.6, 0.42, MaterialLibrary.get_sidewalk_material(Vector2(1.5, 1.5)), true)
	var grass_top := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(4.1, 4.1)
	grass_top.mesh = gm
	grass_top.material_override = MaterialLibrary.get_grass_material(Vector2(1.5, 1.5))
	grass_top.position = center + Vector3(0.0, SIDEWALK_HEIGHT + 0.435, 0.0)
	grass_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_top)

	_place_prop("prop_tree", center + Vector3(0.0, SIDEWALK_HEIGHT + 0.42, 0.0), _rng.randf_range(0.0, TAU), true, Vector2(2.5, 2.5), 95.0, Vector3(0.7, 3.5, 0.7))
	_place_prop("prop_bench", center + Vector3(0.0, SIDEWALK_HEIGHT, 3.8), PI, true, Vector2(2.0, 1.0), 58.0, Vector3(1.8, 0.9, 0.7))
	_place_prop("prop_bench", center + Vector3(0.0, SIDEWALK_HEIGHT, -3.8), 0.0, true, Vector2(2.0, 1.0), 58.0, Vector3(1.8, 0.9, 0.7))
	_place_prop("prop_vending", center + Vector3(-4.6, SIDEWALK_HEIGHT, -2.5), PI * 0.5, true, Vector2(1.5, 1.2), 58.0, Vector3(1.1, 2.0, 0.8))
	_place_prop("prop_trashbin", center + Vector3(-4.6, SIDEWALK_HEIGHT, -0.9), 0.0, true, Vector2(0.95, 0.95), 55.0, Vector3(0.6, 1.1, 0.6))


func _place_building(slot_key: String, pos: Vector3, yaw: float, tint: Color, collider_size: Vector3, mirror_x: bool) -> void:
	var bldg := AssetResolver.instantiate_slot(slot_key)
	bldg.position = pos
	bldg.rotation.y = yaw
	if mirror_x:
		# Note: uniform negative X flips architectural symmetry cleanly on visual node;
		# collider remains positive-scale BoxShape3D so physics stays rock-solid.
		bldg.scale = Vector3(-1.0, _rng.randf_range(0.96, 1.06), 1.0)
	else:
		bldg.scale = Vector3(1.0, _rng.randf_range(0.95, 1.07), 1.0)
	MaterialLibrary.apply_pbr_and_variation(bldg, tint, true, 0.0)
	add_child(bldg)

	# Rotate collider dimensions when rotated 90/270 deg
	var rot_90 := (int(round(yaw / (PI * 0.5))) % 2) != 0
	var csize := Vector3(collider_size.z, collider_size.y, collider_size.x) if rot_90 else collider_size
	_add_box_collider(pos + Vector3(0.0, csize.y * 0.5, 0.0), csize, 1)


func _populate_block_sidewalk_props(bx: int, bz: int, center: Vector3, district: String) -> void:
	var edge := BLOCK_SIZE * 0.5 - 0.85

	# Streetlights on alternating corners (with individual variance)
	var light_corners := [
		[Vector3(edge, 0.0, edge), PI * 0.5],
		[Vector3(-edge, 0.0, -edge), -PI * 0.5],
	]
	if (bx + bz) % 2 == 0:
		light_corners = [
			[Vector3(-edge, 0.0, edge), 0.0],
			[Vector3(edge, 0.0, -edge), PI],
		]
	for lc in light_corners:
		_place_prop("prop_streetlight", center + lc[0] + Vector3(0.0, SIDEWALK_HEIGHT, 0.0), lc[1], false, Vector2(0.8, 0.8), 95.0, Vector3(0.38, 6.0, 0.38))

	# District-specific prop density & mix (breaks repetition across blocks)
	if district == "downtown":
		_place_prop("prop_vending", center + Vector3(5.8, SIDEWALK_HEIGHT, -1.8), PI * 0.5, true, Vector2(1.5, 1.15), 58.0, Vector3(1.1, 2.0, 0.8))
		_place_prop("prop_trashbin", center + Vector3(edge, SIDEWALK_HEIGHT, 2.6), _rng.randf_range(-0.2, 0.2), true, Vector2(0.95, 0.95), 54.0, Vector3(0.6, 1.1, 0.6))
		_place_prop("prop_hydrant", center + Vector3(-edge, SIDEWALK_HEIGHT, -3.4), _rng.randf_range(0.0, TAU), true, Vector2(0.75, 0.75), 54.0, Vector3(0.45, 0.9, 0.45))
		if (bx + bz) % 2 != 0:
			_place_prop("prop_bench", center + Vector3(-2.4, SIDEWALK_HEIGHT, edge - 0.35), 0.0, true, Vector2(2.0, 1.0), 58.0, Vector3(1.8, 0.9, 0.7))
	elif district == "commercial":
		_place_prop("prop_utility_pole", center + Vector3(-edge, SIDEWALK_HEIGHT, 4.2), PI * 0.5, false, Vector2(0.8, 0.8), 95.0, Vector3(0.4, 7.2, 0.4))
		_place_prop("prop_trashbin", center + Vector3(edge, SIDEWALK_HEIGHT, -2.5), _rng.randf_range(-0.2, 0.2), true, Vector2(0.95, 0.95), 54.0, Vector3(0.6, 1.1, 0.6))
		if (bx * 3 + bz) % 2 == 0:
			_place_prop("prop_vending", center + Vector3(-5.8, SIDEWALK_HEIGHT, 1.6), -PI * 0.5, true, Vector2(1.5, 1.15), 58.0, Vector3(1.1, 2.0, 0.8))
		else:
			_place_prop("prop_hydrant", center + Vector3(edge, SIDEWALK_HEIGHT, 3.6), _rng.randf_range(0.0, TAU), true, Vector2(0.75, 0.75), 54.0, Vector3(0.45, 0.9, 0.45))
	elif district == "suburban":
		_place_prop("prop_utility_pole", center + Vector3(edge, SIDEWALK_HEIGHT, -4.4), 0.0, false, Vector2(0.8, 0.8), 95.0, Vector3(0.4, 7.2, 0.4))
		_place_prop("prop_tree", center + Vector3(-edge + 0.3, SIDEWALK_HEIGHT, 3.2), _rng.randf_range(0.0, TAU), true, Vector2(2.2, 2.2), 95.0, Vector3(0.65, 3.4, 0.65))
		if (bx + bz) % 2 == 0:
			_place_prop("prop_hydrant", center + Vector3(edge, SIDEWALK_HEIGHT, 4.8), _rng.randf_range(0.0, TAU), true, Vector2(0.75, 0.75), 54.0, Vector3(0.45, 0.9, 0.45))


func _build_intersections_and_signals() -> void:
	# Place American cantilevered traffic signals at the 4 central landmark intersections
	var central_intersections := [
		Vector3(CELL_PITCH * 0.5, 0.0, CELL_PITCH * 0.5),
		Vector3(-CELL_PITCH * 0.5, 0.0, CELL_PITCH * 0.5),
		Vector3(CELL_PITCH * 0.5, 0.0, -CELL_PITCH * 0.5),
		Vector3(-CELL_PITCH * 0.5, 0.0, -CELL_PITCH * 0.5),
	]
	for ic in central_intersections:
		var corner_off := ROAD_WIDTH * 0.5 + 0.75
		_place_prop("prop_traffic_light", ic + Vector3(-corner_off, SIDEWALK_HEIGHT, -corner_off), PI * 0.5, false, Vector2(0.9, 0.9), 110.0, Vector3(0.42, 5.5, 0.42))
		_place_prop("prop_traffic_light", ic + Vector3(corner_off, SIDEWALK_HEIGHT, corner_off), -PI * 0.5, false, Vector2(0.9, 0.9), 110.0, Vector3(0.42, 5.5, 0.42))


func _build_outer_boulevard_boundary() -> void:
	# Keeps player & car inside the 5x5 city ring boulevard with realistic curbs, lawns & shade trees
	var outer_road_edge := 2.5 * CELL_PITCH + ROAD_WIDTH * 0.5  # 66.8m
	var strip_w := 12.0
	var span := outer_road_edge * 2.0 + strip_w * 2.0
	var grass_mat := MaterialLibrary.get_grass_material(Vector2(24.0, 3.0))
	var curb_mat := MaterialLibrary.get_sidewalk_material(Vector2(28.0, 1.0))

	var sides := [
		[Vector3(0.0, 0.0, -(outer_road_edge + strip_w * 0.5)), Vector3(span, 0.22, strip_w), Vector3(0.0, 0.0, -(outer_road_edge + 1.2)), Vector3(span, 3.5, 0.6)],
		[Vector3(0.0, 0.0, outer_road_edge + strip_w * 0.5), Vector3(span, 0.22, strip_w), Vector3(0.0, 0.0, outer_road_edge + 1.2), Vector3(span, 3.5, 0.6)],
		[Vector3(-(outer_road_edge + strip_w * 0.5), 0.0, 0.0), Vector3(strip_w, 0.22, span), Vector3(-(outer_road_edge + 1.2), 0.0, 0.0), Vector3(0.6, 3.5, span)],
		[Vector3(outer_road_edge + strip_w * 0.5, 0.0, 0.0), Vector3(strip_w, 0.22, span), Vector3(outer_road_edge + 1.2, 0.0, 0.0), Vector3(0.6, 3.5, span)],
	]
	for s in sides:
		_add_raised_slab(s[0], s[1].x, s[1].z, s[1].y, grass_mat, true)
		# Low architectural concrete retaining curb along outer edge
		_add_raised_slab(s[2], minf(s[3].x, span), minf(s[3].z, span), 0.48, curb_mat, true)
		# Invisible safety wall so fast cars never jump outside the city
		_add_box_collider(s[2] + Vector3(0.0, 2.2, 0.0), s[3], 1)

	# Perimeter boulevard trees for rich horizon framing
	for k in range(-5, 6):
		var offset := float(k) * 12.5 + _rng.randf_range(-1.8, 1.8)
		_place_prop("prop_tree", Vector3(offset, 0.22, -(outer_road_edge + 4.4)), _rng.randf_range(0.0, TAU), false, Vector2(2.4, 2.4), 130.0, Vector3.ZERO)
		_place_prop("prop_tree", Vector3(offset, 0.22, outer_road_edge + 4.4), _rng.randf_range(0.0, TAU), false, Vector2(2.4, 2.4), 130.0, Vector3.ZERO)
		_place_prop("prop_tree", Vector3(-(outer_road_edge + 4.4), 0.22, offset), _rng.randf_range(0.0, TAU), false, Vector2(2.4, 2.4), 130.0, Vector3.ZERO)
		_place_prop("prop_tree", Vector3(outer_road_edge + 4.4, 0.22, offset), _rng.randf_range(0.0, TAU), false, Vector2(2.4, 2.4), 130.0, Vector3.ZERO)


func _place_prop(
	slot_key: String,
	pos: Vector3,
	base_yaw: float,
	with_contact_shadow: bool,
	shadow_size: Vector2,
	vis_end: float,
	collider_size: Vector3
) -> void:
	var inst := AssetResolver.instantiate_slot(slot_key)
	inst.position = pos
	# Quality Standard §4: Per-instance variance (+/-10% scale, yaw jitter, +/-5% color tint)
	var scale_var := _rng.randf_range(0.90, 1.10)
	inst.scale = Vector3.ONE * scale_var
	var yaw_jitter := 0.14 if (slot_key == "prop_tree" or slot_key == "prop_trashbin") else 0.04
	inst.rotation.y = base_yaw + _rng.randf_range(-yaw_jitter, yaw_jitter)

	var tint := Color(
		_rng.randf_range(0.95, 1.05),
		_rng.randf_range(0.95, 1.05),
		_rng.randf_range(0.95, 1.05),
		1.0
	)
	MaterialLibrary.apply_pbr_and_variation(inst, tint, true, vis_end)
	add_child(inst)

	if with_contact_shadow:
		var cs := MaterialLibrary.create_contact_shadow_quad(shadow_size.x * scale_var, shadow_size.y * scale_var, 0.62)
		cs.position = pos + Vector3(0.0, 0.022, 0.0)
		cs.rotation.y = inst.rotation.y
		if vis_end > 0.0:
			cs.visibility_range_end = vis_end
		add_child(cs)

	if collider_size != Vector3.ZERO:
		_add_box_collider(pos + Vector3(0.0, collider_size.y * 0.5, 0.0), collider_size * scale_var, 4)


func _add_box_collider(pos: Vector3, size: Vector3, layer_bit: int) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer_bit
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
