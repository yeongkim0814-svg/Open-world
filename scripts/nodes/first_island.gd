class_name FirstIsland
extends Node3D
## 첫 섬 씬 루트 (그룹 "world"). 진행 상태를 갖고 수문·탑 이벤트를 처리한다.

const RECOVERY_RADIUS := 220.0
const RECOVERY_TIME := 6.0
## 안개 두 세트 (흐림 = vitality_global 0, 맑음 = 1). apply_vitality_global()이 보간한다.
const FOG_GREY := {
	"fog_light_color": Color(0.66, 0.68, 0.7), "fog_density": 0.0007, "fog_height_density": 0.05,
	"volumetric_fog_density": 0.003, "volumetric_fog_albedo": Color(0.8, 0.82, 0.85),
}
const FOG_CLEAR := {
	"fog_light_color": Color(0.62, 0.72, 0.86), "fog_density": 0.0005, "fog_height_density": 0.03,
	"volumetric_fog_density": 0.001, "volumetric_fog_albedo": Color(0.9, 0.94, 1.0),
}
const SUN_ENERGY := 1.6  ## 회복 전후 같음 (차이는 하늘·안개가 만든다)

var state := WorldState.new()
var vitality_radius := 0.0

@onready var lake: Lake = $Lake


func _ready() -> void:
	add_to_group("world")
	_set_vitality(RECOVERY_RADIUS if state.tower_stopped else 0.0)
	var grass := get_node_or_null("GrassField")
	if grass:
		lake.level_settled.connect(func():
			grass.invalidate_disc(Vector2(lake.global_position.x, lake.global_position.z), lake.radius))
	set_recovered_visuals(1.0 if state.tower_stopped else 0.0)
	apply_state()


## 수문을 연다: 상태 → 저수호 목표 수위 → 수문·수로 표시.
func open_sluice(i: int) -> void:
	if state.open_sluice(i):
		apply_state()


## 상태를 장면에 반영한다 (불러오기 후에도 호출).
func apply_state() -> void:
	lake.set_target(LakeLevel.level(lake.base_level, state.open_count()))
	for s in get_tree().get_nodes_in_group("sluice"):
		s.set_opened(state.sluices[s.index])
	var aqueduct := get_node_or_null("Aqueduct/Water")
	if aqueduct:
		aqueduct.visible = state.open_count() > 0


## 탑 정지 (처음 한 번만): 소용돌이 멈춤 → 생명력 터짐 → 회복 반경 확장 → 하늘이 갬 → 섬의 기계 정지.
func stop_tower() -> void:
	if not state.stop_tower():
		return
	var tower := $Tower
	tower.get_node("Burst").restart()
	var tween := create_tween().set_parallel()
	tween.tween_method(_set_vitality, 0.0, RECOVERY_RADIUS, RECOVERY_TIME).set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_recovered_visuals, 0.0, 1.0, RECOVERY_TIME).set_trans(Tween.TRANS_SINE)
	for m in get_tree().get_nodes_in_group("enemy"):
		if m.has_method("deactivate"):
			m.deactivate()


## 회복 연출 (0 = 탑 작동 중, 1 = 정지 후): 먹구름이 걷히고 소용돌이가 멈추고 하늘·안개가 갠다.
## 스크린샷 도구도 이 함수로 회복 후 하늘을 만든다.
func set_recovered_visuals(v: float) -> void:
	var tower := get_node_or_null("Tower")
	if tower:
		var cloud := tower.get_node_or_null("Cloud") as MeshInstance3D
		if cloud:
			var mat := cloud.get_active_material(0) as ShaderMaterial
			var a := clampf(1.0 - v * 2.0, 0.0, 1.0)   # 앞 절반 동안 걷힌다
			if mat:
				mat.set_shader_parameter("opacity", a)
			cloud.visible = a > 0.001
		var vortex := tower.get_node_or_null("Vortex") as GPUParticles3D
		if vortex:
			vortex.emitting = v < 0.05
			vortex.visible = v < 0.5
	apply_vitality_global(v)


func _set_vitality(r: float) -> void:
	vitality_radius = r
	RenderingServer.global_shader_parameter_set("vitality_radius", r)


## 하늘·안개처럼 위치 없는 요소의 회복 정도 (0 흐림 ↔ 1 맑음). 하늘 셰이더는 전역 vitality_global을 읽는다.
func apply_vitality_global(v: float) -> void:
	RenderingServer.global_shader_parameter_set("vitality_global", v)
	var env: Environment = $WorldEnvironment.environment
	for k in FOG_GREY:
		env.set(k, lerp(FOG_GREY[k], FOG_CLEAR[k], v))
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = SUN_ENERGY


func status_text() -> String:
	return "수문 %d/3 · 탑 %s" % [state.open_count(), "멈춤" if state.tower_stopped else "작동 중"]
