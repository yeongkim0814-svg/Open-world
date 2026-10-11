class_name Island1km
extends Node3D
## 첫 섬 1km 시험 장면 (설계서 2026-10-12 8장): 구운 색칠 지도 → 구역 LOD 지형·바다·저수호 수면·표식 기둥.
## 퀘스트 오브젝트·식생·구조물은 아직 없음 (B·C). 디버그 패널 = UI/MapPanel.

const BAKED := "res://maps/first_island/baked/"
const TERRAIN := preload("res://shaders/style_terrain.gdshader")
const WATER := preload("res://shaders/style_water.gdshader")
const LAKE_LEVEL := 14.6
const LAKE_R := 48.0
const ZONE_KEYS := ["grass", "zone_broadleaf", "zone_conifer", "zone_wetland", "zone_highland", "sand", "zone_wasteland"]

var field: HeightField
var markers: Array = []
var model := Recovery.new()
var _terrain: ChunkedTerrain
var _map: RecoveryMap
var _env: Environment
var _sun: DirectionalLight3D
var _player: Node3D
var _start := Vector3.ZERO
var _placed := false
var _stats: Label
var _stat_t := 0.0


func _ready() -> void:
	markers = _read_markers()
	_build_environment()
	_build_terrain()
	field = _terrain.field
	_build_recovery()
	_build_water()
	_build_marker_poles()
	_build_panel()
	_player = get_node_or_null("Player") as Node3D
	for m in markers:
		if m.kind == "start":
			_start = Vector3(m.x, 0.0, m.z)
	if _player:
		_terrain.set_focus(_player)


func _process(dt: float) -> void:
	# 발밑 충돌이 생길 때까지 플레이어를 시작 위치에 붙잡아 둔다 (구역 충돌은 몇 프레임에 걸쳐 만들어짐).
	if _player and not _placed:
		_player.global_position = Vector3(_start.x, field.height_at(_start.x, _start.z) + 1.5, _start.z)
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_placed = _terrain.collision_ready()
	var r := _here()
	_env.fog_light_color = StylePalette.color("sky_horizon", r)
	_env.fog_density = lerpf(0.0011, 0.0006, r)
	_sun.light_color = Color(0.86, 0.89, 0.93).lerp(Color(1.0, 0.95, 0.85), r)
	_sun.light_energy = lerpf(0.9, 1.15, r)
	_stat_t -= dt
	if _stat_t <= 0.0 and _stats:
		_stat_t = 0.5
		var st := _terrain.stats()
		var cam := get_viewport().get_camera_3d()
		var p := cam.global_position if cam else Vector3.ZERO
		_stats.text = "FPS %d · 그리기 %d · 삼각형 %dk\n구역 %d · 대기 %d · 생성 %.1fms · 회복 %.2f\n위치 (%d, %d, %d)" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			st.chunks, st.pending, st.last_build_ms, r, p.x, p.y, p.z]


## 스크린샷 도구: 지형 구역이 아직 만들어지는 중이면 기다린다.
func busy() -> bool:
	return _terrain.stats().pending > 0


func set_preview_recovery(v: float) -> void:
	model.set_preview(v)
	_map.refresh()
	_map.step(1000.0)
	RenderingServer.global_shader_parameter_set("recovery_here", v)
	_process(0.0)


func _here() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	return _map.displayed_at(Vector2(cam.global_position.x, cam.global_position.z))


func _read_markers() -> Array:
	var f := FileAccess.open(BAKED + "markers.json", FileAccess.READ)
	if f == null:
		push_error("Island1km: markers.json 없음")
		return []
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Array else []


func _marker(kind: String) -> Dictionary:
	for m in markers:
		if m.kind == kind:
			return m
	return {}


func _tex(name: String) -> ImageTexture:
	var res = load(BAKED + name) if ResourceLoader.exists(BAKED + name) else null
	var img: Image = res if res is Image else (res.get_image() if res is Texture2D else null)
	return ImageTexture.create_from_image(img) if img else null


# ---------- 빌드 ----------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = (load("res://resources/style/style_env.tres") as Environment).duplicate(true)
	we.environment = _env
	add_child(we)
	var sky_mat := _env.sky.sky_material as ShaderMaterial
	for k in ["zenith", "horizon"]:
		sky_mat.set_shader_parameter(k + "_depleted", StylePalette.DEPLETED["sky_" + k])
		sky_mat.set_shader_parameter(k + "_restored", StylePalette.RESTORED["sky_" + k])
	sky_mat.set_shader_parameter("horizon_sharpness", 5.0)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 80.0
	_sun.shadow_normal_bias = 3.0
	add_child(_sun)


func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN
	for k in ["grass", "ground", "rock", "sand"]:
		mat.set_shader_parameter(k + "_depleted", StylePalette.DEPLETED[k])
		mat.set_shader_parameter(k + "_restored", StylePalette.RESTORED[k])
	var zd := PackedColorArray()
	var zr := PackedColorArray()
	for k in ZONE_KEYS:
		zd.append(StylePalette.DEPLETED[k])
		zr.append(StylePalette.RESTORED[k])
	mat.set_shader_parameter("use_zone_map", true)
	mat.set_shader_parameter("zone_map", _tex("zones.png"))
	mat.set_shader_parameter("path_map", _tex("paths.png"))
	mat.set_shader_parameter("map_rect", Vector4(-512, -512, 1024, 1024))
	mat.set_shader_parameter("zone_depleted", zd)
	mat.set_shader_parameter("zone_restored", zr)
	mat.set_shader_parameter("path_depleted", PackedColorArray([StylePalette.DEPLETED.path_dirt, StylePalette.DEPLETED.path_paved]))
	mat.set_shader_parameter("path_restored", PackedColorArray([StylePalette.RESTORED.path_dirt, StylePalette.RESTORED.path_paved]))
	mat.set_shader_parameter("sand_height", 1.8)
	_terrain = ChunkedTerrain.new()
	_terrain.name = "Terrain"
	_terrain.baked_dir = BAKED
	_terrain.material = mat
	add_child(_terrain)


func _build_recovery() -> void:
	model.add_region(&"island", Vector2.ZERO, 600.0)
	_map = RecoveryMap.new()
	_map.name = "RecoveryMap"
	_map.world_rect = Rect2(-512, -512, 1024, 1024)
	_map.model = model
	add_child(_map)
	_map.refresh()


func _water_mat(use_here: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER
	for k in ["shallow", "deep"]:
		m.set_shader_parameter(k + "_depleted", StylePalette.DEPLETED["water_" + k])
		m.set_shader_parameter(k + "_restored", StylePalette.RESTORED["water_" + k])
	m.set_shader_parameter("use_here", use_here)
	return m


## 정점색 R = 깊이(0~1)인 격자 수면.
func _water_grid(center: Vector2, half: float, cell: float, level: float, depth_scale: float, radius := INF) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := center.x - half + ix * cell
			var z0 := center.y - half + iz * cell
			if Vector2(x0 + cell * 0.5, z0 + cell * 0.5).distance_to(center) > radius:
				continue
			var quad := [Vector2(x0, z0), Vector2(x0 + cell, z0), Vector2(x0 + cell, z0 + cell), Vector2(x0, z0 + cell)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[idx]
				var d := clampf((level - field.height_at(p.x, p.y)) / depth_scale, 0.0, 1.0)
				st.set_color(Color(d, 0.0, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, level, p.y))
	return st.commit()


func _build_water() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = _water_grid(Vector2.ZERO, 3000.0, 32.0, 0.0, 3.0)
	sea.material_override = _water_mat(true)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var lk := _marker("lake")
	if lk.is_empty():
		return
	var c := Vector2(lk.x, lk.z)
	var lake := MeshInstance3D.new()
	lake.name = "LakeSurface"
	lake.mesh = _water_grid(c, LAKE_R + 2.0, 2.0, LAKE_LEVEL, 6.0, LAKE_R + 2.0)
	lake.material_override = _water_mat(false)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	var w := Water.new()   # 수영 판정 (그룹 "water")
	w.size = Vector3(LAKE_R * 2.0, LAKE_LEVEL + 6.0, LAKE_R * 2.0)
	w.position = Vector3(c.x, (LAKE_LEVEL - 6.0) * 0.5, c.y)
	add_child(w)


## 표식 위치에 색 기둥 (구조물이 들어오기 전 디버그용).
func _build_marker_poles() -> void:
	for m in markers:
		var col: Color = MapLegend.MARKERS.get(m.kind, Color.WHITE)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 24.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		cyl.material = mat
		mi.mesh = cyl
		mi.position = Vector3(m.x, field.height_at(m.x, m.z) + 12.0, m.z)
		mi.name = "Marker_%s" % m.kind
		add_child(mi)


func _build_panel() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	var box := VBoxContainer.new()
	box.name = "MapPanel"
	box.position = Vector2(16, 16)
	ui.add_child(box)
	_stats = Label.new()
	box.add_child(_stats)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(300, 40)
	slider.value_changed.connect(func(v): model.set_preview(v); _map.refresh())
	box.add_child(slider)
