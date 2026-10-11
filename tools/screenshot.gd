extends SceneTree
## 고정 시점 스크린샷 (Forward+, xvfb). 사용: tools/shots.sh <tag> [grey|color|both]
## 시점: 마을·둑 위·탑 꼭대기·서쪽 고원. color = 회복 후(vitality_radius 크게, vitality_global 1).

## 시점: [카메라 위치, 바라보는 점]
const VIEWS := {
	"village": [Vector3(0, 6, 112), Vector3(0, 20, -10)],
	"dam": [Vector3(6, 19, 52), Vector3(0, 30, -10)],
	"tower": [Vector3(0, 82, -2), Vector3(0, 0, 110)],
	"plateau": [Vector3(-132, 23, -30), Vector3(-40, 15, -10)],
}
const SETTLE_FRAMES := 45

var s; var tag := "shot"; var modes := ["grey", "color"]
var queue := []; var frame := 0; var cam: Camera3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: tag = a[0]
	if a.size() > 1 and a[1] != "both": modes = [a[1]]
	DirAccess.make_dir_recursive_absolute("/tmp/claude-0/shots")
	s = load("res://scenes/first_island.tscn").instantiate()
	root.add_child(s)
	for m in modes:
		for v in VIEWS:
			queue.append([v, m])


func _set_vitality(color: bool) -> void:
	RenderingServer.global_shader_parameter_set("vitality_radius", 100000.0 if color else 0.0)
	if ProjectSettings.has_setting("shader_globals/vitality_global"):
		RenderingServer.global_shader_parameter_set("vitality_global", 1.0 if color else 0.0)
	if s.has_method("set_recovered_visuals"):
		s.set_recovered_visuals(1.0 if color else 0.0)
	elif s.has_method("apply_vitality_global"):
		s.apply_vitality_global(1.0 if color else 0.0)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 2:
		var ui = s.get_node_or_null("UI")
		if ui: ui.visible = false
		for m in get_nodes_in_group("enemy"): m.process_mode = Node.PROCESS_MODE_DISABLED
		s.get_node("Player").global_position = Vector3(3, 4, 104)   # 마을 시점에 크기 기준으로만 보이게
	if queue.is_empty():
		quit(); return false
	var cur = queue[0]
	if frame % SETTLE_FRAMES == 3:
		if cam == null:
			cam = Camera3D.new(); cam.fov = 70.0; s.add_child(cam); cam.make_current()
		var v = VIEWS[cur[0]]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		_set_vitality(cur[1] == "color")
	elif frame % SETTLE_FRAMES == 0:
		var path := "/tmp/claude-0/shots/%s_%s_%s.png" % [tag, cur[0], cur[1]]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		queue.pop_front()
	return false
