# M2: 전투 코어 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 테스트 섬에 공격해 오는 허수아비 적을 두고, 태블릿 터치로 전투 상태·카메라 정렬·한손검 공격·자동 조준·공격 중 회피·방어/패링·슬로우모션 연타·상호작용 팝업을 체험할 수 있게 한다. 핵심 검증 질문: **"터치 패링이 재미있는가?"**

**Architecture:** M1과 같은 구조. 판정 규칙은 노드 비의존 모델(`scripts/core/`, `RefCounted`)로 만들어 헤드리스 테스트하고, 노드(`scripts/nodes/`)는 감지·연출만 한다. 적의 공격은 **단계 기계**(대기→예고→공격→회복)로 모델링하고, 슬로우모션은 전역 `Engine.time_scale` 대신 **적 개체별 시간 배율**로 처리한다.

**Tech Stack:** Godot 4.7.2, GDScript, Mobile 렌더러, 자체 테스트 러너(`./run_tests.sh`).

**Spec:** `docs/design/02-combat-design.md` (C2, C5, C7, C10~C16, 2장 조작표, 2.1 전투 상태, 3장 회피·패링), `docs/design/01-core-design.md` (기둥 2·4)

---

## Global Constraints

- Godot 4.7.2, GDScript만, Mobile 렌더러, 텍스트 씬(`.tscn`/`.tres`), 판정은 `_physics_process`(60 Hz)에서만.
- 오른손 버튼: **공격 · 방어 · 점프/회피** 3개 + **상호작용 팝업**(대상이 있을 때만, 오른손 버튼 위 고정 위치, 대상 이름 표시) — C15.
- **공격은 적이 없어도 휘두른다.** 탭 = 공격, 길게(0.4초) = 강공격.
- **방어 버튼:** 누르는 순간 = 패링 판정, 누르고 있으면 = 방어 자세 — C11.
- **점프/회피:** 스틱 + 점프 = 그 방향 점프. **적의 공격 중**(예고 시작 ~ 공격 끝)에만 스틱 + 점프 = 회피 (앞 = 구르기, 뒤 = 뒤로 도약, 좌·우 = 옆 도약). 회피 중 캐릭터는 앞을 바라봄 — C16.
- **전투 상태:** 진입 15m / 해제 25m + 3초. 전투 중에는 걷기도 이동 방향으로 회전, 카메라는 캐릭터 등 뒤로 자동 정렬(오른손 누르는 동안 정지, 뗀 뒤 0.5초 후 재개, 회피 중 정지, 초당 180°), 자동 달리기 해제 — 2.1절, C14.
- 예고 신호 색: 🟡 노랑 = 패링 가능, 🔴 빨강 = 패링 불가(방어 시 가드 브레이크).
- 패링 판정 창: 무기 **0.2초**, 방패 **0.35초**. 1초 안에 다시 누를 때마다 창 30% 축소(최소 40%).
- 패링 성공 → 그 적만 **1.5초간 시간 배율 0.2** (슬로우모션 연타) — C5.
- 모든 튜닝 수치는 `resources/combat_tuning.tres`(`CombatTuning`) 한 곳에.

## Review Focus

1. **방어 버튼 연타:** 아무 때나 연타해도 패링이 보장되면 안 된다 (연타할수록 창 축소) → Task 4 테스트.
2. **스태미나 바닥에서 회피:** 탈진 중 회피 입력은 거부되고 일반 점프도 하지 않는다(제자리) → Task 3 테스트.
3. **전투 상태 깜빡임:** 15~25m 경계에서 왔다 갔다 해도 상태가 매 틱 바뀌지 않는다 → Task 1 테스트.
4. **카메라가 손가락과 싸움:** 오른손으로 시점을 돌리는 중·직후 0.5초·회피 중에는 자동 정렬이 멈춘다 → Task 6 테스트.
5. **상호작용 대상 선택:** 뒤에 있는 대상이 앞의 대상보다 우선되면 안 되고, 전투 중에도 팝업이 뜬다 → Task 8 테스트.

---

## File Structure

```
scripts/core/
  combat_tuning.gd        # class_name CombatTuning (Resource) — 전투 수치 전부
  combat_state.gd         # class_name CombatState — 진입/해제 히스테리시스
  enemy_attack.gd         # class_name EnemyAttack — 대기→예고→공격→회복 단계 기계
  dodge.gd                # class_name Dodge — 회피 종류 판정 + 무적 시간
  guard.gd                # class_name Guard — 방어/패링 판정, 연타 패널티
  flurry.gd               # class_name Flurry — 슬로우모션 연타 창
  targeting.gd            # class_name Targeting — 자동 조준 대상 선택(정적 함수)
  camera_follow.gd        # class_name CameraFollow — 전투 카메라 정렬 규칙
  interact_picker.gd      # class_name InteractPicker — 상호작용 대상 선택(정적 함수)
scripts/nodes/
  player_combat.gd        # Player 자식 노드: 체력·공격·방어·회피 연결
  training_dummy.gd       # 허수아비 적 (CharacterBody3D)
  interactable.gd         # 줍기 대상 (Area3D, 그룹 "interactable")
resources/combat_tuning.tres
scenes/training_dummy.tscn, scenes/pickup_part.tscn
```
수정: `input_intent.gd`, `locomotion.gd`, `player.gd`, `player.tscn`, `orbit_camera.gd`, `touch_controls.gd`, `debug_hud.gd`, `test_island.tscn`.

테스트 명령(모든 Task 공통): `./run_tests.sh` → 마지막 줄 `ALL PASSED (N tests)`, 종료 코드 0.

---

### Task 1: 전투 수치 + 전투 상태

**Files:** Create `scripts/core/combat_tuning.gd`, `resources/combat_tuning.tres`, `scripts/core/combat_state.gd`, `tests/unit/test_combat_state.gd` · Modify `scripts/core/input_intent.gd`, `scripts/core/locomotion.gd`, `tests/unit/test_locomotion_ground.gd`

**Interfaces:**
- Produces: `CombatTuning extends Resource` — `@export` 기본값:
  `combat_enter_dist=15.0, combat_exit_dist=25.0, combat_exit_delay=3.0, dodge_speed=8.0, dodge_duration=0.45, dodge_iframes=0.3, dodge_cost=15.0, parry_window_weapon=0.2, parry_window_shield=0.35, parry_spam_window=1.0, parry_spam_shrink=0.3, parry_min_ratio=0.4, guard_cost=15.0, flurry_duration=1.5, flurry_enemy_time_scale=0.2, camera_follow_deg_per_sec=180.0, camera_resume_delay=0.5, target_range=6.0, target_cone_deg=120.0, attack_damage=10.0, heavy_hold_time=0.4, heavy_damage=25.0, combo_window=0.6, player_max_hp=100.0`
- Produces: `CombatState extends RefCounted` — `_init(t: CombatTuning)`, `var active: bool`, `func update(nearest_alert_dist: float, engaged: bool, delta: float) -> bool` (`engaged` = 이번 틱에 공격했거나 맞음 → 즉시 진입; 경계 적이 없으면 `nearest_alert_dist = INF`).
- Produces: `InputIntent.in_combat: bool`, `InputIntent.threatened: bool`(적의 공격 중), `InputIntent.facing_yaw: float`. `Locomotion.turns_to_move`는 `in_combat`이면 `true`.

- [ ] **Step 1: 실패 테스트** `tests/unit/test_combat_state.gd`
```gdscript
extends TestCase
var t := CombatTuning.new()
func test_enters_within_15m():
	var c := CombatState.new(t)
	assert_true(c.update(14.0, false, 0.016))
func test_stays_between_15_and_25m():                 # Review Focus 3
	var c := CombatState.new(t); c.update(10.0, false, 0.016)
	for i in 600: c.update(20.0, false, 0.016)        # 10초 경계 안
	assert_true(c.active)
func test_exits_after_3s_beyond_25m():
	var c := CombatState.new(t); c.update(10.0, false, 0.016)
	c.update(30.0, false, 2.9); assert_true(c.active)
	c.update(30.0, false, 0.2); assert_false(c.active)
func test_engaged_enters_immediately_without_enemy():
	var c := CombatState.new(t)
	assert_true(c.update(INF, true, 0.016))
```
그리고 `test_locomotion_ground.gd`에 추가:
```gdscript
func test_in_combat_walk_turns_to_move():
	var i := _intent(Vector2(0.3, 0)); i.in_combat = true
	assert_true(Locomotion.turns_to_move(i, t))
```
- [ ] **Step 2:** `./run_tests.sh` → FAIL (`CombatState` 미정의).
- [ ] **Step 3:** `CombatTuning`, `combat_tuning.tres`(기본값), `CombatState`, `InputIntent` 필드 3개, `turns_to_move`의 `in_combat` 분기(자동 달리기 다음, `camera_held` 앞) 구현.
- [ ] **Step 4:** `./run_tests.sh` → ALL PASSED.
- [ ] **Step 5: Commit** — `feat: 전투 수치 리소스와 전투 상태(진입·해제 히스테리시스)`

---

### Task 2: 적 공격 단계 기계

**Files:** Create `scripts/core/enemy_attack.gd`, `tests/unit/test_enemy_attack.gd`

**Interfaces:**
- Produces: `EnemyAttack extends RefCounted`
  - `enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVER }`, `var phase`, `var parryable: bool`(🟡 true / 🔴 false)
  - `_init(telegraph := 0.6, active := 0.2, recover := 0.8)`
  - `func start(parryable: bool) -> void` (IDLE에서만 시작)
  - `func tick(delta: float) -> Array[StringName]` — 이번 틱에 일어난 이벤트 목록: `&"hit"`(ACTIVE 진입 순간 = 판정 시점), `&"done"`(RECOVER 끝 → IDLE)
  - `func is_threatening() -> bool` — TELEGRAPH 또는 ACTIVE (= C16 회피 문맥)
  - `func time_to_hit() -> float` — TELEGRAPH 중 남은 시간, 그 외 0

- [ ] **Step 1: 실패 테스트**
```gdscript
extends TestCase
func test_full_cycle_emits_hit_then_done():
	var a := EnemyAttack.new(0.6, 0.2, 0.8); a.start(true)
	assert_eq(a.phase, EnemyAttack.Phase.TELEGRAPH)
	assert_true(a.is_threatening())
	assert_eq(a.tick(0.6), [&"hit"]); assert_eq(a.phase, EnemyAttack.Phase.ACTIVE)
	a.tick(0.2); assert_eq(a.phase, EnemyAttack.Phase.RECOVER); assert_false(a.is_threatening())
	assert_eq(a.tick(0.8), [&"done"]); assert_eq(a.phase, EnemyAttack.Phase.IDLE)
func test_time_to_hit_counts_down():
	var a := EnemyAttack.new(0.6, 0.2, 0.8); a.start(false)
	a.tick(0.4); assert_almost(a.time_to_hit(), 0.2)
func test_start_ignored_unless_idle():
	var a := EnemyAttack.new(); a.start(true); a.start(false)
	assert_true(a.parryable)
```
- [ ] **Step 2:** FAIL 확인 → **Step 3:** 구현 (한 틱에 여러 단계를 넘을 만큼 큰 delta는 넘친 시간을 다음 단계로 이월) → **Step 4:** PASS → **Step 5: Commit** — `feat: 적 공격 단계 기계(예고·공격·회복)`

---

### Task 3: 회피 (적의 공격 중 + 스틱 + 점프)

**Files:** Create `scripts/core/dodge.gd`, `tests/unit/test_dodge.gd` · Modify `scripts/core/locomotion.gd` (`State.DODGING` 추가), `tests/unit/test_locomotion_ground.gd`

**Interfaces:**
- Produces: `Dodge extends RefCounted` — `enum Kind { ROLL_FORWARD, HOP_BACK, HOP_LEFT, HOP_RIGHT }`, `static func classify(move_world: Vector3, facing_yaw: float) -> Kind`(캐릭터 정면 기준 ±45° = 앞, 뒤 ±45° = 뒤, 나머지 좌·우).
- `Locomotion` 확장: `Locomotion.new(tuning, stamina, combat_tuning := CombatTuning.new())`, `var dodge_kind`, `func is_invulnerable() -> bool`(회피 시작 후 `dodge_iframes` 동안). 규칙: GROUNDED에서 `intent.threatened and intent.jump_pressed and move != 0` → `stamina.spend(dodge_cost)`가 가능하면(`can_start()`) DODGING, 속도 = 이동 방향 × `dodge_speed`, `dodge_duration` 후 GROUNDED. **탈진이면 아무것도 안 함**(점프도 안 함). `threatened`가 아니면 기존대로 방향 점프.
- Player는 DODGING 중 바라보는 방향을 바꾸지 않는다 (Task 7에서 연결).

- [ ] **Step 1: 실패 테스트**
```gdscript
# test_dodge.gd
extends TestCase
func test_back_relative_to_facing_is_hop_back():
	assert_eq(Dodge.classify(Vector3(0, 0, 1), 0.0), Dodge.Kind.HOP_BACK)     # 정면 -Z, 이동 +Z
func test_forward_is_roll():
	assert_eq(Dodge.classify(Vector3(0, 0, -1), 0.0), Dodge.Kind.ROLL_FORWARD)
func test_side_respects_facing_yaw():
	assert_eq(Dodge.classify(Vector3(0, 0, -1), PI / 2), Dodge.Kind.HOP_RIGHT)  # 정면 -X일 때 -Z는 오른쪽
```
`test_locomotion_ground.gd`에 추가:
```gdscript
func test_threatened_jump_with_stick_dodges():
	var s := Stamina.new(t); var l := Locomotion.new(t, s)
	var i := _intent(Vector2(0, -1), true); i.threatened = true
	l.step(i, _floor(), DT)
	assert_eq(l.state, Locomotion.State.DODGING)
	assert_true(l.is_invulnerable())
	assert_almost(s.value, t.stamina_max - CombatTuning.new().dodge_cost)
func test_not_threatened_jump_with_stick_is_jump():
	var l := _loco(); l.step(_intent(Vector2(0, -1), true), _floor(), DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
func test_exhausted_dodge_does_nothing():               # Review Focus 2
	var s := Stamina.new(t); s.spend(100.0); var l := Locomotion.new(t, s)
	var i := _intent(Vector2(0, -1), true); i.threatened = true
	var v := l.step(i, _floor(), DT)
	assert_eq(l.state, Locomotion.State.GROUNDED); assert_almost(v.y, 0.0)
func test_dodge_ends_after_duration():
	var l := _loco(); var i := _intent(Vector2(1, 0), true); i.threatened = true
	l.step(i, _floor(), DT)
	for k in 30: l.step(_intent(), _floor(), DT)          # 0.5초 > 0.45
	assert_eq(l.state, Locomotion.State.GROUNDED); assert_false(l.is_invulnerable())
```
- [ ] **Step 2:** FAIL → **Step 3:** 구현 (`DebugHud.STATE_NAMES`에 `"DODGING"` 추가) → **Step 4:** PASS → **Step 5: Commit** — `feat: 적의 공격 중 방향 회피(구르기·뒤로·옆 도약)`

---

### Task 4: 방어와 패링

**Files:** Create `scripts/core/guard.gd`, `tests/unit/test_guard.gd`

**Interfaces:**
- Produces: `Guard extends RefCounted` — `_init(t: CombatTuning)`, `enum Result { PARRIED, BLOCKED, GUARD_BREAK, HIT }`
  - `func press() -> void`(누르는 순간; 1초 안 재입력마다 창 배율 ×0.7, 최소 0.4), `func release() -> void`, `func tick(delta: float) -> void`, `var holding: bool`
  - `func resolve(parryable: bool, has_shield: bool) -> Result` — 적 공격의 `&"hit"` 순간에 호출. 마지막 `press()`로부터 경과 시간 ≤ 창(무기 0.2 / 방패 0.35 × 배율)이고 `parryable`이면 PARRIED. 아니면 `holding`이면: 🔴(parryable=false) → GUARD_BREAK, 🟡 → BLOCKED. 그 외 HIT.

- [ ] **Step 1: 실패 테스트**
```gdscript
extends TestCase
var t := CombatTuning.new()
func test_press_just_before_hit_parries():
	var g := Guard.new(t); g.press(); g.tick(0.15)
	assert_eq(g.resolve(true, false), Guard.Result.PARRIED)
func test_weapon_window_is_narrower_than_shield():
	var g := Guard.new(t); g.press(); g.tick(0.3)
	assert_eq(g.resolve(true, false), Guard.Result.BLOCKED)   # 무기 0.2 초과, 누르고 있음
	var h := Guard.new(t); h.press(); h.tick(0.3)
	assert_eq(h.resolve(true, true), Guard.Result.PARRIED)    # 방패 0.35 이내
func test_red_attack_cannot_be_parried_and_breaks_guard():
	var g := Guard.new(t); g.press(); g.tick(0.05)
	assert_eq(g.resolve(false, true), Guard.Result.GUARD_BREAK)
func test_spam_shrinks_window():                            # Review Focus 1
	var g := Guard.new(t)
	for k in 3:
		g.press(); g.release(); g.tick(0.2)
	g.press(); g.tick(0.15)                                  # 4번째: 창 0.2×0.7³≈0.069 (최소 0.4배=0.08)
	assert_eq(g.resolve(true, false), Guard.Result.BLOCKED)
func test_no_guard_is_hit():
	assert_eq(Guard.new(t).resolve(true, false), Guard.Result.HIT)
```
- [ ] **Step 2:** FAIL → **Step 3:** 구현 → **Step 4:** PASS → **Step 5: Commit** — `feat: 방어·패링 판정(무기/방패 창, 연타 패널티, 가드 브레이크)`

---

### Task 5: 자동 조준 + 슬로우모션 연타

**Files:** Create `scripts/core/targeting.gd`, `scripts/core/flurry.gd`, `tests/unit/test_targeting.gd`, `tests/unit/test_flurry.gd`

**Interfaces:**
- Produces: `Targeting` — `static func pick(origin: Vector3, forward: Vector3, candidates: Array[Vector3], range: float, cone_deg: float) -> int` (후보 인덱스, 없으면 -1). 점수 = 거리 + 각도(라디안)×3, 낮을수록 우선. 사거리 밖·원뿔 밖 제외. `cone_deg`는 전체 각(120 = 정면 좌우 60°씩).
- Produces: `Flurry extends RefCounted` — `_init(t: CombatTuning)`, `func start() -> void`, `func tick(delta: float) -> void`, `var active: bool`, `func enemy_time_scale() -> float`(활성 0.2, 아니면 1.0).

- [ ] **Step 1: 실패 테스트**
```gdscript
# test_targeting.gd
extends TestCase
func test_prefers_enemy_in_front_over_closer_one_to_the_side():
	var c: Array[Vector3] = [Vector3(2.5, 0, 0), Vector3(0, 0, -3)]
	assert_eq(Targeting.pick(Vector3.ZERO, Vector3.FORWARD, c, 6.0, 120.0), 1)
func test_ignores_out_of_range_and_behind():
	var c: Array[Vector3] = [Vector3(0, 0, -7), Vector3(0, 0, 2)]
	assert_eq(Targeting.pick(Vector3.ZERO, Vector3.FORWARD, c, 6.0, 120.0), -1)
# test_flurry.gd
extends TestCase
func test_flurry_slows_enemy_for_duration():
	var f := Flurry.new(CombatTuning.new()); f.start()
	assert_almost(f.enemy_time_scale(), 0.2)
	f.tick(1.4); assert_true(f.active)
	f.tick(0.2); assert_false(f.active); assert_almost(f.enemy_time_scale(), 1.0)
```
- [ ] **Step 2:** FAIL → **Step 3:** 구현 → **Step 4:** PASS → **Step 5: Commit** — `feat: 자동 조준 대상 선택과 슬로우모션 연타 창`

---

### Task 6: 전투 카메라 정렬 규칙

**Files:** Create `scripts/core/camera_follow.gd`, `tests/unit/test_camera_follow.gd` · Modify `scripts/nodes/orbit_camera.gd`

**Interfaces:**
- Produces: `CameraFollow extends RefCounted` — `_init(t: CombatTuning)`, `func step(cam_yaw: float, target_yaw: float, delta: float, held: bool, dodging: bool) -> float` (새 yaw). `held`면 정지하고 떼어진 후 0.5초 대기, `dodging`이면 정지, 그 외 최단 각도로 초당 180° 이하 회전. 반환값은 `cam_yaw`에서 연속적으로 이어지는 값(±π로 wrap하지 않음). 생성 직후에는 대기 없이 바로 따라감.
- `OrbitCamera.follow(target_yaw: float, delta: float, held: bool, dodging: bool)` — 내부 `CameraFollow` 사용, `yaw` 갱신.

- [ ] **Step 1: 실패 테스트**
```gdscript
extends TestCase
var t := CombatTuning.new()
func test_rotates_toward_target_at_limited_speed():
	var f := CameraFollow.new(t)
	assert_almost(f.step(0.0, PI, 0.5, false, false), deg_to_rad(90.0))
func test_held_stops_and_waits_after_release():          # Review Focus 4
	var f := CameraFollow.new(t)
	assert_almost(f.step(0.0, PI, 0.1, true, false), 0.0)
	assert_almost(f.step(0.0, PI, 0.4, false, false), 0.0)   # 뗀 뒤 0.4초: 아직 대기
	assert_true(f.step(0.0, PI, 0.2, false, false) > 0.0)    # 0.6초: 재개
func test_dodging_stops_follow():                        # Review Focus 4
	assert_almost(CameraFollow.new(t).step(0.0, PI, 0.5, false, true), 0.0)
func test_takes_shortest_way_around():
	var y := CameraFollow.new(t).step(deg_to_rad(170), deg_to_rad(-170), 0.05, false, false)
	assert_true(y > deg_to_rad(170))
```
- [ ] **Step 2:** FAIL → **Step 3:** 구현 → **Step 4:** PASS → **Step 5: Commit** — `feat: 전투 카메라 자동 정렬 규칙`

---

### Task 7: 플레이어 전투 연결 + 허수아비 적

**Files:** Create `scripts/nodes/player_combat.gd`, `scripts/nodes/training_dummy.gd`, `scenes/training_dummy.tscn` · Modify `player.gd`, `player.tscn`, `touch_controls.gd`, `debug_hud.gd`, `test_island.tscn`

**Interfaces:**
- Consumes: Task 1~6 전부.
- `TouchControls`: 공격 버튼(탭 → `intent.attack_pressed`, 0.4초 유지 → `intent.heavy_released`), 방어 버튼(`intent.guard_pressed`/`guard_held`), 점프 버튼 아이콘은 `set_threatened(bool)`로 점프↔회피 교체. `InputIntent`에 `attack_pressed`, `heavy_released`, `guard_pressed`, `guard_held` 추가.
- `PlayerCombat`(Player 자식 Node): `var hp`, `signal died`, `func on_enemy_hit(attack: EnemyAttack, enemy: Node3D) -> void`(무적이면 무시 → 아니면 `Guard.resolve` 결과 처리: PARRIED → `Flurry.start()` + 적 `stagger()`, BLOCKED → 스태미나 −`guard_cost`, GUARD_BREAK → 1초 경직 + 피해 20, HIT → 피해 20). 공격: 탭마다 3단 콤보(`combo_window` 안 재입력), 판정 = 정면 1.8m 반경 구 안의 `"enemy"` 그룹에 `attack_damage`(강공격 `heavy_damage`), 적이 없어도 모션 재생. 공격 직전 `Targeting.pick`으로 대상이 있으면 그쪽으로 즉시 회전.
- `Player`: 매 틱 가장 가까운 경계 중 적 거리로 `CombatState.update`, `intent.in_combat`/`threatened`(가까운 적 중 하나라도 `is_threatening()`)/`facing_yaw` 채움, 전투 중이면 `OrbitCamera.follow(facing, …, intent.camera_held, state == DODGING)`, 진입 시 `touch_controls.cancel_auto_run()`, DODGING 중 바라보기 고정, 체력 0 → `_respawn()` + 체력 회복.
- `TrainingDummy`(CharacterBody3D, 그룹 `"enemy"`): 경계 반경 15m, 플레이어를 향해 회전만(이동 없음), 2.5m 안이면 `EnemyAttack`을 반복 시작(3회 중 1회 🔴), 예고 동안 머리 구체 발광(🟡/🔴), `&"hit"` 순간 플레이어가 2.5m·전방 120° 안이면 `PlayerCombat.on_enemy_hit`. 시간 배율 = `Flurry.enemy_time_scale()`(플레이어가 제공), `hp=100`, 0이면 3초 뒤 부활. `func stagger()`: 진행 중 공격 취소 + 1초 경직.
- 섬 배치: 시작 지점 북쪽 20m에 허수아비 2기 (5m 간격).
- `DebugHud`: `HP`, `전투`, 마지막 방어 결과(PARRIED 등) 표시.

- [ ] **Step 1:** 노드·씬 구현.
- [ ] **Step 2: 헤드리스 프로브로 검증** (임시 `tests/_probe_tmp.gd`, 커밋하지 않음): ① 허수아비 2.5m 앞에서 아무 입력 없이 서 있으면 hp 감소 ② 🟡 예고 중 `time_to_hit()` ≤ 0.15일 때 `guard_pressed` → 결과 PARRIED, 해당 허수아비 time_scale 0.2 ③ 예고 중 스틱 뒤 + 점프 → DODGING, hp 유지 ④ 허수아비에서 30m 떨어져 3초 후 전투 해제. 전체 `./run_tests.sh` → ALL PASSED, `godot --headless --path . --quit-after 600` 에러 없음.
- [ ] **Step 3: Commit** — `feat: 플레이어 전투 연결과 허수아비 적`

---

### Task 8: 상호작용 팝업 (줍기)

**Files:** Create `scripts/core/interact_picker.gd`, `tests/unit/test_interact_picker.gd`, `scripts/nodes/interactable.gd`, `scenes/pickup_part.tscn` · Modify `touch_controls.gd`, `player.gd`, `test_island.tscn`, `debug_hud.gd`

**Interfaces:**
- Produces: `InteractPicker` — `static func pick(origin: Vector3, forward: Vector3, positions: Array[Vector3], radius := 2.0, cone_deg := 160.0) -> int`(가장 가까운 대상, 원뿔 밖 제외. `cone_deg`는 전체 각).
- `Interactable`(Area3D, 그룹 `"interactable"`): `@export var label := "기계 부품"`, `func interact(player: Player) -> void`(M2: 줍기 → `queue_free()`, 플레이어 `parts` +1).
- `TouchControls.show_interact(label: String)` / `hide_interact()`: 팝업 버튼을 공격 버튼 위(오른손 버튼 위 고정 위치)에 "줍기: <label>"로 표시, 탭 → `intent.interact_pressed`.
- 섬 배치: 허수아비 주변 3개, 시작 지점 근처 2개.

- [ ] **Step 1: 실패 테스트**
```gdscript
extends TestCase
func test_picks_nearest_in_front():
	var p: Array[Vector3] = [Vector3(0, 0, -1.8), Vector3(0, 0, -1.0)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), 1)
func test_ignores_directly_behind_even_if_closer():      # Review Focus 5
	var p: Array[Vector3] = [Vector3(0, 0, 0.5), Vector3(0, 0, -1.5)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), 1)
func test_none_in_radius():
	var p: Array[Vector3] = [Vector3(0, 0, -3)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), -1)
```
- [ ] **Step 2:** FAIL → **Step 3:** 구현 (팝업은 전투 상태와 무관하게 표시) → **Step 4:** PASS + 프로브: 허수아비 옆(전투 중)에서도 팝업 표시·줍기 성공 → **Step 5: Commit** — `feat: 상호작용 팝업과 줍기`

---

### Task 9: 태블릿 확인 (사용자 수행)

**Files:** Create `docs/perf/m2-combat-check.md` (Claude가 양식 작성)

- [ ] **Step 1: 양식 작성** — 조작 안내(공격 탭/길게, 방어 누르는 순간/유지, 🟡/🔴 의미, 적의 공격 중 스틱+점프 = 회피, 줍기 팝업)와 체크리스트:
  - 🟡 예고를 보고 방어 버튼으로 패링이 **10번 중 몇 번** 성공하는가 / 성공했을 때 짜릿한가 (**M2 핵심 질문**)
  - 회피(뒤·옆·앞)가 의도한 방향으로 나가는가 / 회피 중 화면이 흔들리지 않는가
  - 전투 진입 시 카메라 정렬이 불편하지 않은가 / 오른손으로 돌릴 때 카메라가 싸우지 않는가
  - 적이 없을 때 공격 휘두르기가 손에 붙는가
  - 전투 중 줍기 팝업이 뜨고 눌리는가
  - 패링·회피 판정 창 체감 (넓음/적당/좁음)
- [ ] **Step 2: 사용자 수행** — `git pull` → 실행 → 체크리스트 기입 → push.
- [ ] **Step 3: 판정** — 패링 성공률 30% 미만이면 판정 창을 넓혀 재측정, 성공해도 재미없다면 연타 보상(C5) 재설계 논의 후 M3 진행.
