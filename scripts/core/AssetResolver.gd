class_name AssetResolver
extends RefCounted
## Two-tier asset loader:
## 1) Priority-loads downloaded CC0 KayKit / Kenney GLTF/GLB assets from res://assets/cc0/
## 2) Falls back seamlessly to bundled sculpted PBR GLB models in res://assets/models/

static var _scene_cache: Dictionary = {}

const SLOT_CANDIDATES := {
	"bldg_downtown": [
		"res://assets/cc0/kenney_city_commercial/Models/GLB format/building-a.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/building_A.gltf",
		"res://assets/models/bldg_downtown_tower.glb",
	],
	"bldg_brick": [
		"res://assets/cc0/kenney_city_commercial/Models/GLB format/building-c.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/building_C.gltf",
		"res://assets/models/bldg_brick_midrise.glb",
	],
	"bldg_corner": [
		"res://assets/cc0/kenney_city_commercial/Models/GLB format/building-e.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/building_E.gltf",
		"res://assets/models/bldg_corner_shop.glb",
	],
	"bldg_suburban": [
		"res://assets/cc0/kenney_city_suburban/Models/GLB format/building-type-a.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/building_B.gltf",
		"res://assets/models/bldg_suburban_house.glb",
	],
	"bldg_diner": [
		"res://assets/cc0/kenney_city_commercial/Models/GLB format/building-g.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/building_D.gltf",
		"res://assets/models/bldg_diner_market.glb",
	],
	"car_body": [
		"res://assets/models/car_body.glb",
	],
	"car_wheel": [
		"res://assets/models/car_wheel.glb",
	],
	"prop_streetlight": [
		"res://assets/cc0/kenney_city_roads/Models/GLB format/light-curved.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/streetlight.gltf",
		"res://assets/models/prop_streetlight.glb",
	],
	"prop_traffic_light": [
		"res://assets/cc0/kenney_city_roads/Models/GLB format/light-square.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/trafficlight_A.gltf",
		"res://assets/models/prop_traffic_light.glb",
	],
	"prop_bench": [
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/bench.gltf",
		"res://assets/models/prop_bench.glb",
	],
	"prop_tree": [
		"res://assets/cc0/kenney_city_suburban/Models/GLB format/tree-large.glb",
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/bush.gltf",
		"res://assets/models/prop_tree.glb",
	],
	"prop_hydrant": [
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/firehydrant.gltf",
		"res://assets/models/prop_hydrant.glb",
	],
	"prop_vending": [
		"res://assets/models/prop_vending.glb",
	],
	"prop_trashbin": [
		"res://assets/cc0/kaykit_city_builder/Assets/gltf/dumpster.gltf",
		"res://assets/models/prop_trashbin.glb",
	],
	"prop_utility_pole": [
		"res://assets/models/prop_utility_pole.glb",
	],
	"landmark_fountain": [
		"res://assets/models/landmark_clock_fountain.glb",
	],
}


static func instantiate_slot(slot_key: String) -> Node3D:
	var scene := _get_packed_scene(slot_key)
	if scene != null:
		var inst := scene.instantiate()
		if inst is Node3D:
			return inst
	return Node3D.new()


static func _get_packed_scene(slot_key: String) -> PackedScene:
	if _scene_cache.has(slot_key):
		return _scene_cache[slot_key]
	var candidates: Array = SLOT_CANDIDATES.get(slot_key, [])
	for path in candidates:
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			if packed != null:
				_scene_cache[slot_key] = packed
				return packed
	_scene_cache[slot_key] = null
	return null
