# Forward+ 확정 · 지형 등반 개선 · 누르는 동안 활공 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 태블릿 실측(Forward+ 평균 48~78 FPS)으로 렌더러를 Forward+로 확정하고, 첫 섬에서 "일부 지형을 오르기 어렵다"는 문제를 원인부터 찾아 고치며, 활공을 토글에서 **점프 버튼을 누르고 있는 동안만** 펼치는 방식으로 바꾼다.

**Architecture:** 이동 규칙은 `Locomotion`(노드 비의존 모델)에서 헤드리스 테스트로 고정하고, 지형 등반 문제는 첫 섬 전체의 가파른 지형을 자동으로 훑는 탐침으로 실패 지점을 수치화한 뒤 원인을 고친다(추측 수정 금지).

**Tech Stack:** Godot 4.7.2, GDScript, **Forward+ 렌더러**, 자체 테스트 러너(`./run_tests.sh`).

**Spec:** 사용자 요청(2026-10-11) + `docs/design/01-core-design.md` 기둥 1("보이면 갈 수 있다"), `docs/superpowers/specs/2026-10-10-m4-first-island-design.md` 5.4(60° 걷기/등반 경계).

## Global Constraints

- 렌더러: **Forward+** (태블릿·데스크톱 모두). 태블릿 실측 평균 48~78 FPS — 기준 하한 45.
- 걷기 한계 60°, 그보다 가파르면 등반 (기존 규칙 유지).
- 활공: **공중에서 점프 버튼을 누르고 있는 동안만** 활공, 떼면 즉시 접힘. 활공 속도·하강·스태미나 소모(8/s)는 기존 값.
- 판정은 `_physics_process`(60 Hz), 수치는 `resources/movement_tuning.tres`.

## Review Focus

1. **땅에서 점프 버튼을 계속 누르고 있음:** 정점을 지나 떨어지기 시작하면 활공이 펼쳐진다 — 의도된 동작인지 테스트로 고정 → Task 2.
2. **벽 점프(등반 중 점프) 후 버튼 유지:** 다시 벽에 닿으면 활공보다 재등반이 우선 → Task 2 테스트.
3. **활공 중 탈진:** 접히고, 버튼을 계속 누르고 있어도 스태미나가 회복 기준(30%)을 넘기 전에는 다시 펼치지 않는다 → Task 2 테스트.
4. **회피 문맥:** 적이 공격 중일 때 땅에서 스틱+점프는 여전히 회피, 공중 활공과 섞이지 않는다 → Task 2 테스트.
5. **지형 등반 수정이 상자 벽(테스트 섬 절벽·탑·바위벽) 등반을 깨지 않는다** → Task 3 탐침에서 기존 경로 탐침 재실행.

---

### Task 1: Forward+ 확정 기록

**Files:** Modify `docs/design/01-core-design.md`(10.2 렌더링 결정, 10.3 성능 목표), `docs/design/03-art-direction.md`(1.1 개정 예정 → 렌더러 확정), `docs/perf/forward-plus-test.md`(측정값 기록)

- [ ] **Step 1:** 01 설계서 10.2 "Mobile 렌더러" 결정을 "**Forward+** (2026-10-11 태블릿 실측 평균 48~78 FPS)"로 개정. 사용 가능 효과: SSAO·SSIL·볼류메트릭 안개·글로우·반사 프로브·라이트맵. 10.3 목표는 60 FPS 목표 / 45 하한으로.
- [ ] **Step 2:** `forward-plus-test.md`에 측정 범위(48~78) 기록, 판정 "채택".
- [ ] **Step 3:** 커밋 `docs: Forward+ 렌더러 확정 (태블릿 48~78 FPS)`

### Task 2: 누르는 동안 활공

**Files:** Modify `scripts/core/locomotion.gd`(`_step_airborne`, `_step_gliding`), `tests/unit/test_locomotion_climb_glide.gd`, `docs/design/02-combat-design.md`(2장 조작표 점프/회피 행), `docs/perf/m4a-check.md`

**Interfaces:**
- Consumes: 기존 `InputIntent.jump_held`(터치 점프 버튼·스페이스 키를 누르고 있음 — 이미 채워짐).
- 규칙: AIRBORNE에서 `jump_held` and `velocity.y < 0` and `_stamina.can_start()` → GLIDING (벽 재등반 판정 `_try_start_climb`이 먼저). GLIDING에서 `not jump_held` → AIRBORNE. 착지·스태미나 0 처리는 기존 그대로.

- [ ] **Step 1: 실패 테스트** (`test_locomotion_climb_glide.gd`, 기존 토글 테스트 `test_jump_while_falling_opens_glider`는 아래로 대체):
  - `test_holding_jump_while_falling_glides` — AIRBORNE, vy −1, `jump_held` true(pressed false) → GLIDING
  - `test_releasing_jump_closes_glider` — GLIDING 상태에서 `jump_held` false → AIRBORNE
  - `test_tap_jump_in_air_does_not_toggle` — GLIDING에서 `jump_pressed` true + `jump_held` true → GLIDING 유지 (탭이 접지 않음)
  - `test_held_from_ground_jump_glides_after_apex` — 땅 점프 후 `jump_held` 유지 → 상승 중(vy > 0)엔 AIRBORNE, 하강 시작 틱부터 GLIDING (Review Focus 1)
  - `test_wall_regrab_beats_glide` — 벽 점프 후 `jump_held` 유지, 하강 중 벽 감지 + 스틱 위 → CLIMBING (Review Focus 2)
  - `test_exhausted_glider_does_not_reopen_while_held` — 활공 중 스태미나 0 → AIRBORNE, `jump_held` 유지하며 0.5초 → AIRBORNE 유지 (Review Focus 3)
  - `test_threatened_ground_jump_still_dodges` — 기존 회피 테스트가 그대로 통과하는지 확인 (Review Focus 4, 새 테스트 불필요 — 기존 `test_threatened_jump_with_stick_dodges` 실행으로 확인)
- [ ] **Step 2:** `./run_tests.sh` → 위 테스트 FAIL.
- [ ] **Step 3:** 구현. 설계서 02 조작표: "공중에서 활공" → "**공중에서 누르고 있는 동안 활공** (떼면 접힘)". m4a 확인 양식 조작 설명 갱신.
- [ ] **Step 4:** ALL PASSED + 탐침: 첫 섬 협곡 활공 경로(`tests/_probe_routes.gd` (b))를 "누르고 유지 → 고원 위에서 뗌"으로 바꿔 착지 확인.
- [ ] **Step 5:** 커밋 `feat: 활공을 누르고 있는 동안만 (토글 폐지)`

### Task 3: 지형 등반 문제 — 원인 찾기 · 고치기

**Files:** Create `tests/_probe_climb_sweep.gd`(gitignore, 탐침) · Modify (원인에 따라) `scripts/nodes/player.gd`(`_sense`), `scripts/core/locomotion.gd`, `scenes/player.tscn`(레이) 중 해당 파일 · Test: `tests/unit/test_locomotion_climb_glide.gd`

- [ ] **Step 1: 재현 (systematic-debugging):** 탐침이 첫 섬의 가파른 지형 칸(`HeightField.normal_at().y < 0.51`)을 격자 4m 간격으로 표본 추출(최대 200곳) → 각 지점에서 경사 아래 1.5m에 플레이어를 놓고 경사 쪽으로 스틱을 6초간 민다(스태미나 가득). 기록: ① 등반 시작 실패(GROUNDED로 멈춤) ② 시작했으나 3m 못 오르고 떨어짐 ③ 상태가 1초에 3번 이상 CLIMBING↔AIRBORNE로 깜빡임 ④ 성공(꼭대기 도달 또는 3m 이상 상승). 결과를 경사 각도·위치별 표로 출력.
- [ ] **Step 2: 원인 판정:** 실패 지점에서 매 틱 `wall_ray` 충돌 여부·법선, `is_on_wall`/`get_wall_normal`, `ledge_top`, 속도를 기록해 실패 유형별 원인을 하나로 특정한다. 후보(검증 전 가설): (a) 2m 격자 삼각형마다 법선이 달라 `wall_normal`이 틱마다 바뀜/사라짐, (b) 가슴 레이(0.9m, 길이 1m)가 경사면에 닿지 않음, (c) 경사 위쪽에서 `ledge_top`(머리 레이 미충돌)이 너무 일찍 참이 되어 올라서기 도약이 실패, (d) 60°~70° 경사에서 벽 붙이기 속도가 면을 밀어내 접촉이 끊김. Ruling에 실측 근거와 함께 기록.
- [ ] **Step 3: 실패 테스트:** 특정된 원인을 재현하는 `Locomotion` 단위 테스트(예: 틱마다 법선이 조금씩 다른 sense 열을 넣어도 CLIMBING 유지) 또는 탐침 실패를 RED로 확인.
- [ ] **Step 4: 수정:** 원인에 맞는 최소 수정. (예: 지형에 맞은 경우 충돌 법선 대신 `HeightField.normal_at`(부드러운 법선) 사용, 레이 길이·각도 조정, 짧은 접촉 끊김 허용 시간(코요테 타임) 등 — 실측으로 고른 하나.)
- [ ] **Step 5:** ALL PASSED + 스윕 탐침 재실행: 성공률 **95% 이상**, 깜빡임 0. 기존 탐침(`_probe_routes`, `_probe_tower`, `_probe_lake`, 테스트 섬 `_probe_swim`) 재실행 통과 (Review Focus 5).
- [ ] **Step 6:** 커밋 `fix: 지형 경사 등반 안정화 (<원인>)`

### Task 4: 태블릿 확인 (사용자 수행)

- [ ] `git pull` → 활공(누르고 유지/떼기)과, 오르기 어려웠던 지형을 다시 시도. 어려웠던 위치가 남아 있으면 대략의 장소(예: "둑 안쪽 벽", "산 북쪽")를 알려준다.
- [ ] 그 뒤: 그래픽 설계서 03 개정(Forward+ 기준, 두 데모 방식) → 그래픽 개편 계획.
