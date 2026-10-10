# M4a: '첫 섬' 세계 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 높이 지도 지형으로 만든 새 '첫 섬'에서, 수문 3곳을 열어 저수호 수위를 낮추고, 탑을 올라 코어를 멈추면 섬이 회색에서 컬러로 번지고 기계가 멈추는 세계 루프를 태블릿에서 체험한다. (마을·대화·저장은 M4b)

**Architecture:** M1~M3과 같다. 규칙(높이 샘플링·지형 메시·수위·진행 상태·등반 판정)은 노드 비의존 모델로 헤드리스 테스트하고, 노드는 배치·연출만. 지형은 흑백 PNG(`assets/terrain/first_island.png`)를 시작 시 읽어 메시·충돌을 만든다. 회색↔컬러는 공용 셰이더 + 전역 셰이더 변수 `vitality_center`/`vitality_radius`.

**Tech Stack:** Godot 4.7.2, GDScript, Mobile 렌더러, 자체 테스트 러너(`./run_tests.sh`).

**Spec:** `docs/superpowers/specs/2026-10-10-m4-first-island-design.md` (1·4·5·6·7장, M4a 범위), `docs/design/03-art-direction.md` (3·4·5·7장)

## Global Constraints

- Godot 4.7.2, GDScript만, Mobile 렌더러, 텍스트 씬, 판정은 `_physics_process`(60 Hz).
- 섬 300m × 300m, 북쪽 = −Z. 높이 지도 높이 범위 **−10 ~ 60m**, 메시 격자 **2m**.
- 바다 수면 y = **0** (첫 섬 기준). 저수호 초기 수면 **6.6**, 수문 1개당 **−1.2m**, 둑길 윗면 **3.2** (수문 3개 → 수면 3.0, 둑길 드러남).
- 탑 높이 **60m**, 쉼터 **20m·40m**, 꼭대기 코어 = 상호작용 「정지」.
- 정지 시 회복 반경 **0 → 220m**를 **6초**에 확장, 경계 폭 **10m**.
- 잿빛 = 채도 약 **15%** + 약간 푸른 기. 고채도 예외: 생명력 빛, 🟡/🔴 신호, 코어 청록 — 셰이더 회색 처리 제외.
- 성능 예산: 화면당 삼각형 약 30만 이하, 그림자 빛 1개, 입자 2,000개 이하.
- 테스트 섬(`test_island.tscn`)은 그대로 유지. 메인 씬만 `first_island.tscn`으로.

## Review Focus

1. **사용자가 다시 그린 높이 지도:** 크기가 다르거나(512×512 등) 컬러(RGB)로 저장한 PNG도 그대로 읽혀야 한다 → Task 1 테스트.
2. **같은 수문 두 번 열기:** 수위가 두 번 내려가면 안 된다 → Task 4 테스트.
3. **탑 정지 후 수문 열기 / 정지 두 번:** 정지 순간 값(`outcome_at_stop`)은 바뀌지 않는다 → Task 4 테스트.
4. **수위가 내려가는 동안 둑길·물속의 플레이어:** 헤엄→걷기로 자연스럽게 바뀌고 갇히지 않는다 → Task 4 탐침.
5. **경사 45~72° 지형:** 걷지도 오르지도 못하는 미끄럼 구간 없이 오를 수 있다 → Task 1 테스트 + Task 6 탐침.

---

## File Structure

```
scripts/core/
  height_field.gd     # class_name HeightField — 이미지 → 높이·법선 샘플링
  terrain_mesh.gd     # class_name TerrainMesh — HeightField → ArrayMesh(면 법선·정점 색) + 높이 배열
  lake_level.gd       # class_name LakeLevel — 열린 수문 수 → 수위
  world_state.gd      # class_name WorldState — 수문·탑 진행 상태, 직렬화
scripts/nodes/
  terrain.gd          # Terrain (StaticBody3D) — PNG 읽어 메시·HeightMapShape3D 생성
  lake.gd             # Lake (Water 상속) — 목표 수위로 천천히 이동, 수면 메시
  sluice.gd           # Sluice — 상호작용 「수문 열기」
  tower_core.gd       # TowerCore — 상호작용 「정지」, 회복 연출
  first_island.gd     # FirstIsland (씬 루트, 그룹 "world") — WorldState 보유, 수문·탑 이벤트 처리
shaders/vitality.gdshader   # 공용 회색↔컬러 셰이더
tools/gen_first_island.gd   # 높이 지도 PNG 생성 (일회 실행, 결과 커밋)
assets/terrain/first_island.png
scenes/first_island.tscn, scenes/sluice.tscn, scenes/tower.tscn
docs/perf/m4a-check.md
```
수정: `player.gd`(등반 판정), `locomotion.gd`(`is_climbable`), `machine.gd`(`deactivate`), `debug_hud.gd`, `project.godot`(메인 씬·전역 셰이더 변수), `water.gd`(필요 시 크기 변경 지원).

테스트 명령(모든 Task 공통): `./run_tests.sh` → 마지막 줄 `ALL PASSED (N tests)`. 탐침은 `tests/_*.gd`(gitignore), `godot --headless -s tests/_x.gd` (노드는 첫 물리 틱 이후 준비됨; PROCESS_MODE_DISABLED 물리체는 충돌에서 빠지므로 탐침에서 쓰지 말 것).

---

### Task 1: 높이 샘플링 · 지형 메시 · 등반 판정

**Files:** Create `scripts/core/height_field.gd`, `scripts/core/terrain_mesh.gd`, `tests/unit/test_terrain.gd` · Modify `scripts/core/locomotion.gd`, `scripts/nodes/player.gd:100`

**Interfaces:**
- Produces: `HeightField extends RefCounted` — `_init(image: Image, world_size: float, min_h: float, max_h: float)`; `height_at(x: float, z: float) -> float` (월드 좌표, 섬 중심 = 원점, 범위 밖은 가장자리로 클램프, 쌍선형, 픽셀 값은 `get_pixel().r` — RGB든 L8이든 빨강 채널 = 밝기); `normal_at(x, z) -> Vector3` (중앙 차분, 정규화).
- Produces: `TerrainMesh` — `static build(field: HeightField, cell: float, color_fn: Callable) -> ArrayMesh` (격자 `world_size / cell + 1` 정점², 면 법선(로우폴리 평면 셰이딩), `color_fn(height: float, normal: Vector3) -> Color` 정점 색); `static heights(field: HeightField, cell: float) -> PackedFloat32Array` (HeightMapShape3D용, 행 = z).
- Produces: `Locomotion.is_climbable(normal: Vector3) -> bool` (static) = `normal.y < 0.7 and normal.y > -0.3` (45° 이상 경사·수직 벽·약한 오버행).

- [ ] **Step 1: 실패 테스트** `tests/unit/test_terrain.gd` (이미지는 코드로 생성):
  - `test_height_corners_and_center` — 3×3 L8 이미지(좌상 0, 중앙 255) world 10, −10~60 → `height_at(-5,-5)` = −10, `height_at(0,0)` = 60
  - `test_bilinear_between_pixels` — 2×1 이미지(0, 255), world 10 → `height_at(0, 0)` ≈ 25
  - `test_outside_clamps_to_edge` — `height_at(999, 0) == height_at(5, 0)`
  - `test_rgb_and_other_size_images_work` — 5×5 RGB8 이미지 전부 (1,0,0) → 모든 점 60 (Review Focus 1)
  - `test_flat_normal_is_up` — 균일 이미지 → `normal_at` ≈ UP
  - `test_mesh_triangle_count` — world 4, cell 2 → 3×3 정점 격자 → 삼각형 8개 (`mesh.surface_get_array_len` 또는 인덱스 수 24)
  - `test_heights_array_size` — world 4, cell 2 → 9개
  - `test_climbable_slopes` — 50° 경사 법선(n.y = cos50° ≈ 0.643) true, 40° (0.766) false, 수직 (0) true, 천장 (−1) false (Review Focus 5)
- [ ] **Step 2:** `./run_tests.sh` → FAIL (클래스 없음).
- [ ] **Step 3:** 구현. `player.gd`의 `absf(n.y) < 0.3` → `Locomotion.is_climbable(n)`.
- [ ] **Step 4:** ALL PASSED (기존 등반 테스트 포함 — 테스트 섬 절벽은 수직이므로 영향 없음).
- [ ] **Step 5:** 커밋 `feat(m4a): 높이 지도 샘플링·지형 메시·45° 등반 판정`

### Task 2: 첫 섬 높이 지도

**Files:** Create `tools/gen_first_island.gd`, `assets/terrain/first_island.png`, `tests/unit/test_first_island_map.gd`

**Interfaces:**
- Consumes: `HeightField`.
- `tools/gen_first_island.gd` (extends SceneTree): 256×256 L8 PNG 생성. 높이 = 아래 지형 요소의 합성(값은 m, 섬 좌표):
  - 섬 바깥(중심에서 140m 밖) → −10 (바다 밑), 해안 130~140m는 0~2로 경사.
  - 기본 평지 8.
  - 마을 저지대: (0, 95) 중심 반경 35m → 3.
  - 저수호 분지: (0, −10) 중심 반경 45m → 바닥 0.5, 가장자리 45~52m에서 8로 상승.
  - 탑 섬: (0, −10) 반경 8m → 8 (분지 위로 솟음).
  - 북쪽 산: (0, −120) 가우스 봉우리 최고 58 (반경 약 40m).
  - 서쪽 능선(활공 출발): (−70, −30) 높이 35 · 협곡: x −95 ± 8m 를 따라 z −80 ~ 40 깊이 2 · 서쪽 고원: (−125, −20) 높이 20.
  - 남쪽 해변: z 120~140 구간 0~2.
- PNG 값 = `round((h + 10) / 70 × 255)`.

- [ ] **Step 1: 실패 테스트** `test_first_island_map.gd` (`HeightField.new(load PNG Image, 300, -10, 60)`):
  - `test_village_lowland` — `height_at(0, 95)` 2~4
  - `test_lake_basin_below_causeway` — `height_at(0, -40)` < 2 (둑길 자리 아래 분지)
  - `test_tower_islet_above_lake` — `height_at(0, -10)` > 7
  - `test_mountain_peak` — `height_at(0, -120)` > 50
  - `test_canyon_and_plateau` — `height_at(-95, -20)` < 4, `height_at(-70, -30)` > 30, `height_at(-125, -20)` 17~23
  - `test_sea_outside` — `height_at(149, 149)` < 0
- [ ] **Step 2:** FAIL (PNG 없음).
- [ ] **Step 3:** 생성기 작성 → `godot --headless -s tools/gen_first_island.gd` → `godot --headless --import`. PNG 가져오기 설정은 **무손실(Lossless)** (VRAM 압축이면 `get_image()` 값이 변함). 테스트·Terrain 모두 `(load("res://assets/terrain/first_island.png") as Texture2D).get_image()`로 읽는다 (Android 에디터에서도 동작하는 경로).
- [ ] **Step 4:** ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(m4a): 첫 섬 높이 지도 생성기·PNG`

### Task 3: 회복 셰이더 · 지형 노드 · 첫 섬 씬

**Files:** Create `shaders/vitality.gdshader`, `scripts/nodes/terrain.gd`, `scenes/first_island.tscn`, `scripts/nodes/first_island.gd`(골격) · Modify `project.godot`

**Interfaces:**
- Consumes: `HeightField`, `TerrainMesh`, 기존 `Water`, `player.tscn`, `touch_controls.tscn`, `debug_hud.gd`.
- `project.godot`: `run/main_scene="res://scenes/first_island.tscn"`, `[shader_globals]` `vitality_center` (vec3, (0,0,−10)), `vitality_radius` (float, 0.0).
- `shaders/vitality.gdshader` (spatial): `global uniform vec3 vitality_center; global uniform float vitality_radius;` uniform `albedo: vec4`, `use_vertex_color: bool`, `keep_color: bool`. 색 = 정점 색 또는 albedo. 잿빛 판 = 휘도로 채도 15% + 푸른 기 (`mix(vec3(lum), color, 0.15) * vec3(0.95, 0.98, 1.05)`). `t = smoothstep(radius, radius - 10, distance(world_pos.xz, center.xz))` → `mix(grey, color, keep_color ? 1 : t)`. roughness 1.
- `Terrain extends StaticBody3D` — `@export var height_map: Texture2D`, `world_size := 300.0`, `min_h := -10.0`, `max_h := 60.0`, `cell := 2.0`. `_ready`: HeightField → `TerrainMesh.build` (색 함수: 높이 < 2 모래 `#D8C79A`, 경사 법선 y < 0.7 바위 `#C49A6C`, 그 외 풀 `#7FB45A`) → MeshInstance3D(vitality 재질, use_vertex_color) + CollisionShape3D(HeightMapShape3D, `scale = (cell, 1, cell)`).
- `first_island.tscn`: WorldEnvironment(하늘·거리 안개·높이 안개, 03 설계서 5장), Sun(그림자), Terrain, 바다 `Water`(수면 y 0, 2000×40×2000) + 바다 평면 메시, Player(스폰 (0, 4, 100) — 마을 광장), UI(TouchControls, DebugHud). 루트 스크립트 `FirstIsland`(그룹 "world").

- [ ] **Step 1:** 구현.
- [ ] **Step 2:** `./run_tests.sh` ALL PASSED.
- [ ] **Step 3:** 탐침 `tests/_probe_island.gd`: 메인 씬 로드 → 60틱 후 플레이어 `is_on_floor()` true, y 2~5 (마을 지면 위), 지형 생성 시간 출력(ms), `RenderingServer.global_shader_parameter_get("vitality_radius") == 0.0`.
- [ ] **Step 4:** 커밋 `feat(m4a): 회복 셰이더·높이 지도 지형·첫 섬 씬`

### Task 4: 진행 상태 · 저수호 · 수문

**Files:** Create `scripts/core/world_state.gd`, `scripts/core/lake_level.gd`, `scripts/nodes/lake.gd`, `scripts/nodes/sluice.gd`, `scenes/sluice.tscn`, `tests/unit/test_world_state.gd` · Modify `scripts/nodes/first_island.gd`, `scenes/first_island.tscn`, `scripts/nodes/debug_hud.gd`

**Interfaces:**
- Produces: `WorldState extends RefCounted` — `var sluices: Array[bool] = [false, false, false]`, `var tower_stopped := false`, `var outcome_at_stop := -1`, `var departed: Array[StringName] = []`; `open_sluice(i: int) -> bool` (새로 열었으면 true, 이미 열림·범위 밖 false), `open_count() -> int`, `stop_tower() -> bool` (처음이면 true, `outcome_at_stop = open_count()`), `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> WorldState` (잘못된 값은 기본값).
- Produces: `LakeLevel` — `static level(base_y: float, open_count: int, drop := 1.2) -> float` (open_count 0~3으로 클램프).
- Produces: `Lake extends Water` — `@export var base_level := 6.6`, `@export var move_speed := 0.4` (m/s), `set_target(y: float)`, 수면 메시를 현재 수위로 이동. `depth_at`은 현재 수위 기준.
- Produces: `Sluice` (Node3D, 그룹 "interactable") — `@export var index: int`, `prompt()` = `"수문 열기"` / 열린 뒤 `"수문 (열림)"`, `interact(player)` → `get_tree().get_first_node_in_group("world").open_sluice(index)`. 열리면 문짝 메시가 올라감.
- Produces: `FirstIsland.state: WorldState`, `FirstIsland.open_sluice(i: int) -> void` (state 갱신 → `lake.set_target(LakeLevel.level(lake.base_level, state.open_count()))` → 수로 물 표시 갱신).
- 배치: 저수호 = Lake (중심 (0, ?, −10), 수평 100×100, 바닥 y 0), 둑길 = 상자 StaticBody (남쪽 기슭 (0, 3.2 윗면, 35) → 탑 섬 (0, −2)), 수문 3개 = 수문1 (−20, 산 중턱, −100) · 수문2 (−125, 20, −20) · 수문3 (95, 8, 60) — Task 6에서 지형 맞춰 높이 보정. 고대 수로 = 북쪽→마을 상자 수로 + 물 띠 메시(열린 수문 ≥ 1이면 보임).
- HUD: `"수문 %d/3 · 탑 %s"`.

- [ ] **Step 1: 실패 테스트** `test_world_state.gd`:
  - `test_open_sluice_once` — `open_sluice(1)` true, 다시 false, `open_count() == 1` (Review Focus 2)
  - `test_out_of_range_ignored` — `open_sluice(5)` false
  - `test_stop_records_outcome_once` — 2개 열고 stop → `outcome_at_stop == 2`; 1개 더 열고 다시 stop → false, 여전히 2 (Review Focus 3)
  - `test_round_trip` — 상태 → `to_dict` → `from_dict` 동일
  - `test_from_garbage_defaults` — `from_dict({"sluices": "x", "tower_stopped": 5})` → 기본값
  - `test_lake_levels` — `level(6.6, 0..3)` = 6.6, 5.4, 4.2, 3.0; `level(6.6, 7)` = 3.0
- [ ] **Step 2:** FAIL. **Step 3:** 구현 + 씬 배치. **Step 4:** ALL PASSED.
- [ ] **Step 5:** 탐침 `tests/_probe_lake.gd`: (a) 수문 0 → 둑길 위 (0, 4, 20)에 놓은 플레이어 = SWIMMING, (b) `open_sluice(0..2)` 후 수위가 3.0에 도달(약 10초) → 같은 자리 GROUNDED, 남쪽 기슭에서 탑 섬까지 걸어서(스틱 앞) 도달, (c) 수위 하강 중 헤엄치던 플레이어가 GROUNDED로 바뀜 (Review Focus 4).
- [ ] **Step 6:** 커밋 `feat(m4a): 진행 상태·저수호 수위·수문 3곳`

### Task 5: 탑 · 코어 정지 · 회복 연출

**Files:** Create `scripts/nodes/tower_core.gd`, `scenes/tower.tscn` · Modify `scripts/nodes/first_island.gd`, `scripts/nodes/machine.gd`, `scenes/first_island.tscn`

**Interfaces:**
- Consumes: `WorldState.stop_tower()`, 기존 `Machine`.
- `tower.tscn`: 탑 몸체 상자 8×60×8 (각진 고대 금속, 03 설계서 6장) + 쉼터 고리 발판 2개 (20m·40m, 폭 3m) + 꼭대기 발판 + `TowerCore`(청록 발광 구, keep_color) + 소용돌이 `GPUParticles3D`(링 반경 120m에서 탑 꼭대기로: 음의 radial_accel + tangential_accel, 잿빛, amount 600) + 어두운 구름판(반투명 원판, y 90) + 생명력 터짐 `GPUParticles3D`(one_shot, amount 800, 초록·금, 바깥으로 퍼진 뒤 낙하).
- `TowerCore` (그룹 "interactable"): `prompt()` = `"정지"` / 정지 후 `"탑 (멈춤)"`, `interact(player)` → `world.stop_tower()`.
- `FirstIsland.stop_tower()`: `state.stop_tower()`가 true일 때만 — 소용돌이 emitting=false, 터짐 발사, 구름판 페이드, `vitality_radius` 0→220 6초 트윈(`RenderingServer.global_shader_parameter_set`), 그룹 "enemy"의 `deactivate()` 호출.
- `Machine.deactivate()`: 공격 취소, 이동 정지, 회색(본체 색 어둡게, 눈 발광 끔), `is_alive()` false, 부활 없음, 부품 드롭 없음.
- 배치: 탑 섬 (0, 8, −10). 기계: 칼날형 탑 밑 (6, 8, −2), 칼날형 40m 쉼터, 포격형 탑 섬 남쪽 기슭 (0, 8, −3) — 저수호를 향함.

- [ ] **Step 1:** 구현.
- [ ] **Step 2:** `./run_tests.sh` ALL PASSED.
- [ ] **Step 3:** 탐침 `tests/_probe_tower.gd`: 플레이어를 탑 밑에 두고 탑 쪽으로 스틱 → CLIMBING → 20m 쉼터 GROUNDED 확인 → 계속 등반 → 꼭대기 도달 (각 단계 스태미나 출력, 쉼터에서 회복 확인) → `TowerCore.interact` → 6초 후 `vitality_radius` ≈ 220, 모든 기계 `is_alive()` false, `state.outcome_at_stop` 출력.
- [ ] **Step 4:** 커밋 `feat(m4a): 탑 등반·코어 정지·회복 연출`

### Task 6: 지도 꾸미기 · 경로 검증 · 확인 양식

**Files:** Modify `scenes/first_island.tscn` · Create `docs/perf/m4a-check.md`

**Interfaces:**
- Consumes: 전부.
- 배치(상자 도형, vitality 재질): 수문1 아래 30m 바위벽(중간 턱 1개, 15m), 서쪽 능선 끝 활공 출발 바위, 수문3 거점(낮은 벽 + 칼날형 2 + 포격형 1), 마을 자리 임시 집 6채·우물·대장간 블록(M4b에서 다듬음), 고대 수로(각진 금속 홈).
- 수문 높이를 지형 `height_at`에 맞춰 보정.
- `m4a-check.md`: 조작 요약, 지도 설명(수문 3곳 위치 힌트는 지형으로만), 체크리스트 — 지시 없이 수문을 찾았는가 / 수문 여는 순서별 둑길 체감 / 탑 등반 쉼터 / 정지 연출 강도 / 잿빛 세계 피로감 / FPS(마을·저수호·탑 꼭대기·정지 순간) — 판정 기준.

- [ ] **Step 1:** 배치 + 문서.
- [ ] **Step 2:** `./run_tests.sh` ALL PASSED.
- [ ] **Step 3:** 탐침 `tests/_probe_routes.gd`: (a) 수문1 — 바위벽 밑에서 등반해 수문 상호작용 범위 도달 (스태미나 0 전에), (b) 수문2 — 서쪽 능선 출발 바위에서 활공해 서쪽 고원 착지, (c) 마을 → 수문3 거점까지 걸어서 지형에 막히지 않음, (d) 45~72° 지형 경사 한 곳에서 등반 시작 (Review Focus 5).
- [ ] **Step 4:** 커밋 `feat(m4a): 첫 섬 지도 배치·경로 검증·확인 양식`

### Task 7: 태블릿 확인 (사용자 수행)

- [ ] `git pull` → `docs/perf/m4a-check.md` 기록 (FPS 4장면 + 체크리스트).
- [ ] 판정: FPS 30 미만이면 지형 격자·입자 수 축소, 길 찾기가 막히면 랜드마크 보강 → 그 뒤 M4b(마을·대화·저장) 계획.
