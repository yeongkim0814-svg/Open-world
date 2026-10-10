class_name TouchControls
extends Control
## 터치 입력 → InputIntent. 왼쪽 40% = 플로팅 스틱, 오른쪽 = 카메라 드래그, 버튼은 직접 그리고 판정한다.
## 자동 달리기: 스틱을 위로 끌어 🔒 아이콘에서 놓으면 고정, 스틱 영역을 다시 누르면 해제.
## 키보드/패드 입력도 같은 InputIntent로 수렴한다 (PC 디버그용).

signal intent_updated(intent: InputIntent)

const STICK_AREA_RATIO := 0.4
const BUTTON_RADIUS := 64.0
const STICK_RADIUS := 120.0
const WEAPON_BUTTON_RADIUS := 48.0

var _stick := VirtualStick.new(STICK_RADIUS)
var _camera_touches := {}            ## index -> 마지막 위치
var _camera_drag := Vector2.ZERO
var _button_touches := {}            ## index -> 버튼 이름
var _jump_queued := false
var _auto_run := false
var _threatened := false
var _attack_hold := -1.0             ## 공격 버튼 누른 시간 (s), 안 누르면 -1
var _attack_release_queued := 0      ## 0 없음 / 1 탭 / 2 강공격
var _guard_queued := false
var _key_attack_hold := -1.0
var _interact_label := ""            ## 비어 있으면 팝업 숨김
var _interact_queued := false
var _switch_queued := false
var _weapon_label := ""
var _aiming := false
var _attack_drag_pos := Vector2.ZERO  ## 활 조준 중 공격 버튼을 끌면 카메라가 돈다 (C18)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_actions()


## 적이 공격 중일 때 점프 버튼 아이콘을 회피로 바꾼다 (C16).
func set_threatened(threatened: bool) -> void:
	if _threatened != threatened:
		_threatened = threatened
		queue_redraw()


## 상호작용 팝업 (C15): 오른손 버튼 위쪽 고정 위치에 "줍기: 기계 부품" 형식으로 표시.
func show_interact(label: String) -> void:
	if _interact_label != label:
		_interact_label = label
		queue_redraw()


## 무기 교체 버튼에 장착 무기 이름 표시 (C17).
func set_weapon_label(label: String) -> void:
	if _weapon_label != label:
		_weapon_label = label
		queue_redraw()


## 활 조준 중: 화면 중앙 십자선.
func set_aiming(on: bool) -> void:
	if _aiming != on:
		_aiming = on
		queue_redraw()


func hide_interact() -> void:
	show_interact("")


## 점프/회피 버튼 위쪽, 버튼들과 40px 이상 띄운 자리 (회피 탭이 줍기로 새지 않게).
func _interact_rect() -> Rect2:
	return Rect2(Vector2(size.x - 300, size.y - 500), Vector2(260, 64))


func cancel_auto_run() -> void:
	if _auto_run:
		_auto_run = false
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
		"weapon": Vector2(s.x - 90, 90),
	}


func _radius(name: String) -> float:
	return WEAPON_BUTTON_RADIUS if name == "weapon" else BUTTON_RADIUS


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_stick.drag(event.index, event.position)
		if _aiming and _button_touches.get(event.index) == "attack":
			_camera_drag += event.relative if event.relative != Vector2.ZERO else event.position - _attack_drag_pos
		if _button_touches.get(event.index) == "attack":
			_attack_drag_pos = event.position
		if _camera_touches.has(event.index):
			_camera_drag += event.position - _camera_touches[event.index]
			_camera_touches[event.index] = event.position
		queue_redraw()


func _on_touch_down(index: int, pos: Vector2) -> void:
	var buttons := _buttons()
	for name in buttons:
		if pos.distance_to(buttons[name]) <= _radius(name):
			_button_touches[index] = name
			match name:
				"jump": _jump_queued = true
				"attack":
					_attack_hold = 0.0
					_attack_drag_pos = pos
				"guard": _guard_queued = true
				"weapon": _switch_queued = true
			queue_redraw()
			return
	if not _interact_label.is_empty() and _interact_rect().has_point(pos):
		_interact_queued = true
		_button_touches[index] = "interact"
		return
	if pos.x < size.x * STICK_AREA_RATIO:
		_auto_run = false
		_stick.press(index, pos)
	else:
		_camera_touches[index] = pos
	queue_redraw()


func _on_touch_up(index: int) -> void:
	if _stick.release(index):
		_auto_run = true
	_camera_touches.erase(index)
	if _button_touches.get(index) == "attack":
		_attack_release_queued = _classify_attack(_attack_hold)
		_attack_hold = -1.0
	_button_touches.erase(index)
	queue_redraw()


## 공격 버튼을 뗀 순간: heavy_hold_time 미만 = 탭(1), 이상 = 강공격(2).
func _classify_attack(held: float) -> int:
	return 2 if held >= preload("res://resources/combat_tuning.tres").heavy_hold_time else 1


func _physics_process(delta: float) -> void:
	var intent := InputIntent.new()
	if _attack_hold >= 0.0:
		_attack_hold += delta
	# 키보드: J = 공격(길게 = 강공격), K = 방어
	if Input.is_action_just_pressed("attack"):
		_key_attack_hold = 0.0
	elif _key_attack_hold >= 0.0:
		_key_attack_hold += delta
		if not Input.is_action_pressed("attack"):
			_attack_release_queued = _classify_attack(_key_attack_hold)
			_key_attack_hold = -1.0
	intent.attack_pressed = _attack_release_queued == 1
	intent.heavy_released = _attack_release_queued == 2
	_attack_release_queued = 0
	intent.attack_held = _attack_hold >= 0.0 or _key_attack_hold >= 0.0
	intent.switch_weapon_pressed = _switch_queued or Input.is_action_just_pressed("switch_weapon")
	_switch_queued = false
	intent.guard_pressed = _guard_queued or Input.is_action_just_pressed("guard")
	intent.guard_held = _button_touches.values().has("guard") or Input.is_action_pressed("guard")
	_guard_queued = false
	intent.interact_pressed = _interact_queued or Input.is_action_just_pressed("interact")
	_interact_queued = false
	var key_move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if Input.is_action_pressed("walk"):
		key_move *= 0.5
	intent.move = _stick.value() if _stick.is_active() else key_move
	intent.auto_run = _auto_run
	intent.camera_held = not _camera_touches.is_empty()
	intent.jump_pressed = _jump_queued or Input.is_action_just_pressed("jump")
	intent.jump_held = _button_touches.values().has("jump") or Input.is_action_pressed("jump")
	_jump_queued = false
	intent_updated.emit(intent)


func _draw() -> void:
	var font := get_theme_default_font()
	if _stick.is_active():
		draw_circle(_stick.origin(), STICK_RADIUS, Color(1, 1, 1, 0.15))
		draw_circle(_stick.origin() + Vector2(_stick.value().x, -_stick.value().y) * STICK_RADIUS, 40, Color(1, 1, 1, 0.5))
		if _stick.value().y > 0.5:
			var lock_pos := _stick.origin() + Vector2(0, -STICK_RADIUS * (VirtualStick.LOCK_ZONE + 0.2))
			var lit := _stick.in_lock_zone()
			draw_circle(lock_pos, 36, Color(1, 0.85, 0.3, 0.8 if lit else 0.3))
			draw_string(font, lock_pos + Vector2(-24, 8), "자동", HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	if _auto_run:
		draw_string(font, Vector2(40, size.y - 40), "자동 달리기 — 왼쪽을 누르면 해제", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.85, 0.3))
	var held := _button_touches.values()
	var buttons := _buttons()
	for name in buttons:
		var alpha: float = 0.6 if held.has(name) else 0.35
		var tint := Color(1, 0.85, 0.3, alpha) if name == "jump" and _threatened else Color(1, 1, 1, alpha)
		draw_circle(buttons[name], _radius(name), tint)
	draw_string(font, buttons["jump"] + Vector2(-24, 8), "회피" if _threatened else "점프", HORIZONTAL_ALIGNMENT_CENTER, -1, 24)
	draw_string(font, buttons["attack"] + Vector2(-24, 8), "공격", HORIZONTAL_ALIGNMENT_CENTER, -1, 24)
	draw_string(font, buttons["guard"] + Vector2(-24, 8), "방어", HORIZONTAL_ALIGNMENT_CENTER, -1, 24)
	draw_string(font, buttons["weapon"] + Vector2(-40, 8), _weapon_label, HORIZONTAL_ALIGNMENT_CENTER, 80, 20)
	if _aiming:
		var c := size * 0.5
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 6, c + d * 18, Color(1, 1, 1, 0.9), 2.0)
	if not _interact_label.is_empty():
		var r := _interact_rect()
		draw_rect(r, Color(0.1, 0.1, 0.1, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
		draw_string(font, r.position + Vector2(16, 42), _interact_label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 26)


func _ensure_actions() -> void:
	var keys := {
		"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S,
		"jump": KEY_SPACE, "walk": KEY_CTRL, "attack": KEY_J, "guard": KEY_K, "interact": KEY_E, "switch_weapon": KEY_Q,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
