class_name RecoveryMap
extends Node
## 회복 모델을 저해상도 텍스처로 구워 전역 셰이더 변수로 넘긴다.
## 표시값은 목표를 향해 서서히 움직인다(갑자기 바뀌지 않음).

## 지도가 덮는 월드 xz 범위
@export var world_rect := Rect2(-256, -256, 512, 512)
## 텍스처 한 변 칸 수
@export var resolution := 128
## 초당 값 변화량
@export var blend_speed := 0.5

var model: Recovery = Recovery.new()

var _target := PackedFloat32Array()
var _shown := PackedFloat32Array()
var _image: Image
var _texture: ImageTexture
var _here := 0.0
var _settled := false
var _here_sent := false
## 텍스처 업로드 횟수 (테스트·측정용)
var upload_count := 0

func _ready() -> void:
	refresh()
	_push_globals()

func _process(delta: float) -> void:
	step(delta)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var p := cam.global_position
		var here := move_toward(_here, displayed_at(Vector2(p.x, p.z)), blend_speed * delta)
		if here != _here or not _here_sent:
			_here = here
			_here_sent = true
			RenderingServer.global_shader_parameter_set("recovery_here", _here)

## 목표 값을 모델에서 다시 굽는다. 표시값은 처음 한 번만 0으로 초기화.
func refresh() -> void:
	_target = model.bake(world_rect, resolution)
	_settled = false
	if _shown.size() != _target.size():
		_shown = PackedFloat32Array()
		_shown.resize(_target.size())
		_shown.fill(0.0)

## 표시값을 목표 쪽으로 blend_speed*dt만큼 옮기고 텍스처를 갱신한다.
func step(dt: float) -> void:
	if _shown.size() != _target.size() or _shown.is_empty():
		refresh()
	if _settled:
		return   # 목표에 도달 — 매 프레임 1.6만 칸 계산·업로드를 하지 않는다
	var d := blend_speed * dt
	for i in _shown.size():
		_shown[i] = move_toward(_shown[i], _target[i], d)
	_settled = _shown == _target
	_update_texture()


func is_settled() -> bool:
	return _settled

## 월드 xz 위치의 표시값. 범위 밖은 0.
func displayed_at(p: Vector2) -> float:
	if _shown.is_empty() or not world_rect.has_point(p):
		return 0.0
	var u := (p - world_rect.position) / world_rect.size
	var x := clampi(int(u.x * resolution), 0, resolution - 1)
	var y := clampi(int(u.y * resolution), 0, resolution - 1)
	return _shown[y * resolution + x]

func _update_texture() -> void:
	if _image != null and _image.get_width() != resolution:
		_texture = null
	var bytes := PackedByteArray()
	bytes.resize(_shown.size())
	for i in _shown.size():
		bytes[i] = int(clampf(_shown[i], 0.0, 1.0) * 255.0 + 0.5)
	_image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_R8, bytes)
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
		_push_globals()
	else:
		_texture.update(_image)
	upload_count += 1

func _push_globals() -> void:
	if _texture == null:
		return
	RenderingServer.global_shader_parameter_set("recovery_map", _texture)
	RenderingServer.global_shader_parameter_set("recovery_map_rect",
		Vector4(world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y))
