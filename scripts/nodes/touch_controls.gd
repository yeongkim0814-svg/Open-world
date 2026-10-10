class_name TouchControls
extends Control
## 터치 입력 → InputIntent. 왼쪽 40% = 플로팅 스틱, 오른쪽 = 카메라 드래그, 버튼은 직접 그리고 판정한다.
## 키보드/패드 입력도 같은 InputIntent로 수렴한다 (PC 디버그용).

signal intent_updated(intent: InputIntent)

const STICK_AREA_RATIO := 0.4
const BUTTON_RADIUS := 64.0
const STICK_RADIUS := 120.0

var _stick := VirtualStick.new(STICK_RADIUS)
var _camera_touches := {}            ## index -> 마지막 위치
var _camera_drag := Vector2.ZERO
var _button_touches := {}            ## index -> 버튼 이름
var _jump_queued := false
var _combat := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_actions()


## 전투 상태에 따라 점프 버튼 아이콘을 점프 ↔ 회피로 바꾼다 (M1에서는 항상 false).
func set_context(combat: bool) -> void:
	_combat = combat
	queue_redraw()


func consume_camera_drag() -> Vector2:
	var d := _camera_drag
	_camera_drag = Vector2.ZERO
	return d


func _buttons() -> Dictionary:
	var s := size
	return {
		"jump": Vector2(s.x - 110, s.y - 330),
		"attack": Vector2(s.x - 110, s.y - 150),
		"guard": Vector2(s.x - 270, s.y - 110),
	}


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_stick.drag(event.index, event.position)
		if _camera_touches.has(event.index):
			_camera_drag += event.position - _camera_touches[event.index]
			_camera_touches[event.index] = event.position
		queue_redraw()


func _on_touch_down(index: int, pos: Vector2) -> void:
	var buttons := _buttons()
	for name in buttons:
		if pos.distance_to(buttons[name]) <= BUTTON_RADIUS:
			_button_touches[index] = name
			if name == "jump":
				_jump_queued = true
			queue_redraw()
			return
	if pos.x < size.x * STICK_AREA_RATIO:
		_stick.press(index, pos)
	else:
		_camera_touches[index] = pos
	queue_redraw()


func _on_touch_up(index: int) -> void:
	_stick.release(index)
	_camera_touches.erase(index)
	_button_touches.erase(index)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var intent := InputIntent.new()
	var key_move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	intent.move = _stick.value() if _stick.is_active() else key_move
	intent.sprint = _stick.is_full_push() or Input.is_action_pressed("sprint")
	intent.jump_pressed = _jump_queued or Input.is_action_just_pressed("jump")
	intent.jump_held = _button_touches.values().has("jump") or Input.is_action_pressed("jump")
	_jump_queued = false
	intent_updated.emit(intent)


func _draw() -> void:
	if _stick.is_active():
		draw_circle(_stick.origin(), STICK_RADIUS, Color(1, 1, 1, 0.15))
		draw_circle(_stick.origin() + Vector2(_stick.value().x, -_stick.value().y) * STICK_RADIUS, 40, Color(1, 1, 1, 0.5))
	var held := _button_touches.values()
	var buttons := _buttons()
	for name in buttons:
		var active: bool = name == "jump"
		var alpha: float = 0.15 if not active else (0.6 if held.has(name) else 0.35)
		draw_circle(buttons[name], BUTTON_RADIUS, Color(1, 1, 1, alpha))
	var label := "회피" if _combat else "점프"
	draw_string(get_theme_default_font(), buttons["jump"] + Vector2(-24, 8), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 24)


func _ensure_actions() -> void:
	var keys := {
		"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
