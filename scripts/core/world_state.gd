class_name WorldState
extends RefCounted
## 첫 섬 진행 상태: 수문 3곳, 탑 정지 여부, 정지 순간의 열린 수문 수(마을 결과), 떠난 주민.

const SLUICE_COUNT := 3

var sluices: Array[bool] = [false, false, false]
var tower_stopped := false
var outcome_at_stop := -1          ## -1 = 아직 정지 안 함
var departed: Array[StringName] = []


## 새로 열었으면 true. 이미 열렸거나 범위 밖이면 false.
func open_sluice(i: int) -> bool:
	if i < 0 or i >= SLUICE_COUNT or sluices[i]:
		return false
	sluices[i] = true
	return true


func open_count() -> int:
	return sluices.count(true)


## 처음 정지할 때만 true — 그 순간 열린 수문 수를 결과로 고정한다.
func stop_tower() -> bool:
	if tower_stopped:
		return false
	tower_stopped = true
	outcome_at_stop = open_count()
	return true


func to_dict() -> Dictionary:
	return {
		"sluices": sluices.duplicate(),
		"tower_stopped": tower_stopped,
		"outcome_at_stop": outcome_at_stop,
		"departed": departed.map(func(n): return String(n)),
	}


## 저장 파일이 손상돼도 멈추지 않게: 형식이 맞지 않는 값은 기본값.
static func from_dict(d: Dictionary) -> WorldState:
	var s := WorldState.new()
	var sl = d.get("sluices")
	if sl is Array and sl.size() == SLUICE_COUNT and sl.all(func(v): return v is bool):
		for i in SLUICE_COUNT:
			s.sluices[i] = sl[i]
	if d.get("tower_stopped") is bool:
		s.tower_stopped = d["tower_stopped"]
	var o = d.get("outcome_at_stop")
	if (o is int or o is float) and int(o) >= -1 and int(o) <= SLUICE_COUNT:
		s.outcome_at_stop = int(o)
	var dep = d.get("departed")
	if dep is Array:
		for n in dep:
			if n is String or n is StringName:
				s.departed.append(StringName(n))
	return s
