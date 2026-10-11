extends SceneTree
## 고정 시점 스크린샷 (xvfb). 사용: tools/shots.sh <tag> [grey|color|both|r0,r50,r100] [first_island|style_test]
## 모드: grey = 회복 0, color = 회복 1, rNN = 회복 NN%. 장면 루트에 set_preview_recovery(v)가 있으면 그것을 쓰고,
## 없으면 첫 섬의 vitality 경로(set_recovered_visuals)를 쓴다.

## 장면별 시점: [카메라 위치, 바라보는 점]
const SCENES := {
	"first_island": {
		"village": [Vector3(0, 6, 112), Vector3(0, 20, -10)],
		"dam": [Vector3(6, 19, 52), Vector3(0, 30, -10)],
		"tower": [Vector3(0, 82, -2), Vector3(0, 0, 110)],
		"plateau": [Vector3(-132, 23, -30), Vector3(-40, 15, -10)],
	},
	"style_test": {
		# 높이 = 지면 위 m (장면에 field가 있으면 지면 높이를 더한다)
		"near": [Vector3(6, 2.0, 30), Vector3(0, 1.5, 10)],
		"mid": [Vector3(34, 16, 46), Vector3(0, 0, 0)],
		"far": [Vector3(120, 50, 140), Vector3(0, 0, 0)],
		"ruin": [Vector3(-12, 2.5, 10), Vector3(-24, 2.0, -4)],
	},
	"island_1km": {
		"start": [Vector3(690, 2.5, 705), Vector3(300, 40, 300)],
		"village": [Vector3(520, 6, 790), Vector3(430, 5, 650)],
		"lake": [Vector3(-110, 6, -150), Vector3(26, 30, -173)],
		"mountain": [Vector3(520, 3, 330), Vector3(26, 200, -190)],
		"trail": [Vector3(-56, 2.5, 200), Vector3(-25, 1.0, 150)],
		"slope_air": [Vector3(140, 70, 330), Vector3(-40, 0, 170)],
		"summit": [Vector3(-60, 3, 260), Vector3(20, 60, -120)],
		"air": [Vector3(1000, 520, 1150), Vector3(0, 0, -100)],
		"forest": [Vector3(-620, 2.5, 80), Vector3(-560, 3, 140)],   # 서쪽 활엽수림 안 (zones.png 값 1, 평지)
	},
}
const SETTLE_FRAMES := 45

var s; var tag := "shot"; var scene_name := "first_island"; var modes := ["grey", "color"]
var queue := []; var frame := 0; var cam: Camera3D; var t := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: tag = a[0]
	if a.size() > 1 and a[1] != "both": modes = Array(a[1].split(","))
	if a.size() > 2: scene_name = a[2]
	DirAccess.make_dir_recursive_absolute("/tmp/claude-0/shots")
	s = load("res://scenes/%s.tscn" % scene_name).instantiate()
	root.add_child(s)
	for m in modes:
		for v in SCENES[scene_name]:
			queue.append([v, m])


static func mode_value(m: String) -> float:
	if m == "grey": return 0.0
	if m == "color": return 1.0
	return clampf(float(m.trim_prefix("r")) / 100.0, 0.0, 1.0)


func _set_recovery(v: float) -> void:
	if s.has_method("set_preview_recovery"):
		s.set_preview_recovery(v)
		return
	RenderingServer.global_shader_parameter_set("vitality_radius", 100000.0 if v > 0.0 else 0.0)
	if ProjectSettings.has_setting("shader_globals/vitality_global"):
		RenderingServer.global_shader_parameter_set("vitality_global", v)
	if s.has_method("set_recovered_visuals"):
		s.set_recovered_visuals(v)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 2:
		var ui = s.get_node_or_null("UI")
		if ui: ui.visible = false
		for m in get_nodes_in_group("enemy"): m.process_mode = Node.PROCESS_MODE_DISABLED
		if scene_name == "first_island":
			s.get_node("Player").global_position = Vector3(3, 4, 104)   # 마을 시점에 크기 기준으로만 보이게
	if queue.is_empty():
		quit(); return false
	var cur = queue[0]
	t += 1
	if t == 3:
		if cam == null:
			cam = Camera3D.new(); cam.fov = 70.0; cam.far = 4000.0; s.add_child(cam); cam.make_current()
		var v = SCENES[scene_name][cur[0]]
		var pos: Vector3 = v[0]
		var at: Vector3 = v[1]
		var f = s.get("field")
		if f != null:
			pos.y += maxf(f.height_at(pos.x, pos.z), 0.0)
			at.y += maxf(f.height_at(at.x, at.z), 0.0)
		cam.global_position = pos
		cam.look_at(at, Vector3.UP)
		_set_recovery(mode_value(cur[1]))
	elif t >= SETTLE_FRAMES and not (s.has_method("busy") and s.busy() and t < 1200):   # 지형 구역이 다 만들어질 때까지
		var path := "/tmp/claude-0/shots/%s_%s_%s.png" % [tag, cur[0], cur[1]]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		queue.pop_front()
		t = 0
	return false
