# M1: 프로젝트 기반 + 이동 + 태블릿 성능 실측 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 태블릿(Galaxy Tab S11 Ultra)에서 터치로 회색 박스 섬을 달리고·오르고·활공할 수 있는 3인칭 캐릭터를 만들고, 실제 FPS를 측정한다.

**Architecture:** 게임 규칙은 노드에 의존하지 않는 **모델 클래스**(`RefCounted`, `scripts/core/`)에 두고 헤드리스 단위 테스트로 검증한다. 노드(`scripts/nodes/`)는 입력 의도(`InputIntent`)를 모델에 넘기고 결과를 화면에 반영만 한다. 이 분리가 추후 코옵(서버 권한) 확장의 토대다.

**Tech Stack:** Godot 4.7.2, GDScript, Mobile 렌더러, 자체 경량 테스트 러너(애드온 없음).

**Spec:** `docs/design/01-core-design.md` (0장, 3장 기둥 1, 8장, 10장), `docs/design/02-combat-design.md` (2장 조작 체계)

---

## 프로토타입 로드맵 (각 마일스톤 = 별도 계획 문서)

| 마일스톤 | 내용 | 검증 질문 |
|---|---|---|
| **M1 (이 문서)** | 프로젝트 기반, 터치 입력, 이동(달리기·점프·등반·활공·스태미나), 카메라, 회색 섬, FPS 실측 | 태블릿에서 60 FPS 근처가 나오는가? 이동이 손에 붙는가? |
| M2 | 전투 코어: 락온, 회피(무적), 패링(무기·방패), 슬로우모션 연타, 한손검 | **터치 패링이 재미있는가?** (최대 리스크 — 가장 먼저 검증) |
| M3 | 수호 기계 2종(근접·원거리), 예고 신호(🟡/🔴), 대검·활, 내구도 | 회피만으로 이길 수 있고, 패링이 확실히 이득인가? |
| M4 | 원소(불·바람·젖음) 규칙표 + 기계 반응(과열·급냉 균열), 비 날씨 | 의도하지 않은 해법이 나오는가? |
| M5 | 첫 섬 본편: 지형·셀셰이딩·포그, 착취탑(정지 → 회색→컬러 전환), 거점 1곳 | 15분간 스스로 목표를 정해 움직이는가? |
| M6 | 마을 1개 + 적응 퀘스트 1개, 수리·요리·충전식 회복약, 체크포인트 저장 | 루프 3겹이 한 번 완주되는가? |
| M7 | 플레이테스트(01 문서 9장 성공 기준 5개) 및 수치 튜닝 | 확장 진행/재설계 판정 |

---

## Global Constraints

- 엔진: **Godot 4.7.2**, 언어: **GDScript만** (C# 금지 — Android 에디터 미지원).
- 렌더러: **Mobile** (`rendering/renderer/rendering_method="mobile"`). SDFGI·VoxelGI·볼류메트릭 포그 사용 금지.
- 모든 씬·리소스는 **텍스트 형식**(`.tscn`, `.tres`) — Git 병합 가능해야 함.
- 물리 틱 **60 Hz** 고정. 게임 판정은 `_physics_process`에서만.
- 성능 목표: **60 FPS 목표 / 30 FPS 하한**, 3D 해상도 스케일 **0.75** 시작.
- 화면: **가로 고정**(landscape), S11 Ultra 16:10 기준, UI는 앵커로 비율 대응.
- 조작: **터치 우선**. 오른손 버튼은 최대 4개(공격·강공격·회피·패링) — M1에서는 점프·달리기만 사용, 나머지 자리는 비워 둠.
- 튜닝 수치는 하드코딩 금지 — `MovementTuning` 리소스(`.tres`) 한 곳에 모은다.
- 문서·주석은 한국어, 식별자는 영어 snake_case(GDScript 관례).

## Review Focus

1. **멀티터치:** 한 손가락으로 스틱을 누른 채 다른 손가락으로 카메라를 드래그해도 스틱이 풀리거나 튀지 않아야 한다 (스틱은 자기 터치 index만 추적) → Task 5 테스트.
2. **등반 중 스태미나 0:** 벽에 붙은 채 멈추지 않고 떨어져야 하며, 활공 중 0이면 활공이 해제돼야 한다 → Task 3·4 테스트.
3. **섬 밖 추락:** y < −50 으로 떨어지면 마지막 안전 지점에서 재시작해야 한다 → Task 7 테스트.
4. **스태미나 고갈 직후 연타:** 0이 된 뒤 바로 달리기를 다시 눌러도, 회복 지연(1.0초)과 '탈진' 상태 동안 달리기·등반 시작이 거부돼야 한다 → Task 2 테스트.
5. **화면 회전/비율:** 세로로 돌려도 가로 고정 유지, 16:9 기기에서도 버튼이 화면 밖으로 나가지 않아야 한다 → Task 5 수동 확인 항목.

---

## File Structure

```
project.godot                      # Mobile 렌더러, 60Hz, 가로 고정, 입력 맵
scripts/core/                      # 노드 비의존 모델 (헤드리스 테스트 대상)
  movement_tuning.gd               # class_name MovementTuning (Resource) — 모든 이동 수치
  stamina.gd                       # class_name Stamina
  input_intent.gd                  # class_name InputIntent — 장치 독립 입력 의도
  locomotion.gd                    # class_name Locomotion — 이동 상태기계 + 속도 계산
  virtual_stick.gd                 # class_name VirtualStick — 터치 스틱 수학
  respawn_tracker.gd               # class_name RespawnTracker — 안전 지점·추락 판정
scripts/nodes/                     # 씬에 붙는 얇은 노드 스크립트
  player.gd                        # CharacterBody3D: 감지(레이캐스트) → Locomotion → move_and_slide
  orbit_camera.gd                  # SpringArm3D 3인칭 카메라
  touch_controls.gd                # Control: 스틱·버튼·카메라 드래그 → InputIntent
  debug_hud.gd                     # FPS·프레임타임·상태 표시
resources/movement_tuning.tres
scenes/player.tscn
scenes/touch_controls.tscn
scenes/test_island.tscn            # 회색 박스 섬 (M1 실측용)
tests/test_case.gd                 # class_name TestCase — assert 헬퍼
tests/run_tests.gd                 # 헤드리스 러너 (extends SceneTree)
tests/unit/test_*.gd
docs/perf/m1-tablet-measurements.md
```

테스트 실행 명령 (이후 모든 Task 공통, 저장소 루트에서):
```bash
godot --headless --path . -s tests/run_tests.gd
```
성공 시 마지막 줄 `ALL PASSED (N tests)`, 종료 코드 0. 실패 시 `FAILED: <파일>::<메서드> — <메시지>` 출력 후 종료 코드 1.

---

### Task 1: 프로젝트 골격 + 테스트 러너

**Files:**
- Create: `project.godot`, `.gitignore`, `tests/test_case.gd`, `tests/run_tests.gd`, `tests/unit/test_smoke.gd`

**Interfaces:**
- Produces: `TestCase` — `assert_eq(a, b, msg := "")`, `assert_true(c, msg := "")`, `assert_false(c, msg := "")`, `assert_almost(a: float, b: float, eps := 0.001, msg := "")`. 실패 시 내부 `_failures: Array[String]`에 기록. 러너는 `tests/unit/` 아래 `test_*.gd`를 찾아 인스턴스화하고 `test_`로 시작하는 메서드를 각각 실행(메서드마다 새 인스턴스).

- [ ] **Step 1: `project.godot` 작성** — `config/name="Open World"`, `config/features=PackedStringArray("4.7", "Mobile")`, `rendering/renderer/rendering_method="mobile"`, `physics/common/physics_ticks_per_second=60`, `display/window/handheld/orientation=0`(landscape), `rendering/scaling_3d/scale=0.75`, `input_devices/pointing/emulate_touch_from_mouse=true`(PC 디버그용). `.gitignore`에 `.godot/`, `*.import`는 **제외하지 않음**(Android 에디터 재임포트 비용 절감), `export_presets.cfg` 제외.
- [ ] **Step 2: 실패하는 스모크 테스트 작성** `tests/unit/test_smoke.gd`

```gdscript
extends TestCase
func test_runner_reports_failure():
	assert_eq(1 + 1, 3, "의도적 실패 — 러너가 실패를 잡는지 확인")
```
- [ ] **Step 3: `TestCase`, `run_tests.gd` 구현** (위 Interfaces 그대로).
- [ ] **Step 4: 실행 → FAIL 확인** — 출력에 `FAILED: test_smoke.gd::test_runner_reports_failure`, 종료 코드 1.
- [ ] **Step 5: 테스트를 `assert_eq(1 + 1, 2)`로 수정 → 실행 → `ALL PASSED (1 tests)`, 종료 코드 0.**
- [ ] **Step 6: Commit** — `git commit -m "chore: Godot 4.7.2 프로젝트 골격과 헤드리스 테스트 러너"`

---

### Task 2: 이동 수치 리소스 + 스태미나

**Files:**
- Create: `scripts/core/movement_tuning.gd`, `resources/movement_tuning.tres`, `scripts/core/stamina.gd`, `tests/unit/test_stamina.gd`

**Interfaces:**
- Produces: `MovementTuning extends Resource` — `@export` 필드와 기본값:
  `walk_speed=4.0, run_speed=6.0, sprint_speed=9.0, jump_velocity=5.0, gravity=20.0, climb_speed=2.0, glide_fall_speed=2.0, glide_speed=8.0, stamina_max=100.0, stamina_regen=25.0, stamina_regen_delay=1.0, sprint_cost=20.0, climb_cost=10.0, climb_jump_cost=20.0, glide_cost=8.0, exhausted_recover_ratio=0.3, fall_respawn_y=-50.0`
- Produces: `Stamina extends RefCounted` — `_init(tuning: MovementTuning)`, `var value: float`, `var exhausted: bool`, `func spend(amount: float) -> bool`(잔량 부족이면 남은 만큼 소모 후 `false`, 0 도달 시 `exhausted=true`), `func drain(rate: float, delta: float) -> bool`(지속 소모, 0 도달 시 `false`), `func tick(delta: float) -> void`(마지막 소모 후 `stamina_regen_delay` 지나면 회복; `exhausted`는 `value >= stamina_max * exhausted_recover_ratio`일 때 해제), `func can_start() -> bool`(`not exhausted and value > 0`).

- [ ] **Step 1: 실패하는 테스트 작성** `tests/unit/test_stamina.gd`

```gdscript
extends TestCase
var t := MovementTuning.new()

func test_drain_to_zero_sets_exhausted():
	var s := Stamina.new(t)
	for i in 300: s.drain(t.sprint_cost, 1.0 / 60.0)   # 5초 × 20/s = 100
	assert_almost(s.value, 0.0)
	assert_true(s.exhausted)
	assert_false(s.can_start())

func test_no_regen_during_delay():
	var s := Stamina.new(t)
	s.spend(50.0)
	s.tick(0.9)
	assert_almost(s.value, 50.0)

func test_regen_after_delay():
	var s := Stamina.new(t)
	s.spend(50.0)
	s.tick(1.0); s.tick(1.0)          # 지연 1초 후 1초 회복 = +25
	assert_almost(s.value, 75.0)

func test_exhaustion_clears_at_30_percent():   # Review Focus 4
	var s := Stamina.new(t)
	s.spend(100.0)
	s.tick(1.0); s.tick(1.0)          # 25 → 아직 탈진
	assert_true(s.exhausted)
	s.tick(0.2)                       # 30 → 해제
	assert_false(s.exhausted)

func test_regen_caps_at_max():
	var s := Stamina.new(t)
	s.spend(10.0)
	for i in 10: s.tick(1.0)
	assert_almost(s.value, 100.0)
```
- [ ] **Step 2: 실행 → FAIL** (`Stamina`/`MovementTuning` 미정의).
- [ ] **Step 3: `MovementTuning`, `Stamina` 구현, `resources/movement_tuning.tres`를 기본값으로 생성.**
- [ ] **Step 4: 실행 → `ALL PASSED`.**
- [ ] **Step 5: Commit** — `feat: 이동 수치 리소스와 스태미나 모델`

---

### Task 3: 입력 의도 + 지상 이동 상태기계 (달리기·전력질주·점프·낙하)

**Files:**
- Create: `scripts/core/input_intent.gd`, `scripts/core/locomotion.gd`, `tests/unit/test_locomotion_ground.gd`

**Interfaces:**
- Produces: `InputIntent extends RefCounted` — `var move: Vector2`(길이 ≤ 1, x=오른쪽, y=앞), `var sprint: bool`, `var jump_pressed: bool`(이번 틱에 눌림), `var jump_held: bool`, `var camera_yaw: float`(라디안; 이동 방향을 카메라 기준으로 변환할 때 사용).
- Produces: `Locomotion extends RefCounted`
  - `enum State { GROUNDED, AIRBORNE, CLIMBING, GLIDING }`
  - `_init(tuning: MovementTuning, stamina: Stamina)`
  - `var state: State`, `var velocity: Vector3`
  - `func step(intent: InputIntent, sense: Dictionary, delta: float) -> Vector3` — 새 속도를 반환하고 `state` 갱신. `sense` 키: `on_floor: bool`, `wall_normal: Vector3`(벽 없으면 `Vector3.ZERO`), `ledge_top: bool`(벽 꼭대기 도달).
  - 지상 속도: `|move| < 0.5` → walk, 그 이상 → run, `sprint` 그리고 `stamina.can_start()` → sprint(+`sprint_cost` 소모). 방향은 `move`를 `camera_yaw`만큼 Y축 회전.
  - 점프: GROUNDED에서 `jump_pressed` → `velocity.y = jump_velocity`, AIRBORNE.

- [ ] **Step 1: 실패하는 테스트** `tests/unit/test_locomotion_ground.gd`

```gdscript
extends TestCase
const DT := 1.0 / 60.0
var t := MovementTuning.new()
func _loco() -> Locomotion: return Locomotion.new(t, Stamina.new(t))
func _floor() -> Dictionary: return {"on_floor": true, "wall_normal": Vector3.ZERO, "ledge_top": false}
func _intent(move := Vector2.ZERO, sprint := false, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.sprint = sprint; i.jump_pressed = jump; return i

func test_full_stick_runs_forward():
	var v := _loco().step(_intent(Vector2(0, 1)), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.run_speed)
	assert_almost(v.z, -t.run_speed)          # Godot 전방 = -Z

func test_half_stick_walks():
	var v := _loco().step(_intent(Vector2(0, 0.4)), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.walk_speed)

func test_camera_yaw_rotates_direction():
	var i := _intent(Vector2(0, 1)); i.camera_yaw = PI / 2
	var v := _loco().step(i, _floor(), DT)
	assert_almost(v.x, -t.run_speed)

func test_sprint_spends_stamina_and_falls_back_when_exhausted():
	var l := _loco()
	for k in 301: l.step(_intent(Vector2(0, 1), true), _floor(), DT)
	var v := l.step(_intent(Vector2(0, 1), true), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.run_speed)   # 탈진 → 달리기로 복귀

func test_jump_leaves_ground():
	var l := _loco()
	var v := l.step(_intent(Vector2.ZERO, false, true), _floor(), DT)
	assert_almost(v.y, t.jump_velocity)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_gravity_applies_in_air():
	var l := _loco(); l.state = Locomotion.State.AIRBORNE
	var air := {"on_floor": false, "wall_normal": Vector3.ZERO, "ledge_top": false}
	var v := l.step(_intent(), air, DT)
	assert_almost(v.y, -t.gravity * DT)
```
- [ ] **Step 2: 실행 → FAIL.**
- [ ] **Step 3: `InputIntent`, `Locomotion`(GROUNDED/AIRBORNE 부분) 구현.**
- [ ] **Step 4: 실행 → `ALL PASSED`.**
- [ ] **Step 5: Commit** — `feat: 입력 의도와 지상 이동 상태기계`

---

### Task 4: 등반 + 활공

**Files:**
- Modify: `scripts/core/locomotion.gd`
- Create: `tests/unit/test_locomotion_climb_glide.gd`

**Interfaces:**
- Consumes: Task 3의 `Locomotion.step`, `sense` 딕셔너리.
- 규칙(스펙: 기둥 1 "제한은 불가능이 아니라 스태미나 부족으로만"):
  - AIRBORNE/GROUNDED에서 `wall_normal != ZERO` 이고 `move`가 벽 쪽(전방 성분 > 0.5)이며 `stamina.can_start()` → CLIMBING.
  - CLIMBING: 속도 = 벽 평면 위 `move` × `climb_speed`, 움직이는 동안 `climb_cost`/s 소모. 정지 시 소모 없음.
  - CLIMBING 중 `jump_pressed` → `climb_jump_cost` 소모, 위로 도약.
  - CLIMBING 중 스태미나 0 → AIRBORNE (벽에서 떨어짐). `ledge_top` → GROUNDED로 올라섬(위로 `jump_velocity` 절반 부여).
  - AIRBORNE에서 하강 중(`velocity.y < 0`) `jump_pressed` 그리고 `stamina.can_start()` → GLIDING.
  - GLIDING: `velocity.y = -glide_fall_speed`, 수평 = `move` 방향 × `glide_speed`, `glide_cost`/s 소모. 다시 `jump_pressed` 또는 스태미나 0 → AIRBORNE. 착지 → GROUNDED.

- [ ] **Step 1: 실패하는 테스트** `tests/unit/test_locomotion_climb_glide.gd`

```gdscript
extends TestCase
const DT := 1.0 / 60.0
var t := MovementTuning.new()
var wall := {"on_floor": false, "wall_normal": Vector3(0, 0, 1), "ledge_top": false}
var air := {"on_floor": false, "wall_normal": Vector3.ZERO, "ledge_top": false}
func _intent(move := Vector2.ZERO, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.jump_pressed = jump; return i

func test_pushing_into_wall_starts_climb():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_climb_up_moves_up_and_drains():
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.CLIMBING
	var v := l.step(_intent(Vector2(0, 1)), wall, 1.0)
	assert_almost(v.y, t.climb_speed)
	assert_almost(s.value, t.stamina_max - t.climb_cost)

func test_zero_stamina_falls_off_wall():          # Review Focus 2
	var s := Stamina.new(t); s.spend(100.0)
	var l := Locomotion.new(t, s); l.state = Locomotion.State.CLIMBING
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_exhausted_cannot_start_climb():          # Review Focus 4
	var s := Stamina.new(t); s.spend(100.0); s.tick(1.0); s.tick(0.5)   # 12.5, 탈진 중
	var l := Locomotion.new(t, s); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_ledge_top_climbs_onto_ground():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var top := wall.duplicate(); top["ledge_top"] = true
	l.step(_intent(Vector2(0, 1)), top, DT)
	assert_eq(l.state, Locomotion.State.GROUNDED)

func test_jump_while_falling_opens_glider():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.velocity = Vector3(0, -5, 0)
	var v := l.step(_intent(Vector2(0, 1), true), air, DT)
	assert_eq(l.state, Locomotion.State.GLIDING)
	assert_almost(v.y, -t.glide_fall_speed)

func test_glider_closes_when_stamina_empty():      # Review Focus 2
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.GLIDING
	s.spend(99.99)
	l.step(_intent(Vector2(0, 1)), air, 1.0)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
```
- [ ] **Step 2: 실행 → FAIL.**
- [ ] **Step 3: CLIMBING/GLIDING 구현.**
- [ ] **Step 4: 실행 → `ALL PASSED`** (Task 3 테스트 포함 전체).
- [ ] **Step 5: Commit** — `feat: 등반과 활공 (스태미나 연동)`

---

### Task 5: 터치 조작 (가상 스틱 + 버튼 + 카메라 드래그)

**Files:**
- Create: `scripts/core/virtual_stick.gd`, `tests/unit/test_virtual_stick.gd`, `scripts/nodes/touch_controls.gd`, `scenes/touch_controls.tscn`

**Interfaces:**
- Produces: `VirtualStick extends RefCounted` — `_init(radius_px: float = 120.0, dead_zone: float = 0.15)`, `func press(index: int, pos: Vector2) -> bool`(이미 다른 손가락이 잡고 있으면 `false`), `func drag(index: int, pos: Vector2) -> void`(자기 index만 반영), `func release(index: int) -> void`, `func value() -> Vector2`(길이 ≤ 1, 데드존 내 0, 화면 위쪽 = +y).
- Produces: `TouchControls`(Control) — `signal intent_updated(intent: InputIntent)`를 매 물리 틱 발신. 왼쪽 40% 영역 터치 = 스틱(누른 자리에 생성되는 플로팅 스틱), 오른쪽 나머지 영역 드래그 = 카메라(`var camera_drag: Vector2` 누적 후 틱마다 소비). 버튼: **점프**(오른쪽 하단), **달리기 토글**(점프 왼쪽). 공격·강공격·회피·패링 자리는 반투명 빈 원으로 표시만(M2에서 연결). 키보드/패드 대체: WASD/좌스틱, Space/A = 점프, Shift/LB = 달리기 — PC 디버그용, 같은 `InputIntent`로 수렴.

- [ ] **Step 1: 실패하는 테스트** `tests/unit/test_virtual_stick.gd`

```gdscript
extends TestCase
func test_full_deflection_up_is_plus_y():
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(200, 380))
	assert_almost(s.value().y, 1.0); assert_almost(s.value().x, 0.0)

func test_dead_zone_returns_zero():
	var s := VirtualStick.new(100.0, 0.15)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(210, 500))
	assert_eq(s.value(), Vector2.ZERO)

func test_second_finger_ignored():                 # Review Focus 1
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(300, 500))
	assert_false(s.press(1, Vector2(250, 450)))
	s.drag(1, Vector2(900, 100))
	assert_almost(s.value().x, 1.0)

func test_release_other_finger_keeps_stick():      # Review Focus 1
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(300, 500))
	s.release(1)
	assert_almost(s.value().x, 1.0)
	s.release(0)
	assert_eq(s.value(), Vector2.ZERO)
```
- [ ] **Step 2: 실행 → FAIL.**
- [ ] **Step 3: `VirtualStick` 구현, `TouchControls` 노드·씬 구현** (스틱은 `VirtualStick` 사용, `InputEventScreenTouch/ScreenDrag`의 `index`로 분배).
- [ ] **Step 4: 실행 → `ALL PASSED`.** 추가로 `godot --headless --path . --quit-after 120 scenes/touch_controls.tscn` 실행 시 에러 출력 없음.
- [ ] **Step 5: Commit** — `feat: 터치 가상 스틱·버튼·카메라 드래그 입력`

---

### Task 6: 플레이어 노드 + 3인칭 카메라

**Files:**
- Create: `scripts/nodes/player.gd`, `scripts/nodes/orbit_camera.gd`, `scenes/player.tscn`

**Interfaces:**
- Consumes: `Locomotion`, `Stamina`, `MovementTuning`(`resources/movement_tuning.tres`), `TouchControls.intent_updated`.
- Produces: `Player`(CharacterBody3D) — `var locomotion: Locomotion`, `var stamina: Stamina`, `func set_intent(intent: InputIntent)`. `_physics_process`에서 감지(전방 `RayCast3D` 1.0m → `wall_normal`, 머리 높이 전방 레이 미충돌 + 허리 높이 충돌 → `ledge_top`) → `locomotion.step` → `velocity` 대입 → `move_and_slide()` → `stamina.tick`. 캡슐 높이 1.8m, 반경 0.35m, 외형은 캡슐 메시 + 진행 방향 표시 콘.
- Produces: `OrbitCamera`(Node3D + SpringArm3D 길이 4.5m + Camera3D) — `func apply_drag(drag_px: Vector2)`: 감도 0.005 rad/px, 피치 −70°~+40° 클램프, 스프링암이 지형 충돌 시 당겨짐. `var yaw: float`를 플레이어가 `InputIntent.camera_yaw`로 사용.

- [ ] **Step 1: `player.tscn` 구성 및 스크립트 구현.**
- [ ] **Step 2: 검증** — 임시 평지 씬에서 `godot --headless --path . --quit-after 300 scenes/player.tscn` 실행 시 에러 없음, 전체 테스트 `ALL PASSED`.
- [ ] **Step 3: Commit** — `feat: 플레이어 노드와 3인칭 오빗 카메라`

---

### Task 7: 회색 박스 테스트 섬 + 추락 재시작 + 디버그 HUD

**Files:**
- Create: `scripts/core/respawn_tracker.gd`, `tests/unit/test_respawn_tracker.gd`, `scripts/nodes/debug_hud.gd`, `scenes/test_island.tscn`

**Interfaces:**
- Produces: `RespawnTracker extends RefCounted` — `_init(fall_y: float)`, `func update(pos: Vector3, on_floor: bool, delta: float) -> bool`(바닥에 1.0초 이상 연속으로 서 있으면 그 위치를 안전 지점으로 저장; `pos.y < fall_y`면 `true` 반환 = 재시작 필요), `var safe_point: Vector3`.
- 섬 구성(약 300m × 300m, 기획서 8장): 바다 평면 + 섬 지면, **높이 5·15·40m 절벽 3개**(등반 스태미나 한계 체감용 — 40m는 기본 스태미나로 못 오르고 중간 착지점 필요), **활공 출발용 언덕 1개**, 멀리서 보이는 **착취탑 자리 표시 기둥(높이 60m)** 1개. 머티리얼은 단색 `StandardMaterial3D` 3종(지면·바위·탑). `DirectionalLight3D` 그림자 on, 일반 거리 포그 on.
- `DebugHud`: 좌상단에 `FPS`, `frame ms`(1초 평균·최악), `state`, `stamina` 표시. 3초마다 `print("PERF fps=%d avg_ms=%.1f worst_ms=%.1f")` 로그.

- [ ] **Step 1: 실패하는 테스트** `tests/unit/test_respawn_tracker.gd`

```gdscript
extends TestCase
func test_falling_below_threshold_requests_respawn():   # Review Focus 3
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(10, 2, 10), true, 1.1)
	assert_true(r.update(Vector3(10, -51, 10), false, 0.016))
	assert_eq(r.safe_point, Vector3(10, 2, 10))

func test_brief_touch_is_not_safe_point():
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(0, 1, 0), true, 1.1)
	r.update(Vector3(5, 1, 5), true, 0.5)
	assert_eq(r.safe_point, Vector3(0, 1, 0))
```
- [ ] **Step 2: 실행 → FAIL.**
- [ ] **Step 3: `RespawnTracker` 구현, `Player`에 연결(재시작 시 위치 = `safe_point + Vector3.UP`, 속도 0), `test_island.tscn` 구성(Player + TouchControls + DebugHud), `project.godot`의 메인 씬으로 지정.**
- [ ] **Step 4: 실행 → `ALL PASSED`**, `godot --headless --path . --quit-after 600` 실행 시 에러 없음 + `PERF` 로그 출력 확인.
- [ ] **Step 5: Commit** — `feat: 회색 박스 테스트 섬, 추락 재시작, 디버그 HUD`

---

### Task 8: 태블릿 실측 (사용자 수행)

**Files:**
- Create: `docs/perf/m1-tablet-measurements.md` (Claude가 측정 양식 작성 → 사용자가 값 기입)

- [ ] **Step 1: 측정 양식 작성** — 표 열: 장면(섬 중앙 전경 / 절벽 아래 / 탑 방향 원경 / 활공 중), 평균 FPS, 최악 ms, 발열 체감(상/중/하), 비고. 그리고 조작감 체크리스트:
  - 스틱을 누른 채 카메라 드래그가 자연스러운가 (Review Focus 1)
  - 40m 절벽에서 스태미나가 바닥나면 떨어지는가 (Review Focus 2)
  - 섬 밖으로 떨어지면 재시작되는가 (Review Focus 3)
  - 기기를 세로로 돌려도 가로가 유지되는가, 버튼이 화면 안에 있는가 (Review Focus 5)
  - 달리기·점프·활공의 속도감 (빠름/적당/느림)
- [ ] **Step 2: 사용자 수행** — Termux `git pull` → Godot 4.7.2 Android 에디터에서 프로젝트 열기 → 실행 → 각 장면 30초 이상 → 양식 기입 → `git commit`·`git push`.
- [ ] **Step 3: 판정** — 평균 FPS ≥ 55면 통과. 30~55면 해상도 스케일·그림자 조정 후 재측정. 30 미만이면 M2 이전에 렌더링 설정 재검토 회의.
