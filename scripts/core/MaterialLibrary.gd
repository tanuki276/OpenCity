class_name MaterialLibrary
extends RefCounted
## Centralized PBR material factory ensuring mipmaps, anisotropic filtering,
## real textures, per-instance color variation, and AO contact shadow quads.

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		_tex_cache[path] = tex
		return tex
	return null


static func make_pbr_material(
	key: String,
	albedo_path: String,
	normal_path: String = "",
	roughness_path: String = "",
	albedo_tint: Color = Color.WHITE,
	roughness_val: float = 0.85,
	metallic_val: float = 0.0,
	uv_scale: Vector3 = Vector3.ONE,
	normal_scale: float = 1.0
) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo_tint
	mat.roughness = roughness_val
	mat.metallic = metallic_val
	mat.uv1_scale = uv_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	if albedo_path != "":
		var a_tex := _load_tex(albedo_path)
		if a_tex:
			mat.albedo_texture = a_tex
	if normal_path != "":
		var n_tex := _load_tex(normal_path)
		if n_tex:
			mat.normal_enabled = true
			mat.normal_texture = n_tex
			mat.normal_scale = normal_scale
	if roughness_path != "":
		var r_tex := _load_tex(roughness_path)
		if r_tex:
			mat.roughness_texture = r_tex
			mat.roughness = 1.0

	_mat_cache[key] = mat
	return mat


static func get_road_material(variant: String = "lane", uv_repeat: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var tex_path := "res://assets/textures/asphalt_lane_albedo.png"
	if variant == "plain":
		tex_path = "res://assets/textures/asphalt_albedo.png"
	elif variant == "crosswalk":
		tex_path = "res://assets/textures/road_crosswalk_albedo.png"
	var key := "road_%s_%.2f_%.2f" % [variant, uv_repeat.x, uv_repeat.y]
	return make_pbr_material(
		key,
		tex_path,
		"res://assets/textures/asphalt_normal.png",
		"res://assets/textures/asphalt_roughness.png",
		Color(0.96, 0.96, 0.97, 1.0),
		0.88,
		0.0,
		Vector3(uv_repeat.x, uv_repeat.y, 1.0),
		0.85
	)


static func get_sidewalk_material(uv_repeat: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var key := "sidewalk_%.2f_%.2f" % [uv_repeat.x, uv_repeat.y]
	return make_pbr_material(
		key,
		"res://assets/textures/sidewalk_albedo.png",
		"res://assets/textures/sidewalk_normal.png",
		"res://assets/textures/sidewalk_roughness.png",
		Color(0.98, 0.97, 0.95, 1.0),
		0.86,
		0.0,
		Vector3(uv_repeat.x, uv_repeat.y, 1.0),
		0.75
	)


static func get_plaza_material(uv_repeat: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var key := "plaza_%.2f_%.2f" % [uv_repeat.x, uv_repeat.y]
	return make_pbr_material(
		key,
		"res://assets/textures/plaza_paver_albedo.png",
		"res://assets/textures/plaza_paver_normal.png",
		"res://assets/textures/plaza_paver_roughness.png",
		Color.WHITE,
		0.82,
		0.0,
		Vector3(uv_repeat.x, uv_repeat.y, 1.0),
		0.85
	)


static func get_grass_material(uv_repeat: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var key := "grass_%.2f_%.2f" % [uv_repeat.x, uv_repeat.y]
	return make_pbr_material(
		key,
		"res://assets/textures/grass_albedo.png",
		"res://assets/textures/grass_normal.png",
		"",
		Color(0.95, 0.97, 0.92, 1.0),
		0.92,
		0.0,
		Vector3(uv_repeat.x, uv_repeat.y, 1.0),
		0.65
	)


static func get_contact_shadow_material(opacity: float = 0.72) -> StandardMaterial3D:
	var key := "contact_shadow_%.2f" % opacity
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _load_tex("res://assets/textures/contact_shadow.png")
	mat.albedo_color = Color(1.0, 1.0, 1.0, opacity)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_cache[key] = mat
	return mat


static func create_contact_shadow_quad(width: float, depth: float, opacity: float = 0.72) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, depth)
	quad.orientation = PlaneMesh.FACE_Y
	mi.mesh = quad
	mi.material_override = get_contact_shadow_material(opacity)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.025
	mi.name = "ContactShadow"
	return mi


static func _material_for_slot(slot_name: String) -> StandardMaterial3D:
	match slot_name:
		"mat_concrete":
			return get_sidewalk_material(Vector2(1.0, 1.0))
		"mat_brick_red":
			return make_pbr_material(
				"slot_brick_red",
				"res://assets/textures/brick_red_albedo.png",
				"res://assets/textures/brick_normal.png",
				"res://assets/textures/brick_roughness.png",
				Color.WHITE, 0.88, 0.0, Vector3.ONE, 0.95
			)
		"mat_brick_tan":
			return make_pbr_material(
				"slot_brick_tan",
				"res://assets/textures/brick_tan_albedo.png",
				"res://assets/textures/brick_normal.png",
				"res://assets/textures/brick_roughness.png",
				Color.WHITE, 0.88, 0.0, Vector3.ONE, 0.90
			)
		"mat_stucco_cream":
			return make_pbr_material(
				"slot_stucco_cream",
				"res://assets/textures/stucco_cream_albedo.png",
				"res://assets/textures/stucco_normal.png",
				"res://assets/textures/stucco_roughness.png",
				Color.WHITE, 0.84, 0.0, Vector3.ONE, 0.65
			)
		"mat_stucco_terracotta":
			return make_pbr_material(
				"slot_stucco_terracotta",
				"res://assets/textures/stucco_terracotta_albedo.png",
				"res://assets/textures/stucco_normal.png",
				"res://assets/textures/stucco_roughness.png",
				Color.WHITE, 0.84, 0.0, Vector3.ONE, 0.65
			)
		"mat_stucco_slate":
			return make_pbr_material(
				"slot_stucco_slate",
				"res://assets/textures/stucco_slate_albedo.png",
				"res://assets/textures/stucco_normal.png",
				"res://assets/textures/stucco_roughness.png",
				Color.WHITE, 0.80, 0.0, Vector3.ONE, 0.60
			)
		"mat_stucco_sage":
			return make_pbr_material(
				"slot_stucco_sage",
				"res://assets/textures/stucco_sage_albedo.png",
				"res://assets/textures/stucco_normal.png",
				"res://assets/textures/stucco_roughness.png",
				Color.WHITE, 0.84, 0.0, Vector3.ONE, 0.65
			)
		"mat_commercial_glass":
			return make_pbr_material(
				"slot_commercial_glass",
				"res://assets/textures/commercial_glass_albedo.png",
				"res://assets/textures/commercial_glass_normal.png",
				"res://assets/textures/commercial_glass_roughness.png",
				Color.WHITE, 0.14, 0.18, Vector3.ONE, 0.55
			)
		"mat_roof_gravel", "mat_roof_shingle":
			var tint := Color(0.75, 0.72, 0.69) if slot_name == "mat_roof_gravel" else Color(0.45, 0.38, 0.34)
			return make_pbr_material(
				"slot_" + slot_name,
				"res://assets/textures/roof_gravel_albedo.png",
				"res://assets/textures/roof_gravel_normal.png",
				"",
				tint, 0.92, 0.0, Vector3.ONE, 0.80
			)
		"mat_bark":
			return make_pbr_material(
				"slot_bark",
				"res://assets/textures/bark_albedo.png",
				"res://assets/textures/bark_normal.png",
				"",
				Color.WHITE, 0.92, 0.0, Vector3.ONE, 1.0
			)
		"mat_foliage":
			return make_pbr_material(
				"slot_foliage",
				"res://assets/textures/foliage_albedo.png",
				"res://assets/textures/foliage_normal.png",
				"",
				Color.WHITE, 0.86, 0.0, Vector3.ONE, 0.8
			)
		"mat_tire":
			return make_pbr_material(
				"slot_tire",
				"res://assets/textures/tire_tread_albedo.png",
				"res://assets/textures/tire_tread_normal.png",
				"",
				Color.WHITE, 0.85, 0.05, Vector3.ONE, 0.9
			)
		_:
			return null


static func apply_pbr_and_variation(
	root: Node,
	tint_color: Color = Color.WHITE,
	cast_shadows: bool = true,
	visibility_end: float = 0.0
) -> void:
	## Walks an instantiated GLB scene, upgrades bundled material slots with full
	## mipmapped PBR textures, applies subtle color variance, and enforces shadow casting.
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if cast_shadows
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			if visibility_end > 0.0:
				mi.visibility_range_end = visibility_end
				mi.visibility_range_end_margin = 6.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

			var mesh := mi.mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var orig := mesh.surface_get_material(s)
				var chosen: StandardMaterial3D = null
				if orig != null:
					chosen = _material_for_slot(orig.resource_name)
				if chosen == null and orig is StandardMaterial3D:
					var dup := orig.duplicate() as StandardMaterial3D
					dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if tint_color != Color.WHITE:
						dup.albedo_color = dup.albedo_color * tint_color
					mi.set_surface_override_material(s, dup)
				elif chosen != null:
					if tint_color != Color.WHITE:
						var tinted := chosen.duplicate() as StandardMaterial3D
						tinted.albedo_color = tinted.albedo_color * tint_color
						mi.set_surface_override_material(s, tinted)
					else:
						mi.set_surface_override_material(s, chosen)
