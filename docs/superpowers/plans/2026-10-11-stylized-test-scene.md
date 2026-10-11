# 스타일 개편 1부 — Compatibility 전환 · 색면 셰이더 · 코드 생성 에셋 · 테스트 씬 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 렌더러를 Compatibility로 바꾸고, 사진 텍스처 없는 색면 스타일(코드 생성 바위·식생·건축·구름 + 지역 회복 지도)을 `scenes/style_test.tscn` 한 장면에서 검증한다.

**Architecture:** 색 결정은 공통 include(`style_common.gdshaderinc`) 하나에 모으고, 회복은 노드 비의존 모델(`Recovery`)이 지역별 0~1을 계산해 저해상도 회복 지도 텍스처로 구워 전역 셰이더 변수로 넘긴다. 메시는 `scripts/core/gen/`의 결정적 생성기가 정점색(AO·명도)까지 구워 만든다. 첫 섬 통합·웹 빌드는 2부 계획(이 계획의 결과를 사용자 승인 후 작성).

**Tech Stack:** Godot 4.7.2, GDScript, **Compatibility 렌더러(gl_compatibility)**, 자체 테스트 러너 `./run_tests.sh`, 스크린샷 `tools/shots.sh`(xvfb + Mesa llvmpipe OpenGL).

**Spec:** `docs/superpowers/specs/2026-10-11-stylized-graphics-design.md` · 지침 `docs/GRAPHICS_IMPLEMENTATION_GUIDE.md`

## Global Constraints

- 렌더러 `gl_compatibility`(데스크톱·모바일 모두). Forward+ 전용 기능(SSAO·SSIL·볼류메트릭 안개·SDFGI·SSR) 사용 금지. 셰이더에서 `DEPTH_TEXTURE`·`SCREEN_TEXTURE`·`hint_depth_texture`·`hint_screen_texture` 금지.
- 새 그래픽에 사진 텍스처·노멀맵 금지. 색 = 기본색 × 정점색 × 저주파 노이즈(명도 ±5~8%).
- 팔레트 시작값 = 설계서 5장 (아래 Task 2 `StylePalette`에 그대로). 생명 에너지 `#76C9C3`, 적 예고 `#FFD933`/`#FF2619`, 코어 `#4DE6FF`는 회복값과 무관하게 고채도.
- 회복: 지역별 0~1, `TASK_CAP = 0.4`(탑 외 과제 합계 상한) < 탑 무력화(→1.0). 단계 경계 `DEPLETED < 0.3 ≤ REGENERATING < 1.0 = RESTORED`.
- 생성기는 결정적(같은 인자 = 같은 메시). 예산: 바위 40~200, 나무 150~400, 풀 6~10, 건축 부품 12~200, 구름 100~300 삼각형.
- 기존 게임플레이 무변경: 테스트 184개 ALL PASSED 유지, 첫 섬 헤드리스 실행 SCRIPT ERROR 0.
- 기존 첫 섬 그래픽(실사 셰이더·에셋)은 이 계획에서 고치지도 지우지도 않는다(Compatibility에서 깨지는 곳만 목록화).
- 문서·주석·커밋 메시지는 한국어, 기존 코드 관례(class_name, `##` 문서 주석, 탭 들여쓰기) 따름.

## Review Focus

1. **회복 지도 경계 밖 좌표:** 지도 범위 밖 월드 위치는 0(고갈)으로 읽혀야 함(텍스처 반복으로 반대편 값이 새면 안 됨) → Task 3 `test_bake_outside_rect_is_zero` + 셰이더 샘플러 `repeat_disable`.
2. **같은 위치에 겹친 두 지역:** 값은 둘 중 큰 쪽(합산 아님, 1 초과 금지) → Task 3 `test_overlapping_regions_take_max`.
3. **탑 무력화 후 과제 추가:** 1.0 유지(내려가거나 넘치지 않음) → Task 3 `test_progress_after_tower_stays_one`.
4. **음수·과도한 과제 기여:** `add_progress(-0.2)`는 무시, 상한 초과는 잘림 → Task 3 `test_negative_progress_ignored`.
5. **평면 음영이 아주 먼 지형에서 깜빡임(dFdx 정밀도):** 원거리에서 평면/부드러움 섞기 → Task 2 셰이더 `flat_fade_end` + Task 7 원경 스크린샷 검토 항목.

---

### Task 1: Compatibility 전환 + 스크린샷 도구 일반화 + 호환성 목록

**Files:**
- Modify: `project.godot` (`renderer/rendering_method="gl_compatibility"`, `.mobile`도 동일, `config/features`의 `"Forward Plus"` → `"GL Compatibility"`)
- Modify: `tools/shots.sh` (`--rendering-driver opengl3`, 인자 `<tag> [mode] [scene]`), `tools/screenshot.gd` (장면별 시점 표, 모드 = 회복값 목록)
- Create: `docs/perf/compat-audit.md`

**Interfaces:**
- Produces: `tools/shots.sh <tag> [grey|color|both|r0,r50,r100] [first_island|style_test]` → `/tmp/claude-0/shots/<tag>_<view>_<mode>.png`. `screenshot.gd`는 장면 루트에 `set_preview_recovery(v: float)`가 있으면 그것을, 없으면 기존 vitality 경로를 쓴다.

- [ ] **Step 1:** 렌더러 설정 변경 후 `./run_tests.sh` → `ALL PASSED (184 tests)`.
- [ ] **Step 2:** `timeout 120 godot --headless --quit-after 300` (첫 섬) → `SCRIPT ERROR` 0.
- [ ] **Step 3:** `tools/shots.sh compat_before both first_island` → 8장 저장. 경고·셰이더 오류를 `compat-audit.md`에 표로: 기능 | Compatibility 동작 | 2부에서 할 일 (예: 물 `hint_depth_texture`, SSAO/SSIL/볼류메트릭 무시, 글로우 차이).
- [ ] **Step 4:** 커밋 `chore(gfx): Compatibility 렌더러 전환 + 스크린샷 도구 장면 인자`

### Task 2: 팔레트 · 공통 색면 셰이더 · 하늘 · 환경

**Files:**
- Create: `scripts/core/style_palette.gd`, `shaders/style_common.gdshaderinc`, `shaders/style_lit.gdshader`, `shaders/style_terrain.gdshader`, `shaders/style_sky.gdshader`, `shaders/style_water.gdshader`, `resources/style/style_env.tres`
- Modify: `project.godot` (`shader_globals`: `recovery_map` sampler2D, `recovery_map_rect` vec4 = (-256,-256,512,512), `recovery_here` float = 0)
- Test: `tests/unit/test_style_palette.gd`

**Interfaces:**
- Produces:
  - `class_name StylePalette` — `const DEPLETED := {...}`, `const RESTORED := {...}` (키: `sky_zenith, sky_horizon, grass, grass_tip, ground, rock, foliage, water_shallow, water_deep`), `const LIFE := Color("#76C9C3")`, `static func color(key: String, recovery: float) -> Color` (선형 보간).
  - include 함수: `float recovery_at(vec3 world_pos)` (전역 `recovery_map`, `recovery_map_rect`; 범위 밖 0), `float big_noise(vec2 p)` (값 노이즈, 0~1), `vec3 style_color(vec3 depleted, vec3 restored, float r, vec3 world_pos, float noise_amount)`.
  - `style_lit` uniform: `color_depleted`, `color_restored` (source_color), `noise_amount = 0.06`, `noise_scale = 0.02`, `flat_shading = true`, `flat_fade_end = 150.0`, `wind = 0.0`(정점색 G = 흔들림 가중). 정점색 RGB = 명도 배수, A = AO.
  - `style_terrain` uniform: 팔레트 4색(풀·흙·바위·모래) × 고갈/회복, `cliff_slope = 0.62`(법선 y 아래면 바위색), `sand_height = 1.5`, `flat_shading`.
  - `style_sky` uniform: 천정·지평선 × 고갈/회복, `horizon_sharpness = 6.0`, 해 원반. 전역 `recovery_here` 사용.
  - `style_water` uniform: 얕음·깊음 × 고갈/회복, 정점색 R = 깊이(0~1), 약한 파문(시간 노이즈 법선), 알파 0.85.
  - `style_env.tres`: Sky = `style_sky`, 환경광 = 하늘, 톤매핑 Filmic, 거리 안개 + 높이 안개(색 = 고갈 지평선 `#AABAC5`), 글로우 약하게(threshold 1.2).

- [ ] **Step 1: 실패 테스트** `test_style_palette.gd`:
  - `test_depleted_and_restored_match_spec` — `StylePalette.DEPLETED.sky_horizon == Color("#AABAC5")`, `DEPLETED.grass == Color("#A5AC91")`, `DEPLETED.rock == Color("#8C918F")`, `DEPLETED.ground == Color("#C8C2AC")`, `RESTORED.grass == Color("#6FA35A")`, `RESTORED.sky_zenith == Color("#4F86C0")`, `LIFE == Color("#76C9C3")`
  - `test_color_interpolates` — `color("grass", 0.0) == DEPLETED.grass`, `color("grass", 1.0) == RESTORED.grass`, `color("grass", 0.5)`는 두 색의 중간(각 채널 오차 0.01)
  - `test_restored_is_more_saturated` — 모든 키에서 `RESTORED[k].s >= DEPLETED[k].s` (하늘 지평선 제외 허용 없음: 지평선도 같거나 큼)
- [ ] **Step 2:** `./run_tests.sh` → 위 3개 FAIL.
- [ ] **Step 3:** 팔레트·셰이더·환경 구현. 셰이더 5개는 빈 테스트 씬에 MeshInstance 하나씩 붙여 `godot --headless`로 로드해 컴파일 오류 0 확인(헤드리스는 셰이더 컴파일을 하지 않으므로 Step 4 스크린샷으로 최종 확인).
- [ ] **Step 4:** `./run_tests.sh` ALL PASSED. 커밋 `feat(gfx): 스타일 팔레트 + 색면·지형·하늘·물 셰이더`

### Task 3: 회복 모델 (지역 · 단계 · 상한 · 굽기)

**Files:**
- Create: `scripts/core/recovery.gd`
- Test: `tests/unit/test_recovery.gd`

**Interfaces:**
- Produces: `class_name Recovery extends RefCounted`
  - `enum Stage { DEPLETED, REGENERATING, RESTORED }`, `const TASK_CAP := 0.4`, `const DEPLETED_BELOW := 0.3`, `const EDGE := 12.0`(지역 가장자리 번짐 m)
  - `add_region(id: StringName, center: Vector2, radius: float) -> void`
  - `add_progress(id: StringName, amount: float) -> void` (음수 무시, 합계 `TASK_CAP`에서 멈춤)
  - `neutralize_tower(id: StringName) -> void` · `value(id) -> float` (탑 = 1.0, 아니면 과제 합계) · `stage(id) -> Stage`
  - `set_preview(v: float) -> void` (−1 = 끔; 0~1이면 모든 지역 값을 덮어씀 — 테스트 씬 슬라이더용)
  - `value_at(p: Vector2) -> float` (지역들 중 최댓값, 반경 밖 `EDGE` m 동안 0으로 번짐)
  - `bake(rect: Rect2, res: int) -> PackedFloat32Array` (res×res, 행 우선, 칸 중심 좌표에서 `value_at`; rect 밖은 굽지 않음)
  - `to_dict() -> Dictionary` / `static from_dict(d: Dictionary) -> Recovery`

- [ ] **Step 1: 실패 테스트** `test_recovery.gd`:
  - `test_stage_bounds` — 0.0 → DEPLETED, 0.29 → DEPLETED, 0.3 → REGENERATING, 0.99 → REGENERATING, 탑 → RESTORED
  - `test_task_progress_capped_below_tower` — `add_progress` 0.3 + 0.3 → `value == 0.4`; `neutralize_tower` → 1.0
  - `test_progress_after_tower_stays_one` (Review Focus 3)
  - `test_negative_progress_ignored` (Review Focus 4) — −0.2 후 0.0
  - `test_value_at_inside_edge_outside` — 반경 50 지역 값 1: 중심 1.0, 거리 50에서 1.0, 50+EDGE에서 0.0, 그 사이 0~1
  - `test_overlapping_regions_take_max` (Review Focus 2) — 0.4와 1.0 지역 겹침 → 1.0
  - `test_bake_size_and_values` — `bake(Rect2(-64,-64,128,128), 8)` 길이 64, 중심 칸 ≈ 지역 값
  - `test_bake_outside_rect_is_zero` (Review Focus 1) — 지역이 rect 밖이면 모든 칸 0
  - `test_preview_overrides_and_clears` — `set_preview(0.7)` → 모든 `value` 0.7, `set_preview(-1)` → 원래 값
  - `test_dict_roundtrip` — 과제 0.2·탑 1개 상태 왕복 후 같은 `value`
- [ ] **Step 2:** FAIL 확인. **Step 3:** 구현. **Step 4:** ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(core): 지역 회복 모델 (단계·과제 상한·탑·굽기)`

### Task 4: 회복 지도 노드

**Files:**
- Create: `scripts/nodes/recovery_map.gd`
- Test: `tests/unit/test_recovery_map.gd`

**Interfaces:**
- Consumes: `Recovery.bake`, `Recovery.value_at` (Task 3); 전역 `recovery_map`, `recovery_map_rect`, `recovery_here` (Task 2)
- Produces: `class_name RecoveryMap extends Node` — `@export world_rect := Rect2(-256,-256,512,512)`, `@export resolution := 128`, `@export blend_speed := 0.5`(초당 값 변화), `var model: Recovery`, `func refresh() -> void`(목표 다시 굽기), `func step(dt: float) -> void`(표시값을 목표로 `blend_speed*dt`만큼 이동, 텍스처 갱신), `func displayed_at(p: Vector2) -> float`. `_process`는 `step(dt)` 후 카메라 xz의 `displayed_at`을 `recovery_here`로 보낸다. 텍스처 = `Image.FORMAT_R8` → `ImageTexture`(update로 재사용).

- [ ] **Step 1: 실패 테스트**:
  - `test_step_moves_toward_target_without_jump` — 목표 1.0, `step(0.5)` → 표시 0.25(±0.01), 4초 후 1.0
  - `test_displayed_at_outside_rect_zero`
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(gfx): 회복 지도 텍스처 노드 (보간·전역 변수)`

### Task 5: 메시 도구 + 바위·구름 생성기

**Files:**
- Create: `scripts/core/gen/mesh_kit.gd`, `scripts/core/gen/rock_gen.gd`, `scripts/core/gen/cloud_gen.gd`
- Test: `tests/unit/test_gen_rock_cloud.gd`

**Interfaces:**
- Produces:
  - `class_name MeshKit extends RefCounted` — `add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void`(면 법선, 반시계 = 바깥), `tri_count() -> int`, `bake_height_ao(min_y: float, max_y: float, strength: float) -> void`(아래쪽 어둡게 → 정점색 A), `commit() -> ArrayMesh`
  - `class_name RockGen` — `static func build(seed: int, kind: int) -> ArrayMesh`, `enum Kind { ROUND, SLAB, PILLAR }`. 정이십면체(세분 1회) → 저주파 변위 → 평면 깎기 2~4개 → 크기 약 1m 정규화(PILLAR는 높이 2.5).
  - `class_name CloudGen` — `static func build(seed: int) -> ArrayMesh` (변형 구 3~6개 뭉침, 아래면 평평하게, 정점색 G = 정점 애니메이션 가중)

- [ ] **Step 1: 실패 테스트**:
  - `test_rock_deterministic` — 같은 (seed, kind) 두 번 → 정점 배열 동일; 다른 seed → 다름
  - `test_rock_budget` — 세 종류 × seed 5개 모두 40~200 삼각형
  - `test_rock_normals_outward` — 모든 면 법선 · (면 중심 − 메시 중심) > 0
  - `test_rock_colors_in_range` — 정점색 RGB 0.8~1.1 배수 범위, A(AO) 0.4~1.0
  - `test_cloud_budget_and_flat_bottom` — 100~300 삼각형, 최저 정점들의 y 편차 < 0.15 × 높이
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(gen): 메시 도구 + 바위·구름 생성기`

### Task 6: 식생 생성기 (풀 3 · 나무 3)

**Files:**
- Create: `scripts/core/gen/grass_gen.gd`, `scripts/core/gen/tree_gen.gd`, `shaders/style_foliage.gdshader`
- Test: `tests/unit/test_gen_foliage.gd`

**Interfaces:**
- Consumes: `MeshKit` (Task 5), `style_common.gdshaderinc` (Task 2)
- Produces:
  - `class_name GrassGen` — `static func build(kind: int) -> ArrayMesh`, `enum Kind { TUFT, BROAD, FLOWER }`. 둥근 덩어리: 끝이 넓은 꽃잎형 잎 3~5장(끝 폭 ≥ 뿌리 폭 × 0.6 — 뾰족한 털 금지), 정점색 G = 높이 비율(바람 가중), A = AO(뿌리 0.5). FLOWER는 꽃 부분 정점색 R=2(셰이더가 꽃색으로 표시).
  - `class_name TreeGen` — `static func build(seed: int, kind: int) -> ArrayMesh`, `enum Kind { ROUND, COLUMN, SHRUB }`. 각진 줄기(6각) + 잎 덩어리 2~4개(변형 다면체). 서피스 2개: 0 = 줄기, 1 = 잎.
  - `style_foliage.gdshader`: `style_lit` + 정점 바람(`wind_strength = 0.06`, 정점색 G 가중) + `INSTANCE_CUSTOM.r` 문턱값: `recovery_at(인스턴스 위치)`로 계산한 밀도 `mix(density_depleted, density_restored, r)`보다 문턱이 크면 정점을 0으로 접어 숨김. 꽃 표시는 r ≥ 0.5부터.
- [ ] **Step 1: 실패 테스트**:
  - `test_grass_budget_and_no_spikes` — 세 종류 6~10 삼각형(FLOWER는 ≤ 14); 각 잎 끝 폭/뿌리 폭 ≥ 0.6
  - `test_grass_wind_weight_root_zero` — y 최저 정점의 G = 0, 최고 정점 G ≥ 0.9
  - `test_tree_budget_and_surfaces` — 150~400 삼각형, 서피스 2개
  - `test_tree_deterministic_and_varied` — 같은 seed 동일, seed 1·2의 높이 차 > 5%
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(gen): 덩어리형 풀 3종·나무 3종 + 식생 셰이더(바람·회복 밀도)`

### Task 7: 건축 부품 생성기 (블록·계단·기둥·아치)

**Files:**
- Create: `scripts/core/gen/structure_gen.gd`
- Test: `tests/unit/test_gen_structure.gd`

**Interfaces:**
- Consumes: `MeshKit` (Task 5)
- Produces: `class_name StructureGen` —
  - `static func block(size: Vector3, bevel: float, seed: int, damage: float) -> ArrayMesh` (모서리 경사 면, damage 0~1 = 모서리 떨어짐 개수)
  - `static func stairs(steps: int, width: float, step_h: float, step_d: float, seed: int) -> ArrayMesh`
  - `static func pillar(height: float, radius: float, seed: int, broken: bool) -> ArrayMesh` (8각 + 받침·머리, broken이면 위가 비스듬히 잘림)
  - `static func arch(span: float, height: float, thickness: float, seed: int) -> ArrayMesh` (반원 아치 분할 8 + 기둥 2)
  - 모두 정점색: 위쪽 밝게·아래 AO, 면마다 명도 ±4%.
- [ ] **Step 1: 실패 테스트**:
  - `test_block_bevel_adds_faces` — bevel 0 → 12 삼각형, bevel 0.1 → > 12; 바운딩 박스 = size(±1%)
  - `test_parts_in_budget` — 네 부품 기본값 12~200 삼각형
  - `test_damage_changes_mesh_deterministically` — damage 0과 0.5 다름, 같은 인자 두 번 동일
  - `test_stairs_height` — 바운딩 높이 = steps × step_h
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED.
- [ ] **Step 5:** 커밋 `feat(gen): 건축 부품 생성기 (블록·계단·기둥·아치)`

### Task 8: 스타일 테스트 씬

**Files:**
- Create: `scripts/core/gen/test_island_gen.gd`, `scripts/nodes/style_test.gd`, `scenes/style_test.tscn`
- Modify: `tools/screenshot.gd` (`style_test` 시점: `near`·`mid`·`far`·`ruin`, 모드 `r0,r50,r100`)
- Test: `tests/unit/test_test_island_gen.gd`

**Interfaces:**
- Consumes: Task 2~7 전부, 기존 `HeightField`, `TerrainMesh.build(field, cell)`, `scenes/player.tscn`
- Produces: `class_name TestIslandGen` — `static func image(size: int, seed: int) -> Image` (FORMAT_RGB8 16-bit 관례: R 상위·G 하위; 128m 섬: 완만한 언덕, 높이 12m 절벽 한 줄, 협곡 1개, 작은 연못(바닥 < 수면 2.0)). `StyleTest.set_preview_recovery(v: float)`.
- 장면 구성: `WorldEnvironment`(style_env) · `Sun`(그림자 60m, 2분할) · `Terrain`(MeshInstance + 충돌, `style_terrain`) · `Water`(정점색 깊이) · `RecoveryMap`(지역 "test" 중심 (0,0) 반경 40) · 바위(종류별 MultiMesh, 절벽 가장자리에 큰 덩어리 3~5개는 개별 노드) · 나무 3종 MultiMesh · 풀 3종 MultiMesh(노이즈 군집, `INSTANCE_CUSTOM.r` 문턱) · 폐허(계단+기둥 3+아치+블록) · 구름 8~12개(원경 고리 + 섬 위 몇 개) · 원경 능선 링(색면) · 생명 입자(`CPUParticles3D`, `#76C9C3` 떠다니는 점, 개수 = r × 40, r < 0.3이면 0) · `Player` · 디버그 UI(회복 슬라이더, 평면 음영·안개 토글, FPS·`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`·`RENDER_TOTAL_PRIMITIVES_IN_FRAME`).
- [ ] **Step 1: 실패 테스트** `test_test_island_gen.gd`:
  - `test_size_and_deterministic` — 크기 = size², 같은 seed 동일
  - `test_has_cliff_and_pond` — `HeightField`로 읽어 경사 > 60° 칸 존재, 연못 중심 높이 < 2.0, 가장자리 높이 < 0.5(바다)
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED.
- [ ] **Step 5:** `godot --headless --quit-after 300 scenes/style_test.tscn` → SCRIPT ERROR 0. `tools/shots.sh st r0,r50,r100 style_test` → 12장, `python3 tools/contact_sheet.py st`.
- [ ] **Step 6: 시각 검토(에이전트):** 대조 시트로 판정 — ① 사진 텍스처·반복 무늬 없음 ② 풀이 덩어리로 읽히고 불쾌하지 않음 ③ 절벽·폐허 실루엣이 원경에서 구분 ④ 하늘-지평선-원경이 안개로 이어짐 ⑤ r0/r50/r100이 한눈에 구분, 강조색만 고채도 ⑥ 원경 평면 음영 깜빡임 없음(Review Focus 5). FAIL 항목은 수치 조정 후 재촬영(최대 2회), 남으면 보고.
- [ ] **Step 7:** 커밋 `feat(gfx): 스타일 테스트 씬 (지형·바위·식생·폐허·하늘·구름·물·회복 슬라이더)`

### Task 9: 성능 측정 · 문서 개정 · 사용자 확인 양식

**Files:**
- Create: `docs/perf/style-test-check.md`(태블릿 양식: 에디터에서 `style_test.tscn` 실행 → 시점 3곳 FPS, 슬라이더 0/0.5/1 인상, 풀·절벽·폐허 평가 칸)
- Modify: `docs/design/03-art-direction.md` → v0.3 (설계서 결정 S1~S6 반영, 실사풍 폐기 표기), `docs/design/01-core-design.md` 10장 렌더러 = Compatibility

- [ ] **Step 1:** 테스트 씬 4시점 헤드리스 렌더 측정(그리기 호출·삼각형 수)을 `style-test-check.md` 상단에 기록. 예산: 그리기 호출 < 150, 삼각형 < 30만.
- [ ] **Step 2:** 문서 개정, `./run_tests.sh` ALL PASSED, 첫 섬 헤드리스 SCRIPT ERROR 0.
- [ ] **Step 3:** 커밋·푸시 `docs: 그래픽 설계서 v0.3 (색면 스타일·Compatibility) + 테스트 씬 확인 양식`

## 실행 순서 (에이전트 활용)

- **직접(메인):** Task 1 → Task 2 (기반·전역 변수 — 이후 모두가 의존)
- **병렬 워크트리 에이전트 3개:** A = Task 3 + Task 4, B = Task 5 + Task 6, C = Task 7 (B의 `MeshKit`이 필요 → C는 B의 Task 5 커밋 후 시작하거나 MeshKit 인터페이스대로 임시 구현 금지: **C는 B의 Task 5 완료 뒤 시작**)
- **메인:** 병합 → Task 8(통합·시각 검토 에이전트) → Task 9 → 최종 리뷰 에이전트
