# M3: 수호 기계 · 대검 · 활 · 내구도 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 테스트 섬에 수호 기계 2종(근접 칼날형·원거리 포격형)을 두고, 한손검·대검·활 3종을 바꿔 가며 싸우고, 무기가 닳고 부서지면 부품으로 수리하는 순환을 태블릿에서 체험한다. 핵심 질문: **"회피만으로 이길 수 있고, 패링이 확실히 이득인가? 무기를 상황에 따라 바꿔 쓰는가?"**

**Architecture:** M1·M2와 같다. 규칙은 노드 비의존 모델(`scripts/core/`, `RefCounted`/`Resource`)로 헤드리스 테스트하고, 노드(`scripts/nodes/`)는 감지·연출만. 무기·기계는 **데이터 리소스**(`WeaponData`, `MachineData` `.tres`)로 정의해 30종 이상 확장 시 파일 추가만으로 늘린다 (02 설계서 4.3).

**Tech Stack:** Godot 4.7.2, GDScript, Mobile 렌더러, 자체 테스트 러너(`./run_tests.sh`).

**Spec:** `docs/design/02-combat-design.md` (C3·C4·C7·C10·C16, 3.3 막기 표, 4장 무기, 5장 수호 기계, 6장 소수 정예), `docs/design/01-core-design.md` 8장 프로토타입 범위. 이 계획에서 새로 정한 사항은 Task 8에서 설계서에 C17~C20으로 기록한다.

## Global Constraints

- Godot 4.7.2, GDScript만, Mobile 렌더러, 텍스트 씬, 판정은 `_physics_process`(60 Hz)에서만.
- 오른손 버튼 3개(공격·방어·점프/회피) + 상호작용 팝업 유지. 새 버튼은 **무기 교체 1개**(오른쪽 위, 탭 = 다음 무기). 휠은 무기 확장(30종+) 때 — C17.
- 예고 신호 색: 🟡 = 패링 가능, 🔴 = 패링 불가. 모든 적·투사체 공통.
- 내구도: 맞혔을 때만 닳는다(허공 휘두르기 무료). 0 = **파손**(사라지지 않음, 피해 ×0.25). 수리 = 부품 1개로 장착 무기 완전 수리 — C4·C19.
- 활: 공격 버튼 **누르고 있기 = 당기기**(조준 확대·십자선·걷기만), **떼기 = 발사**. 짧게 탭해도 약한 화살이 나간다. 조준 = 화면 중앙(카메라 정면) — C18.
- 🟡 투사체를 패링하면 **되받아쳐** 쏜 기계에 피해 — C20.
- 화살 수는 무한 (인벤토리는 이후 마일스톤). 수영·무기 30종+은 이후.
- 튜닝 수치: 공통 = `resources/combat_tuning.tres`, 무기 = `resources/weapons/*.tres`, 기계 = `resources/machines/*.tres`.

## Review Focus

1. **파손 무기:** 내구도 0에서도 휘두르고 막을 수 있고(피해만 ×0.25), 수리하면 원래 피해로 돌아온다 → Task 1·3 테스트.
2. **활 짧은 탭:** 당김 0초여도 화살이 나가고 피해는 최소 비율(30%) → Task 2 테스트.
3. **당기는 중 무기 교체:** 교체하면 당김이 취소되고 화살이 나가지 않는다 → Task 2 테스트.
4. **기계 끝없는 추적:** 집에서 25m 넘게 끌려가면 경계를 풀고 돌아간다 → Task 6 테스트.
5. **투사체 이중 판정:** 회피로 흘린 투사체가 다음 틱에 다시 맞지 않고, 되받아친 투사체는 플레이어를 맞히지 않는다 → Task 5 테스트.

---

## File Structure

```
scripts/core/
  weapon_data.gd      # class_name WeaponData (Resource) — 무기 1종의 수치
  durability.gd       # class_name Durability — 내구도·파손·수리
  arsenal.gd          # class_name Arsenal — 소지 무기 목록·장착·교체
  hit.gd              # class_name Hit — 피해 1회 (장갑 관통·경직·약점)
  bow_draw.gd         # class_name BowDraw — 당기기/발사/취소, 당김 비율
  enemy_shot.gd       # class_name EnemyShot — 적 투사체 비행·판정·되받아치기
  machine_data.gd     # class_name MachineData (Resource) — 기계 1종의 수치
  machine_brain.gd    # class_name MachineBrain — 추적/공격/후퇴/귀환 결정
scripts/nodes/
  arrow.gd            # 플레이어 화살 (Node3D, 구간 레이캐스트)
  enemy_projectile.gd # 기계 탄 (Node3D, 그룹 "threat")
  machine.gd          # 수호 기계 (CharacterBody3D, 그룹 "enemy")
  repair_bench.gd     # 수리대 (그룹 "interactable")
resources/weapons/{sword,greatsword,bow}.tres
resources/machines/{blade,cannon}.tres
scenes/{arrow,enemy_projectile,machine_blade,machine_cannon,repair_bench}.tscn
docs/perf/m3-check.md
```
수정: `combat_tuning.gd/.tres`, `input_intent.gd`, `locomotion.gd`, `player_combat.gd`, `player.gd`, `player.tscn`, `orbit_camera.gd`, `touch_controls.gd`, `debug_hud.gd`, `training_dummy.gd`, `test_island.tscn`, `02-combat-design.md`, `01-core-design.md`.

**적 인터페이스 (덕 타이핑, 그룹 "enemy"):** `is_alive() -> bool`, `is_alerted() -> bool`, `is_threatening() -> bool`, `take_hit(hit: Hit) -> void`, `on_parried() -> void`, 선택: `core_point() -> Vector3`(약점 위치). M2의 `take_hit(amount)`·`stagger()`는 이것으로 바뀐다.

테스트 명령(모든 Task 공통): `./run_tests.sh` → 마지막 줄 `ALL PASSED (N tests)`.

---

### Task 1: 무기 데이터 · 내구도 · 무기고

**Files:** Create `scripts/core/weapon_data.gd`, `durability.gd`, `arsenal.gd`, `resources/weapons/sword.tres`, `greatsword.tres`, `bow.tres`, `tests/unit/test_arsenal.gd` · Modify `combat_tuning.gd`

**Interfaces:**
- Produces: `WeaponData extends Resource` — `enum Kind { MELEE, BOW }`, `@export`: `display_name: String, kind: Kind, damage: float, heavy_damage: float, light_cooldown: float, heavy_cooldown: float, reach: float, arc_deg: float, durability: float, armor_pierce: bool, heavy_staggers: bool, draw_time: float, min_draw_ratio: float, arrow_speed: float`.
  - sword: `"한손검", MELEE, 10, 25, 0.35, 0.7, 1.8, 120, 40, false, false`
  - greatsword: `"대검", MELEE, 22, 50, 0.8, 1.3, 2.4, 160, 30, true, true`
  - bow: `"활", BOW, damage=20, light_cooldown=0.3, durability=50, draw_time=0.6, min_draw_ratio=0.3, arrow_speed=45`
- Produces: `Durability extends RefCounted` — `_init(max_value: float)`, `var value: float`, `var max_value: float`, `wear(amount: float) -> void` (0 아래로 안 내려감), `is_broken() -> bool` (value ≤ 0), `repair() -> void` (최대치로).
- Produces: `Arsenal extends RefCounted` — `_init(weapons: Array[WeaponData])`, `current() -> WeaponData`, `durability() -> Durability`(장착 무기 것), `cycle() -> void`(다음 무기, 끝이면 처음), `index: int`. 무기마다 별도 Durability.
- Produces: `CombatTuning` 추가 `@export`: `broken_damage_mult=0.25, weak_point_mult=2.0, wear_hit=1.0, wear_block=3.0, wear_parry=1.0, hit_stagger_time=0.8, arrow_gravity=6.0, arrow_max_dist=80.0`. `attack_damage`·`heavy_damage`는 Task 3에서 제거.

- [ ] **Step 1: 실패 테스트** `tests/unit/test_arsenal.gd` — `test_wear_stops_at_zero_and_breaks` (max 3, wear 5 → value 0, broken), `test_repair_restores_full`, `test_cycle_wraps` (3종 → cycle 3번 → index 0), `test_each_weapon_has_own_durability` (wear 후 cycle → 새 무기 value = 최대), `test_weapon_tres_values` (greatsword.tres `armor_pierce` true, `durability` 30; bow.tres `kind == BOW`).
- [ ] **Step 2:** `./run_tests.sh` → 위 테스트 FAIL (클래스 없음).
- [ ] **Step 3:** 세 스크립트 + 세 `.tres` + CombatTuning 필드 구현.
- [ ] **Step 4:** `./run_tests.sh` → ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(m3): 무기 데이터·내구도·무기고`

### Task 2: 피해(Hit) · 활 당기기

**Files:** Create `scripts/core/hit.gd`, `bow_draw.gd`, `tests/unit/test_hit_bow.gd`

**Interfaces:**
- Produces: `Hit extends RefCounted` — 필드 `damage: float, armor_pierce: bool, stagger: bool, weak_point: bool`; `static func make(damage: float, armor_pierce := false, stagger := false) -> Hit`; `amount_against(armor: float, weak_point_mult: float) -> float` = damage × (1 if armor_pierce else armor) × (weak_point_mult if weak_point else 1).
- Produces: `BowDraw extends RefCounted` — `_init(weapon: WeaponData)`, `var drawing: bool`, `start()`, `tick(delta)`, `ratio() -> float` = lerp(min_draw_ratio, 1, clamp(t/draw_time)), `release() -> float` (발사 비율 반환, 당기는 중이 아니면 -1.0), `cancel()`.

- [ ] **Step 1: 실패 테스트** — `test_armor_reduces_unless_pierce` (Hit 20 vs armor 0.4 → 8; pierce → 20), `test_weak_point_doubles` (→ 40 with mult 2), `test_tap_release_fires_min_ratio` (start → release 즉시 → 0.3), `test_full_draw_ratio_one` (tick 0.6 → 1.0, tick 더 해도 1.0), `test_cancel_then_release_fires_nothing` (start, cancel, release → -1.0) — Review Focus 2·3.
- [ ] **Step 2:** FAIL 확인. **Step 3:** 구현. **Step 4:** ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(m3): 피해 계산·활 당기기 모델`

### Task 3: 플레이어 무기 연결 (근접 2종 + 교체 + 내구도)

**Files:** Modify `input_intent.gd`, `player_combat.gd`, `combat_tuning.gd/.tres`, `training_dummy.gd`, `touch_controls.gd`, `debug_hud.gd`, `player.gd`, `tests/unit/test_player_combat_reset.gd` · Create `tests/unit/test_player_weapons.gd`

**Interfaces:**
- Consumes: Task 1·2 전부.
- Produces: `InputIntent.attack_held: bool`, `InputIntent.switch_weapon_pressed: bool`, `InputIntent.aiming: bool`(Task 4가 채움).
- Produces: `PlayerCombat.arsenal: Arsenal` (setup에서 sword·greatsword·bow 순), `PlayerCombat.melee_hit(weapon: WeaponData, heavy: bool) -> Hit` (파손이면 ×broken_damage_mult, 대검 강공격이면 stagger=true), `PlayerCombat.switch_weapon()`(콤보·당기기 초기화).
- 근접: 공격 판정 거리·각도·쿨다운을 `WeaponData`에서. 적을 **맞혔을 때만** `wear_hit`, 무기 막기 `wear_block`, 무기 패링 `wear_parry`. 방패가 있으면 무기 내구도 소모 없음.
- 적 인터페이스 변경: `TrainingDummy.take_hit(hit: Hit)`(armor 1.0), `on_parried()`(기존 stagger). `hit.stagger`면 공격 취소 + `hit_stagger_time` 경직(슬로우 없음).
- 터치: 무기 버튼 `Vector2(s.x - 90, 90)`, 반지름 48, 라벨 = 장착 무기 이름. 키보드 `Q`. `touch_controls.set_weapon_label(name: String)`.
- HUD 한 줄 추가: `"%s %d/%d%s" % [이름, 내구도, 최대, " (파손)"]`.

- [ ] **Step 1: 실패 테스트** `test_player_weapons.gd` (`PlayerCombat.new()` + `setup(null)`, 노드 트리 없이):
  - `test_broken_weapon_deals_quarter` — durability.wear(999) → `melee_hit(sword, false).damage` = 2.5; `repair()` 후 10 (Review Focus 1)
  - `test_greatsword_heavy_staggers_and_pierces` — `melee_hit(greatsword, true)`: damage 50, stagger true, armor_pierce true
  - `test_switch_cycles_and_resets_combo` — `_combo_step = 2; switch_weapon()` → `arsenal.current().display_name == "대검"`, `_combo_step == 0`
- [ ] **Step 2:** FAIL. **Step 3:** 구현 (CombatTuning의 `attack_damage`·`heavy_damage` 제거, 쓰던 곳은 WeaponData로). **Step 4:** ALL PASSED + 에디터 실행 `godot --headless --quit-after 120 res://scenes/test_island.tscn` 에 SCRIPT ERROR 없음.
- [ ] **Step 5:** 커밋 `feat(m3): 대검·무기 교체·내구도 연결`

### Task 4: 활 (조준 · 화살)

**Files:** Create `scripts/nodes/arrow.gd`, `scenes/arrow.tscn` · Modify `player_combat.gd`, `player.gd`, `orbit_camera.gd`, `touch_controls.gd`, `locomotion.gd`, `tests/unit/test_locomotion_ground.gd`

**Interfaces:**
- Consumes: `BowDraw`, `Hit`, `Arsenal`.
- 활 장착 시 `attack_held` 시작 → `BowDraw.start()`, 떼는 순간(`attack_pressed` 또는 `heavy_released`) → `release()` 비율 r ≥ 0이면 발사: 피해 `damage × r`(파손이면 ×0.25), 속도 `arrow_speed × lerp(0.5, 1, r)`, 쿨다운 `light_cooldown`, 내구도 `wear_hit`은 **발사마다**.
- `Locomotion.wants_run`: `intent.aiming`이면 false (걷기만). `Player`가 locomotion.step 전에 `_intent.aiming = combat.is_drawing()`.
- 조준: `Player.aim_target() -> Vector3` = 카메라 중앙 레이 100m 충돌점(없으면 끝점). 화살 방향 = 가슴(+1.4m)에서 그 점으로.
- `OrbitCamera.set_aiming(on: bool)`: FOV 70→50, 0.15초 보간. `TouchControls.set_aiming(on)`: 화면 중앙 십자선.
- `Arrow`: 매 틱 `velocity.y -= arrow_gravity × delta`, 이전→다음 위치 구간 `intersect_ray`(지형 + 적). 적 맞으면 `weak_point = 적.has_method("core_point") and 충돌점.distance_to(core_point()) <= 0.45` 후 `take_hit(hit)`; 무엇이든 맞거나 `arrow_max_dist` 넘으면 사라짐.

- [ ] **Step 1: 실패 테스트** `test_aiming_walks_only` — move (0,1) 전력 + `aiming=true` → 수평 속도 = walk_speed, 스태미나 소모 없음.
- [ ] **Step 2:** FAIL. **Step 3:** 구현. **Step 4:** ALL PASSED + 헤드리스 탐침(`tests/_probe_bow.gd`, gitignore): 활 장착 → 0.6초 당김 → 발사 → 정면 15m 허수아비 HP 20 감소 확인.
- [ ] **Step 5:** 커밋 `feat(m3): 활 조준·화살`

### Task 5: 적 투사체 모델

**Files:** Create `scripts/core/enemy_shot.gd`, `tests/unit/test_enemy_shot.gd`

**Interfaces:**
- Produces: `EnemyShot extends RefCounted` — `_init(from: Vector3, to: Vector3, speed: float, parryable: bool)`, 필드 `position, velocity, parryable, reflected := false, resolved := false, travelled := 0.0`; `step(delta) -> Vector3`(이전 위치 반환), `crosses(prev: Vector3, point: Vector3, radius: float) -> bool`(선분–점 거리), `is_threat_to(point: Vector3, range: float) -> bool`(되받아치지 않았고, 미판정이고, 거리 ≤ range이고, 다가오는 중), `reflect(toward: Vector3)`(방향 전환, 속도 ×1.5, reflected = true), `expired(max_dist: float) -> bool`.

- [ ] **Step 1: 실패 테스트** — `test_flies_toward_target`, `test_crosses_detects_pass_through`(한 틱에 점을 지나쳐도 true), `test_threat_only_when_close_and_approaching`(지나간 뒤 false), `test_reflected_is_not_threat`, `test_resolved_is_not_threat`(Review Focus 5).
- [ ] **Step 2:** FAIL. **Step 3:** 구현. **Step 4:** ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(m3): 적 투사체 모델`

### Task 6: 기계 데이터 · 판단 모델

**Files:** Create `scripts/core/machine_data.gd`, `machine_brain.gd`, `resources/machines/blade.tres`, `cannon.tres`, `tests/unit/test_machine_brain.gd`

**Interfaces:**
- Produces: `MachineData extends Resource` — `@export`: `display_name, ranged: bool, max_hp, armor, move_speed, alert_range, attack_range, keep_min, leash, damage, attack_interval, telegraph, active, recover, red_every: int, shot_speed, red_shot_speed, part_drop: int, respawn_time`.
  - blade: `"칼날형", false, 120, 0.4, 3.5, 15, 2.2, 0, 25, 20, 1.4, 0.6, 0.2, 0.9, 3, -, -, 1, 30`
  - cannon: `"포격형", true, 70, 1.0, 2.5, 22, 20, 8, 25, 15, 2.5, 1.0, 0.1, 0.8, 3, 14, 20, 1, 30`
- Produces: `MachineBrain extends RefCounted` — `enum Mode { IDLE, CHASE, ATTACK, RETREAT, RETURN }`, `_init(data: MachineData)`, `var alerted: bool`, `decide(dist_player: float, dist_home: float, hit_this_tick: bool) -> Mode`:
  - `hit_this_tick` 또는 dist_player ≤ alert_range → alerted = true; dist_home > leash → alerted = false 후 RETURN; alerted 아니고 dist_home > 1 → RETURN; 아니면 IDLE.
  - 근접: dist_player ≤ attack_range → ATTACK, 아니면 CHASE.
  - 원거리: dist_player < keep_min → RETREAT, > attack_range → CHASE, 아니면 ATTACK.
  - `is_red(count: int) -> bool` = count % red_every == 0.

- [ ] **Step 1: 실패 테스트** — `test_idle_until_alert`, `test_blade_chases_then_attacks`, `test_cannon_keeps_distance`(5m RETREAT, 12m ATTACK, 25m CHASE), `test_leash_drops_alert_and_returns`(dist_home 26 → RETURN, alerted false — Review Focus 4), `test_hit_alerts_from_far`, `test_every_third_attack_red`.
- [ ] **Step 2:** FAIL. **Step 3:** 구현. **Step 4:** ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(m3): 수호 기계 데이터·판단 모델`

### Task 7: 수호 기계 노드 + 투사체 + 섬 배치

**Files:** Create `scripts/nodes/machine.gd`, `enemy_projectile.gd`, `scenes/machine_blade.tscn`, `machine_cannon.tscn`, `enemy_projectile.tscn` · Modify `player.gd`, `player_combat.gd`, `test_island.tscn`

**Interfaces:**
- Consumes: `MachineData`, `MachineBrain`, `EnemyAttack`, `Flurry`, `Hit`, `EnemyShot`.
- `Machine extends CharacterBody3D` — `@export var data: MachineData`, 적 인터페이스 전부 + `core_point()`. 집 = 시작 위치. 중력 적용, `Mode`대로 이동(RETREAT = 반대 방향, RETURN = 집으로, 도착하면 HP 회복). 공격: 근접은 TrainingDummy와 같은 판정(`_in_reach`), 원거리는 `hit` 이벤트 순간 `enemy_projectile.tscn` 생성(🔴면 `red_shot_speed`). 패링당하면(`on_parried`) 공격 취소 + 1초 경직 + 개체 슬로우. `hit.stagger`면 `hit_stagger_time` 경직. 피해 = `hit.amount_against(data.armor, weak_point_mult)`. 사망 → `pickup_part.tscn` `part_drop`개 생성, `respawn_time` 뒤 집에서 부활.
- 외형(프리미티브): 칼날형 = 상자 몸체 1.2×1.0×1.6 + 등 위 시안 발광 구(코어, 반지름 0.3) + 앞쪽 칼날 상자; 포격형 = 원기둥 몸체(높이 2.2) + 앞쪽 포신 + 상단 앞 코어. 예고 신호 = 눈(Eye) 메시 발광(🟡/🔴), HP Label3D.
- `EnemyProjectile` (Node3D, 그룹 `"threat"`): `EnemyShot`으로 비행, 지형 구간 레이캐스트로 소멸. 플레이어 구간 통과(반지름 0.7) 시 한 번만 `player.combat.on_enemy_hit(parryable, self, damage)`. 되받아친 탄은 쏜 기계 반지름 1.0 통과 시 `take_hit(Hit.make(damage × 2))`. `is_threatening()` = `shot.is_threat_to(player, THREAT_RANGE)`.
- `PlayerCombat.on_enemy_hit(parryable: bool, source: Node3D, damage: float)` 로 시그니처 변경(첫 인자 EnemyAttack → bool), 패링 시 `source.on_parried()`. `TrainingDummy`의 호출도 `on_enemy_hit(attack.parryable, self, damage)`로 바꾼다. 투사체의 `on_parried()` = `reflect(쏜 기계 위치)`. 회피/피격/막기 후 `shot.resolved = true`.
- `Player._update_combat_context`: 그룹 `"threat"`도 위협으로 센다.
- 섬 배치: 칼날형 `(-25, 0, 10)`, 포격형 `(25, 0, 5)` (시작 지점 (0,1,60)에서 약 50m 앞 양옆).

- [ ] **Step 1:** 구현 (노드는 단위 테스트 대신 탐침 검증).
- [ ] **Step 2:** `./run_tests.sh` ALL PASSED.
- [ ] **Step 3:** 헤드리스 탐침 `tests/_probe_machines.gd`: (a) 칼날형 앞 10m에 플레이어 → 3초 안에 2.2m까지 접근·공격 시작, (b) 플레이어를 칼날형 집에서 40m로 순간이동 → 경계 해제·귀환, (c) 포격형 12m → 탄 생성, 플레이어가 막기 없이 맞으면 HP 15 감소, (d) 🟡 탄 도착 0.1초 전 방어 누름 → "패링!" 후 포격형 HP 30 감소, (e) 칼날형 처치 → 부품 1개 생성.
- [ ] **Step 4:** 커밋 `feat(m3): 수호 기계 2종·투사체·섬 배치`

### Task 8: 수리대 + 문서

**Files:** Create `scripts/nodes/repair_bench.gd`, `scenes/repair_bench.tscn`, `docs/perf/m3-check.md` · Modify `test_island.tscn`, `docs/design/02-combat-design.md`, `docs/design/01-core-design.md`

**Interfaces:**
- `RepairBench` (Node3D, 그룹 `"interactable"`): `prompt()` = 부품 있으면 `"수리: <무기> (부품 1)"`, 장착 무기가 멀쩡하면 `"수리: <무기> (최대)"`, 부품 0이면 `"수리: 부품 부족"`. `interact(player)`: 부품 ≥ 1이고 내구도 < 최대면 parts −1, `repair()`. 섬 위치 `(6, 0, 58)`.
- 설계서 02: C3 목표 "30종+ (추후 확장)", C17 무기 교체(버튼 순환 → 확장 시 휠), C18 활 조작, C19 수리 규칙(M3 = 수리대, 이후 마을 대장장이), C20 투사체 되받아치기. 4.1 표 순서 유지. 01 설계서 8장 제외 칸에 "수영 (M3 이후, 물 지형과 함께)".
- `m3-check.md`: 조작·기계 설명 + 체크리스트(회피만으로 칼날형 처치 가능? / 패링이 확실히 이득? / 대검 경직 체감 / 활 조준·당김 / 포격형 탄 되받아치기 / 내구도 소모 속도 / 무기 교체 버튼 위치) + 판정 기준.

- [ ] **Step 1:** 구현 + 문서. **Step 2:** `./run_tests.sh` ALL PASSED, 탐침: 부품 1 + 파손 대검 → 수리 → 30/30, 부품 0.
- [ ] **Step 3:** 커밋 `feat(m3): 수리대·설계서 갱신·확인 양식`

### Task 9: 태블릿 확인 (사용자 수행)

- [ ] `git pull` → `docs/perf/m3-check.md` 체크리스트 기록.
- [ ] 판정: 회피만으로 못 이기면 기계 수치 조정, 패링 이득이 약하면 슬로우·피해 배율 논의, 그 외 → M4 (마을·적응 퀘스트 또는 탑).
