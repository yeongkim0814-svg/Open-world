class_name StyleTest
extends Node3D
## 스타일 테스트 씬 (설계서 7장): 코드 생성 섬·바위·식생·폐허·구름·원경·물 + 회복 슬라이더.
## 모든 메시와 배치는 시작할 때 시드로 만든다 (사진 텍스처 없음). 디버그 UI = UI/StylePanel.

const LIT := preload("res://shaders/style_lit.gdshader")
const TERRAIN := preload("res://shaders/style_terrain.gdshader")
const FOLIAGE := preload("res://shaders/style_foliage.gdshader")
const WATER := preload("res://shaders/style_water.gdshader")
const SEED := 3
const RUIN_POS := Vector2(-24.0, -4.0)
const SEA_LEVEL := 0.0
const LIFE_MAX := 40

var field: HeightField
var model := Recovery.new()
var _map: RecoveryMap
var _env: Environment
var _sun: DirectionalLight3D
var _terrain_mat: ShaderMaterial
var _life: CPUParticles3D
var _stats: Label
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _stat_t := 0.0
var _life_n := -1


func _ready() -> void:
	_rng.seed = SEED
	_noise.seed = SEED + 11
	_noise.frequency = 0.04
	field = HeightField.new(TestIslandGen.image(129, SEED), TestIslandGen.WORLD, TestIslandGen.MIN_H, TestIslandGen.MAX_H)
	_build_environment()
	_sync_sky()
	_build_recovery()
	_build_terrain()
	_build_water()
	_build_rocks()
	_build_trees()
	_build_grass()
	_build_ruin()
	_build_clouds()
	_build_ridges()
	_build_life()
	_build_panel()
	var player := get_node_or_null("Player") as Node3D
	if player:
		player.global_position = Vector3(0.0, field.height_at(0.0, 24.0) + 1.0, 24.0)


func _process(dt: float) -> void:
	var r := _here()
	_env.fog_light_color = StylePalette.color("sky_horizon", r)
	_env.fog_density = lerpf(0.0016, 0.0009, r)
	_sun.light_color = Color(0.86, 0.89, 0.93).lerp(Color(1.0, 0.95, 0.85), r)
	_sun.light_energy = lerpf(0.9, 1.15, r)
	var want := 0 if r < 0.3 else maxi(1, int(LIFE_MAX * r / 5.0) * 5)   # 5개 단위 (amount 변경은 재시작이라 자주 바꾸지 않음)
	if want != _life_n:
		_life_n = want
		_life.emitting = want > 0
		if want > 0:
			_life.amount = want
	_stat_t -= dt
	if _stat_t <= 0.0 and _stats:
		_stat_t = 0.5
		_stats.text = "FPS %d · 그리기 %d · 삼각형 %dk · 회복 %.2f" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), r]


## 스크린샷·슬라이더용: 섬 전체를 즉시 회복값 v로.
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


# ---------- 재질 ----------

func _lit(key: String, light := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIT
	m.set_shader_parameter("color_depleted", StylePalette.DEPLETED[key] * light)
	m.set_shader_parameter("color_restored", StylePalette.RESTORED[key] * light)
	return m


func _foliage(body: String, tip: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE
	m.set_shader_parameter("color_depleted", StylePalette.DEPLETED[body])
	m.set_shader_parameter("color_restored", StylePalette.RESTORED[body])
	m.set_shader_parameter("tip_depleted", StylePalette.DEPLETED[tip])
	m.set_shader_parameter("tip_restored", StylePalette.RESTORED[tip])
	m.set_shader_parameter("flower_depleted", StylePalette.DEPLETED.flower)
	m.set_shader_parameter("flower_restored", StylePalette.RESTORED.flower)
	return m


# ---------- 환경·회복 ----------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = (load("res://resources/style/style_env.tres") as Environment).duplicate(true)
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 60.0
	_sun.shadow_normal_bias = 3.0
	add_child(_sun)


## 하늘 지평선 = 안개색 (팔레트 한 곳에서), 천정 변화는 완만하게.
func _sync_sky() -> void:
	var sky_mat := _env.sky.sky_material as ShaderMaterial
	for k in ["zenith", "horizon"]:
		sky_mat.set_shader_parameter(k + "_depleted", StylePalette.DEPLETED["sky_" + k])
		sky_mat.set_shader_parameter(k + "_restored", StylePalette.RESTORED["sky_" + k])
	sky_mat.set_shader_parameter("horizon_sharpness", 5.0)


func _build_recovery() -> void:
	model.add_region(&"test", Vector2.ZERO, 70.0)
	_map = RecoveryMap.new()
	_map.name = "RecoveryMap"
	_map.model = model
	add_child(_map)
	_map.refresh()


# ---------- 지형·물 ----------

func _build_terrain() -> void:
	var mesh := TerrainMesh.build(field, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN
	for k in ["grass", "ground", "rock", "sand"]:
		_terrain_mat.set_shader_parameter(k + "_depleted", StylePalette.DEPLETED[k])
		_terrain_mat.set_shader_parameter(k + "_restored", StylePalette.RESTORED[k])
	_terrain_mat.set_shader_parameter("flat_shading", true)
	mi.material_override = _terrain_mat
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## 정점색 R = 깊이(0~1)인 격자 수면.
func _water_grid(center: Vector2, half: float, cell: float, level: float, depth_scale: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := center.x - half + ix * cell
			var z0 := center.y - half + iz * cell
			var quad := [Vector2(x0, z0), Vector2(x0 + cell, z0), Vector2(x0 + cell, z0 + cell), Vector2(x0, z0 + cell)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[idx]
				var d := clampf((level - field.height_at(p.x, p.y)) / depth_scale, 0.0, 1.0)
				st.set_color(Color(d, 0.0, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, level, p.y))
	return st.commit()


func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("shallow_depleted", StylePalette.DEPLETED.water_shallow)
	m.set_shader_parameter("shallow_restored", StylePalette.RESTORED.water_shallow)
	m.set_shader_parameter("deep_depleted", StylePalette.DEPLETED.water_deep)
	m.set_shader_parameter("deep_restored", StylePalette.RESTORED.water_deep)
	return m


func _build_water() -> void:
	var mat := _water_mat()
	var pond := MeshInstance3D.new()
	pond.name = "Pond"
	pond.mesh = _water_grid(TestIslandGen.POND_CENTER, 14.0, 1.0, TestIslandGen.POND_LEVEL, 2.0)
	pond.material_override = mat
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = _water_grid(Vector2.ZERO, 2400.0, 40.0, SEA_LEVEL, 2.5)
	var sea_mat := mat.duplicate() as ShaderMaterial
	sea_mat.set_shader_parameter("use_here", true)
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var w := Water.new()   # 수영 판정용 (그룹 "water")
	w.size = Vector3(TestIslandGen.POND_R * 2.0, 3.0, TestIslandGen.POND_R * 2.0)
	w.position = Vector3(TestIslandGen.POND_CENTER.x, TestIslandGen.POND_LEVEL - 1.5, TestIslandGen.POND_CENTER.y)
	add_child(w)


# ---------- 배치 도구 ----------

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, field.height_at(x, z), z)


func _land_ok(x: float, z: float, min_ny: float) -> bool:
	var h := field.height_at(x, z)
	if h < TestIslandGen.POND_LEVEL + 0.3 or field.normal_at(x, z).y < min_ny:
		return false
	if Vector2(x, z).distance_to(TestIslandGen.POND_CENTER) < TestIslandGen.POND_R + 1.5:
		return false
	return Vector2(x, z).distance_to(RUIN_POS) > 9.0


func _multimesh(mesh: Mesh, xforms: Array, custom := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = true   # 끄면 인스턴스 색이 정점색을 곱해 어두워진다
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, Color.WHITE)
		if custom:
			mm.set_instance_custom_data(i, Color(_rng.randf(), 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


func _xf(pos: Vector3, s: float, tilt := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU)
	if tilt > 0.0:
		b = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(-tilt, tilt)) * b
	return Transform3D(b.scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s)), pos)


# ---------- 바위 ----------

func _build_rocks() -> void:
	var mat := _lit("rock")
	var meshes := []
	for kind in 3:
		for s in 2:
			var m := RockGen.build(SEED * 10 + s, kind)
			m.surface_set_material(0, mat)
			meshes.append(m)
	var groups := []
	for i in meshes.size():
		groups.append([])
	# 경사·절벽 아래에 흩뿌림 (작은 것 많이, 큰 것 적게)
	for i in 160:
		var x := _rng.randf_range(-50, 50)
		var z := _rng.randf_range(-50, 50)
		var ny := field.normal_at(x, z).y
		if field.height_at(x, z) < 0.6 or ny > 0.93 or Vector2(x, z).distance_to(RUIN_POS) < 6.0:
			continue
		var s := _rng.randf_range(0.4, 1.4) * (1.6 if ny < 0.7 else 1.0)
		groups[_rng.randi() % meshes.size()].append(_xf(_ground(x, z) + Vector3.DOWN * s * 0.25, s, 0.4))
	for i in meshes.size():
		if not groups[i].is_empty():
			_multimesh(meshes[i], groups[i])
	# 절벽 가장자리 큰 덩어리 (실루엣) + 단순 충돌
	for p in [Vector2(-30, -16), Vector2(-4, -15), Vector2(4, -20), Vector2(-40, -22), Vector2(-17, -30)]:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[_rng.randi() % meshes.size()]
		var s := _rng.randf_range(3.0, 5.0)
		mi.transform = _xf(_ground(p.x, p.y) + Vector3.DOWN * s * 0.3, s, 0.25)
		add_child(mi)
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = s * 0.45
		col.shape = sph
		body.position = mi.position + Vector3.UP * s * 0.2
		body.add_child(col)
		add_child(body)


# ---------- 식생 ----------

func _build_trees() -> void:
	var trunk := _lit("ground", 0.55)
	var leaves := _foliage("foliage", "grass_tip")
	leaves.set_shader_parameter("density_depleted", 1.0)   # 나무는 회복 전에도 서 있다 (색·바람만 변화)
	leaves.set_shader_parameter("height_depleted", 1.0)    # 잎이 줄기에서 떨어지지 않게
	leaves.set_shader_parameter("wind_strength", 0.02)
	leaves.set_shader_parameter("fade_start", 100000.0)
	leaves.set_shader_parameter("fade_end", 100001.0)
	var meshes := []
	for kind in 3:
		var m := TreeGen.build(SEED + kind * 7, kind)
		m.surface_set_material(0, trunk)
		m.surface_set_material(1, leaves)
		meshes.append(m)
	var groups := [[], [], []]
	for i in 220:
		var x := _rng.randf_range(-46, 46)
		var z := _rng.randf_range(-46, 46)
		if _noise.get_noise_2d(x * 0.6, z * 0.6) < 0.25 or not _land_ok(x, z, 0.85):
			continue
		var kind := _rng.randi() % 3
		groups[kind].append(_xf(_ground(x, z), _rng.randf_range(0.8, 1.3), 0.08))
	for k in 3:
		if not groups[k].is_empty():
			_multimesh(meshes[k], groups[k], true)


func _build_grass() -> void:
	var mat := _foliage("grass", "grass_tip")
	var meshes := []
	for kind in 3:
		var m := GrassGen.build(kind)
		m.surface_set_material(0, mat)
		meshes.append(m)
	var groups := [[], [], []]
	var step := 0.7
	var z := -50.0
	while z < 50.0:
		var x := -50.0
		while x < 50.0:
			var px := x + _rng.randf_range(-0.35, 0.35) * step
			var pz := z + _rng.randf_range(-0.35, 0.35) * step
			var n := _noise.get_noise_2d(px * 1.7, pz * 1.7)
			if n > -0.15 and _land_ok(px, pz, 0.8):
				var kind := 2 if _rng.randf() < 0.025 else (1 if n > 0.25 else 0)
				groups[kind].append(_xf(_ground(px, pz), _rng.randf_range(0.9, 1.4)))
			x += step
		z += step
	for k in 3:
		var mmi := _multimesh(meshes[k], groups[k], true)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------- 폐허 ----------

func _place_part(mesh: ArrayMesh, mat: Material, xf: Transform3D) -> void:
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := mesh.get_aabb()
	box.size = aabb.size
	col.shape = box
	col.position = aabb.get_center()
	body.transform = xf
	body.add_child(col)
	add_child(body)


func _build_ruin() -> void:
	var stone := _lit("ground")
	stone.set_shader_parameter("color_depleted", Color("#B9B3A6"))   # 폐허 돌: 절벽 회색과 구분되는 따뜻한 돌색
	stone.set_shader_parameter("color_restored", Color("#B59D7A"))
	var base := _ground(RUIN_POS.x, RUIN_POS.y)
	var face := Basis(Vector3.UP, deg_to_rad(20.0))
	_place_part(StructureGen.block(Vector3(10, 1.2, 8), 0.2, SEED, 0.3), stone, Transform3D(face, base + Vector3(0, -0.4, 0)))
	_place_part(StructureGen.stairs(5, 3.0, 0.3, 0.45, SEED), stone, Transform3D(face, base + face * Vector3(0, -0.4, 4.0)))
	var i := 0
	for off in [Vector3(-3.5, 0.8, -2.5), Vector3(0, 0.8, -3.0), Vector3(3.5, 0.8, -2.5)]:
		_place_part(StructureGen.pillar(5.5 - i * 1.2, 0.5, SEED + i, i == 2), stone, Transform3D(face, base + face * off))
		i += 1
	_place_part(StructureGen.arch(4.0, 4.5, 0.7, SEED), stone, Transform3D(face, base + face * Vector3(0, 0.8, 1.5)))
	for j in 4:
		var p := Vector2(RUIN_POS.x + _rng.randf_range(-8, 8), RUIN_POS.y + _rng.randf_range(-8, 8))
		var sz := Vector3(_rng.randf_range(0.8, 1.8), _rng.randf_range(0.5, 1.0), _rng.randf_range(0.8, 1.8))
		_place_part(StructureGen.block(sz, 0.08, SEED + 20 + j, 0.6), stone, _xf(_ground(p.x, p.y), 1.0, 0.3))


# ---------- 하늘 요소 ----------

func _build_clouds() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = LIT
	mat.set_shader_parameter("color_depleted", Color("#C9CDD0"))
	mat.set_shader_parameter("color_restored", Color("#FFFFFF"))
	mat.set_shader_parameter("noise_amount", 0.0)
	mat.set_shader_parameter("wobble", 0.04)
	mat.set_shader_parameter("use_here", true)
	for i in 12:
		var m := CloudGen.build(SEED + i)
		m.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 12.0 + _rng.randf_range(-0.2, 0.2)
		var d := _rng.randf_range(300.0, 600.0)
		var s := _rng.randf_range(14.0, 30.0)
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s)),
			Vector3(cos(a) * d, _rng.randf_range(70.0, 140.0), sin(a) * d))
		add_child(mi)


## 원경 능선 링 2겹 (색면, 안개로 하늘에 녹는다).
func _build_ridges() -> void:
	var kit := MeshKit.new()
	var nz := FastNoiseLite.new()
	nz.seed = SEED + 99
	nz.frequency = 3.0
	var seg := 96
	for layer in 2:
		var rad := 900.0 + layer * 500.0
		var amp := 110.0 + layer * 120.0
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var h0 := 40.0 + (nz.get_noise_1d(a0 + layer * 10.0) * 0.5 + 0.5) * amp
			var h1 := 40.0 + (nz.get_noise_1d(a1 + layer * 10.0) * 0.5 + 0.5) * amp
			var b0 := Vector3(cos(a0), 0, sin(a0)) * rad + Vector3.DOWN * 20.0
			var b1 := Vector3(cos(a1), 0, sin(a1)) * rad + Vector3.DOWN * 20.0
			var t0 := Vector3(cos(a0) * rad * 1.02, h0, sin(a0) * rad * 1.02)
			var t1 := Vector3(cos(a1) * rad * 1.02, h1, sin(a1) * rad * 1.02)
			kit.add_quad(b0, b1, t1, t0, Color(1.0 - layer * 0.08, 1, 1, 1))   # 섬 안쪽을 향하게
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	var m := _lit("rock")
	m.set_shader_parameter("color_depleted", Color("#6F7C86"))   # 먼 산은 푸른 회색 색면 (안개가 하늘색으로 녹인다)
	m.set_shader_parameter("color_restored", Color("#5E7D99"))
	m.set_shader_parameter("noise_amount", 0.0)
	m.set_shader_parameter("use_here", true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_life() -> void:
	_life = CPUParticles3D.new()
	_life.amount = LIFE_MAX
	_life.lifetime = 6.0
	_life.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_life.emission_box_extents = Vector3(30, 3, 30)
	_life.position = Vector3(0, 8, 0)
	_life.direction = Vector3.UP
	_life.spread = 60.0
	_life.initial_velocity_min = 0.2
	_life.initial_velocity_max = 0.6
	_life.gravity = Vector3.ZERO
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	dot.radial_segments = 6
	dot.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = StylePalette.LIFE
	m.emission_enabled = true
	m.emission = StylePalette.LIFE
	m.emission_energy_multiplier = 2.0
	dot.material = m
	_life.mesh = dot
	add_child(_life)


# ---------- 디버그 UI ----------

func _build_panel() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	var box := VBoxContainer.new()
	box.name = "StylePanel"
	box.position = Vector2(16, 16)
	box.custom_minimum_size = Vector2(320, 0)
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
	var flat := CheckButton.new()
	flat.text = "지형 평면 음영"
	flat.button_pressed = true
	flat.toggled.connect(func(on): _terrain_mat.set_shader_parameter("flat_shading", on))
	box.add_child(flat)
	var fog := CheckButton.new()
	fog.text = "안개"
	fog.button_pressed = true
	fog.toggled.connect(func(on): _env.fog_enabled = on)
	box.add_child(fog)
