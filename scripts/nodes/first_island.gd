class_name FirstIsland
extends Node3D
## 첫 섬 씬 루트 (그룹 "world"). 진행 상태를 갖고 수문·탑 이벤트를 처리한다.

var state := WorldState.new()

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


func status_text() -> String:
	return "수문 %d/3 · 탑 %s" % [state.open_count(), "멈춤" if state.tower_stopped else "작동 중"]
