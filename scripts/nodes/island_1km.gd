class_name Island1km
extends Node3D
## 첫 지역 시험 장면 (설계서 2026-10-12 8장·11장): 구운 색칠 지도 → 구역 LOD 지형·바다·저수호 수면·표식 기둥.
## 지도 크기·높이 범위는 baked/meta.json, 저수호 수위는 markers.json 의 crest(둑 꼭대기) 기준.
## 식생·바위 = VegetationField (설계서 2026-10-13). 퀘스트 오브젝트·구조물은 아직 없음 (C). 디버그 패널 = UI/MapPanel.

const BAKED := "res://maps/first_island/baked/"
const TERRAIN := preload("res://shaders/style_terrain.gdshader")
const WATER := preload("res://shaders/style_water.gdshader")
const LEVEL_BELOW_CREST := 1.4   ## 첫 수위 = 둑 꼭대기 − 1.4m (수문 1개당 −3.9m는 C)
const LAKE_DEPTH := 22.0
const ZONE_KEYS := ["grass", "zone_broadleaf", "zone_conifer", "zone_wetland", "zone_highland", "sand", "zone_wasteland"]

var field: HeightField
var world := 1024.0
var map_px := 1024
var markers: Array = []
var model := Recovery.new()
var _terrain: ChunkedTerrain
var veg: VegetationField
static var _veg_catalog: VegCatalog   ## 메시 생성이 무거워 장면을 다시 열어도 재사용
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
	_read_meta()
	_build_environment()
	_build_terrain()
	field = _terrain.field
	_build_recovery()
	_build_water()
	_build_vegetation()
	_build_marker_poles()
	_build_panel()
	_player = get_node_or_null("Player") as Node3D
	for m in markers:
		if m.kind == "start":
			_start = Vector3(m.x, 0.0, m.z)
	if _player:
		_terrain.set_focus(_player)
		if veg:
			veg.collision_target = _player


func _process(dt: float) -> void:
	# 발밑 충돌이 생길 때까지 플레이어를 시작 위치에 붙잡아 둔다 (구역 충돌은 몇 프레임에 걸쳐 만들어짐).
	if _player and not _placed:
		_player.global_position = Vector3(_start.x, field.height_at(_start.x, _start.z) + 1.5, _start.z)
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_placed = _terrain.collision_ready()
	var r := _here()
	_env.fog_light_color = StylePalette.color("sky_horizon", r)
	_env.fog_density = lerpf(0.0011, 0.0006, r) * clampf(1024.0 / world, 0.35, 1.0)   # 넓은 지도일수록 옅게 (2km: 약 절반)
	_sun.light_color = Color(0.86, 0.89, 0.93).lerp(Color(1.0, 0.95, 0.85), r)
	_sun.light_energy = lerpf(0.9, 1.15, r)
	_stat_t -= dt
	if _stat_t <= 0.0 and _stats:
		_stat_t = 0.5
		var st := _terrain.stats()
		var cam := get_viewport().get_camera_3d()
		var p := cam.global_position if cam else Vector3.ZERO
		var vs := veg.stats() if veg else {"blocks": 0, "instances": 0, "collision_blocks": 0, "pending": 0}
		_stats.text = "FPS %d · 그리기 %d · 삼각형 %dk\n구역 %d · 대기 %d · 생성 %.1fms · 회복 %.2f\n식생 블록 %d · 개체 %d · 충돌 %d · 대기 %d\n위치 (%d, %d, %d)" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			st.chunks, st.pending, st.last_build_ms, r,
			vs.blocks, vs.instances, vs.collision_blocks, vs.pending, p.x, p.y, p.z]


## 스크린샷 도구: 지형 구역·식생 블록이 아직 만들어지는 중이면 기다린다.
func busy() -> bool:
	return _terrain.stats().pending > 0 or (veg != null and veg.busy())


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


func _read_meta() -> void:
	var f := FileAccess.open(BAKED + "meta.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		world = float(d.get("world", world))
		map_px = int(d.get("size", map_px))


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


func _img(name: String) -> Image:
	var res = load(BAKED + name) if ResourceLoader.exists(BAKED + name) else null
	return res if res is Image else (res.get_image() if res is Texture2D else null)


## 모양 해자 칸 값: 0 없음, 1 물, 2 섬 (baked/moat.png, 굽기 관례 픽셀)
func _moat_at(img: Image, x: float, z: float) -> int:
	var n := img.get_width()
	var v := img.get_pixel(clampi(roundi((x / world + 0.5) * (n - 1)), 0, n - 1), clampi(roundi((z / world + 0.5) * (n - 1)), 0, n - 1)).r8
	return 2 if v >= 192 else (1 if v >= 64 else 0)


func _tex(name: String) -> ImageTexture:
	var img := _img(name)
	return ImageTexture.create_from_image(img) if img else null


func _map_cfg() -> Dictionary:
	var f := FileAccess.open("res://maps/first_island/map.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


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
	mat.set_shader_parameter("map_rect", Vector4(-world * 0.5, -world * 0.5, world, world))
	mat.set_shader_parameter("map_px", float(map_px))
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
	if _terrain.field == null:
		_terrain.load_map()   # 트리 밖(헤드리스 테스트)에서도 높이장이 준비되게


func _build_recovery() -> void:
	model.add_region(&"island", Vector2.ZERO, world * 0.75)
	_map = RecoveryMap.new()
	_map.name = "RecoveryMap"
	_map.world_rect = Rect2(-world * 0.5, -world * 0.5, world, world)
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
## inside (선택): (x, z) → bool — 칸 가운데나 모서리 하나라도 물이면 그 칸을 그린다 (벽 안쪽까지 덮게).
func _water_grid(center: Vector2, half: float, cell: float, level: float, depth_scale: float, radius := INF, inside := Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := center.x - half + ix * cell
			var z0 := center.y - half + iz * cell
			if Vector2(x0 + cell * 0.5, z0 + cell * 0.5).distance_to(center) > radius:
				continue
			if inside.is_valid() and not (inside.call(x0 + cell * 0.5, z0 + cell * 0.5) or inside.call(x0, z0)
					or inside.call(x0 + cell, z0) or inside.call(x0, z0 + cell) or inside.call(x0 + cell, z0 + cell)):
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
	sea.mesh = _water_grid(Vector2.ZERO, world * 1.5, 64.0, 0.0, 3.0)
	sea.material_override = _water_mat(true)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var sea_w := Water.new()   # 바다 수영 판정 (수면 0m)
	sea_w.name = "SeaWater"
	sea_w.size = Vector3(world + 100.0, 40.0, world + 100.0)
	sea_w.position = Vector3(0.0, -20.0, 0.0)
	add_child(sea_w)
	_build_world_edge()
	var lk := _marker("lake")
	if lk.is_empty():
		return
	var c := Vector2(lk.x, lk.z)
	var crest := float(lk.get("crest", 16.0))
	var lake_r := float(lk.get("radius", 48.0))   ## 수면 반경 (굽기 cfg lake_radius) — 모양 해자는 둘레 원 반경
	var level := crest - LEVEL_BELOW_CREST
	var floor_y := crest - LAKE_DEPTH
	var in_moat := Callable()
	if lk.get("shaped", false):
		var moat := _img("moat.png")
		if moat:
			in_moat = func(x: float, z: float) -> bool: return _moat_at(moat, x, z) == 1
	var lake := MeshInstance3D.new()
	lake.name = "LakeSurface"
	lake.mesh = _water_grid(c, lake_r + 2.0, 2.0, level, 6.0, lake_r + 2.0, in_moat)
	lake.material_override = _water_mat(false)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	var w := Water.new()   # 수영 판정 (그룹 "water")
	w.size = Vector3(lake_r * 2.0, level - floor_y, lake_r * 2.0)
	w.circular = true
	w.area = in_moat
	w.position = Vector3(c.x, (level + floor_y) * 0.5, c.y)
	add_child(w)


## 식생·바위: 구운 구역·길 지도 + 표식 + map.json 반경. 물 판정은 VegetationField 가 그룹 "water" 로 붙인다.
func _build_vegetation() -> void:
	var zones := _img("zones.png")
	var paths := _img("paths.png")
	if zones == null or paths == null:
		push_error("Island1km: zones/paths 없음 — 식생 생략")
		return
	var mc := _map_cfg()
	var cfg := {}
	for k in ["tower_radius", "lake_radius", "summit_radius"]:
		if mc.has(k):
			cfg[k] = float(mc[k])
	if _marker("lake").get("shaped", false):
		var moat := _img("moat.png")
		if moat:
			cfg["moat"] = moat
	if _veg_catalog == null:
		_veg_catalog = VegCatalog.new()
	var ctx := VegContext.new(field, zones, paths, markers, cfg)
	veg = VegetationField.new()
	veg.name = "Vegetation"
	add_child(veg)
	veg.setup(ctx, _veg_catalog)


## 지도 가장자리 보이지 않는 벽 — 밖에는 지형·충돌이 없다 (서·북은 나중에 세계가 이어지면 없앤다).
func _build_world_edge() -> void:
	var body := StaticBody3D.new()
	body.name = "WorldEdge"
	for i in 4:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along := i < 2
		box.size = Vector3(world + 20.0, 600.0, 20.0) if along else Vector3(20.0, 600.0, world + 20.0)
		col.shape = box
		var sgn := -1.0 if i % 2 == 0 else 1.0
		var e := world * 0.5 - 2.0
		col.position = Vector3(0.0, 100.0, sgn * e) if along else Vector3(sgn * e, 100.0, 0.0)
		body.add_child(col)
	add_child(body)


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
