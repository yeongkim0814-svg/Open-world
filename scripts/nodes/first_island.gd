class_name FirstIsland
extends Node3D
## 첫 섬 씬 루트 (그룹 "world"). 진행 상태를 갖고 수문·탑 이벤트를 처리한다.

const RECOVERY_RADIUS := 220.0
const RECOVERY_TIME := 6.0
const CLEAR_SKY_TOP := Color("#7EC3EA")
const CLEAR_HORIZON := Color(0.78, 0.86, 0.9)
const CLEAR_FOG := Color(0.78, 0.86, 0.9)

var state := WorldState.new()
var vitality_radius := 0.0

@onready var lake: Lake = $Lake


func _ready() -> void:
	add_to_group("world")
	RenderingServer.global_shader_parameter_set("vitality_radius", 0.0)
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
	tower.get_node("Vortex").emitting = false
	tower.get_node("Burst").restart()
	var tween := create_tween().set_parallel()
	tween.tween_method(_set_vitality, 0.0, RECOVERY_RADIUS, RECOVERY_TIME).set_trans(Tween.TRANS_SINE)
	var cloud_mat: StandardMaterial3D = (tower.get_node("Cloud") as MeshInstance3D).mesh.material
	tween.tween_property(cloud_mat, "albedo_color:a", 0.0, RECOVERY_TIME * 0.5)
	var env: Environment = $WorldEnvironment.environment
	var sky: ProceduralSkyMaterial = env.sky.sky_material
	tween.tween_property(sky, "sky_top_color", CLEAR_SKY_TOP, RECOVERY_TIME)
	tween.tween_property(sky, "sky_horizon_color", CLEAR_HORIZON, RECOVERY_TIME)
	tween.tween_property(env, "fog_light_color", CLEAR_FOG, RECOVERY_TIME)
	for m in get_tree().get_nodes_in_group("enemy"):
		if m.has_method("deactivate"):
			m.deactivate()


func _set_vitality(r: float) -> void:
	vitality_radius = r
	RenderingServer.global_shader_parameter_set("vitality_radius", r)


func status_text() -> String:
	return "수문 %d/3 · 탑 %s" % [state.open_count(), "멈춤" if state.tower_stopped else "작동 중"]
