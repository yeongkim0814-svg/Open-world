class_name DebugHud
extends Label
## 성능·상태 표시. 1초 단위 평균/최악 프레임 시간, 3초마다 PERF 로그.

const STATE_NAMES := ["GROUNDED", "AIRBORNE", "CLIMBING", "GLIDING", "DODGING", "SWIMMING"]

@export var player: Player

var _frame_sum := 0.0
var _frame_worst := 0.0
var _frame_count := 0
var _window := 0.0
var _log_timer := 0.0
var _avg_ms := 0.0
var _worst_ms := 0.0


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_frame_sum += ms
	_frame_worst = maxf(_frame_worst, ms)
	_frame_count += 1
	_window += delta
	_log_timer += delta
	if _window >= 1.0:
		_avg_ms = _frame_sum / _frame_count
		_worst_ms = _frame_worst
		_frame_sum = 0.0
		_frame_worst = 0.0
		_frame_count = 0
		_window = 0.0
	if _log_timer >= 3.0:
		_log_timer = 0.0
		print("PERF fps=%d avg_ms=%.1f worst_ms=%.1f" % [Engine.get_frames_per_second(), _avg_ms, _worst_ms])
	var lines := ["FPS %d" % Engine.get_frames_per_second(), "frame %.1f ms (최악 %.1f)" % [_avg_ms, _worst_ms]]
	if player and player.locomotion:
		lines.append("state %s" % STATE_NAMES[player.locomotion.state])
		lines.append("stamina %d%s" % [roundi(player.stamina.value), " (탈진)" if player.stamina.exhausted else ""])
	if player and player.combat and player.combat.state:
		var a: Arsenal = player.combat.arsenal
		var d := a.durability()
		lines.append("%s %d/%d%s" % [a.current().display_name, ceili(d.value), roundi(d.max_value), " (파손)" if d.is_broken() else ""])
		lines.append("HP %d  부품 %d  %s  %s" % [roundi(player.combat.hp), player.parts, "⚔전투" if player.combat.state.active else "", player.combat.last_result])
	var world := get_tree().get_first_node_in_group("world")
	if world:
		lines.append(world.status_text())
	text = "\n".join(lines)
