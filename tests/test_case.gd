class_name TestCase
extends RefCounted
## 단위 테스트 기반 클래스. 실패는 예외 대신 _failures에 기록한다.

var _failures: Array[String] = []


func assert_eq(a, b, msg := "") -> void:
	if a != b:
		_fail("expected %s == %s" % [str(a), str(b)], msg)


func assert_true(c, msg := "") -> void:
	if not c:
		_fail("expected true", msg)


func assert_false(c, msg := "") -> void:
	if c:
		_fail("expected false", msg)


func assert_almost(a: float, b: float, eps := 0.001, msg := "") -> void:
	if absf(a - b) > eps:
		_fail("expected %f ≈ %f (eps %f)" % [a, b, eps], msg)


func _fail(detail: String, msg: String) -> void:
	_failures.append(detail if msg.is_empty() else "%s — %s" % [detail, msg])
