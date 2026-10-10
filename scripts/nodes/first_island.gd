class_name FirstIsland
extends Node3D
## 첫 섬 씬 루트 (그룹 "world"). 진행 상태를 갖고 수문·탑 이벤트를 처리한다.


func _ready() -> void:
	add_to_group("world")
	RenderingServer.global_shader_parameter_set("vitality_radius", 0.0)
