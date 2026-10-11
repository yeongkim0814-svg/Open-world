# B. 첫 지역 식생·바위 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2 km 첫 지역에 군락형 풀·덤불·활엽수(3형태)·바위를 카메라 주변 결정적 스트리밍으로 깐다.

**Architecture:** 순수 단위(VegContext = 지도 조회·제외, VegPlacement = 블록 → 개체 목록, VegCatalog = 메시·재질)와 노드 VegetationField(스트리밍·MultiMesh·충돌)로 나눈다. 블록 시드 = hash(world_seed, layer, key). 거리 전환은 visibility_range.

**Tech Stack:** Godot 4.7.2 GDScript, gl_compatibility, 자체 테스트 러너 `./run_tests.sh` (tests/unit/test_*.gd, `extends TestCase`, assert_true/assert_eq/assert_almost).

**Spec:** `docs/superpowers/specs/2026-10-13-vegetation-rocks-design.md`

## Global Constraints

- Compatibility 렌더러: GLSL ES 3.0, DEPTH/SCREEN 텍스처 금지.
- 사진 텍스처 금지 — 기존 생성기(MeshKit·GrassGen·TreeGen·RockGen) + style 셰이더(style_lit·style_foliage)만.
- 결정성: 같은 입력 = 같은 출력 (RandomNumberGenerator 시드 고정, FastNoiseLite 시드 고정, Dictionary 순회 순서에 의존 금지).
- 성능: 4시점 그리기 호출 ≤ 250(지형 포함), 보이는 삼각형 ≤ 60만, 스트리밍 프레임당 ≤ 3 ms.
- 층 수치(설계서 3·4장): 풀 블록 16 m·보임 55 m(페이드 끝 15 m), 덤불 64 m·160 m, 나무 128 m·LOD0 0~260 m / LOD1 240~700 m, 바위 128 m·500 m. 충돌 48 m.
- 주석·문서는 한국어, 기존 코드 밀도에 맞춤. `./run_tests.sh` 는 직접 실행 (`sh -c` 금지).
- 커밋 꼬리: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_01PShdycDoYj1ffFPsLxdXpC`.

## Review Focus

1. 지도 가장자리(±world/2) 블록: 이미지 밖 조회 → 범위 고정(clamp), 오류·개체 0 아님 (Task 2 테스트).
2. 저수호 정상: 호수 수면 아래·탑 섬에 나무·바위 없음, 둑 위 풀은 허용 (Task 3 테스트).
3. 수위 변화(수문 열림 등)로 물 노드가 나중에 생겨도 VegetationField 가 다음 블록부터 반영 (Task 5: `_water` 를 블록 만들 때마다 그룹에서 다시 읽음).
4. 텔레포트(먼 이동): 이전 블록 모두 해제, 새 위치 가까운 블록부터 (Task 5 테스트).
5. 경사 절벽 위 바위가 공중에 뜨지 않음: 묻힘 = 크기 × 0.2~0.4 이고 위치 높이 = 바위 바닥 네 모서리 표본의 최솟값 (Task 3 테스트).

---

### Task 1: 생성기 확장 (TreeGen SPREAD·LOD1, GrassGen LOW·꽃색, 잎 셰이더 개체 색)

**Files:**
- Modify: `scripts/core/gen/tree_gen.gd`, `scripts/core/gen/grass_gen.gd`, `shaders/style_foliage.gdshader`
- Test: `tests/unit/test_tree_gen.gd`, `tests/unit/test_grass_gen.gd` (있으면 추가, 없으면 생성)

**Interfaces:**
- Produces: `TreeGen.Kind.SPREAD` (enum 끝에 추가 = 3), `TreeGen.build(seed: int, kind: int, lod := 0) -> ArrayMesh` — lod 1 = 4각 줄기 + 수관 덩어리 1~2(정이십면체 비세분 20면), ≤ 40 삼각형, 서피스 0 줄기 / 1 잎 유지, lod 0 과 키·수관 중심 같음(같은 rng 순서로 크기 결정 후 메시만 다름).
- Produces: `GrassGen.Kind.LOW` (= 3): 잎 6~7장, 높이 0.10~0.14, 넓게 퍼짐. `GrassGen.build(kind)` 그대로.
- Produces: style_foliage 개체 색: `INSTANCE_CUSTOM.g` = 명도(0..1 → ×0.85..1.12), `.b` = 색온도(0 차가움 ↔ 1 따뜻함, ±6 % 녹/황 이동), `.a` = 꽃색(< 0.5 노랑 flower_*, ≥ 0.5 흰색 `flower2_depleted/restored` 새 uniform). `.r` = 기존 밀도 문턱 유지. custom 미사용 MultiMesh(값 0)일 때 기존과 같은 색이 나오도록 g·b 0 을 "변화 없음"으로 쓰지 말고 **use_custom 플래그 uniform `instance_tint` (기본 false)** 로 켠다.

- [ ] **Step 1: 실패 테스트** — `test_tree_spread_and_lod1`: `TreeGen.build(3, TreeGen.Kind.SPREAD)` 두 번 → 같은 정점 수(결정적), 수관 폭(AABB x·z) / 키(AABB y) ≥ 0.9 (평관형); 세 형태 × seed 0..5 의 `build(s, k, 1).get_faces().size() / 3 <= 40`; lod0·lod1 AABB 높이 차 < 15 %. `test_grass_low`: `GrassGen.build(GrassGen.Kind.LOW)` AABB 높이 ≤ 0.16, 폭 ≥ 0.3.
- [ ] **Step 2: `./run_tests.sh` → 위 테스트 FAIL 확인**
- [ ] **Step 3: 구현** — SPREAD: 줄기 높이 2.0~2.8, 수관 = 납작한 큰 덩어리 1(반경 rr 2.0~2.6, 높이 비 0.45) + 가장자리 작은 덩어리 2~3. LOD1: `_blob` 대신 세분 없는 `_blob_coarse`(20면), 줄기 `_trunk` 의 변 수 4. 셰이더: varying 으로 tint 전달, `instance_tint` false 면 무시.
- [ ] **Step 4: `./run_tests.sh` → ALL PASSED**
- [ ] **Step 5: 커밋** `feat(gen): 활엽수 평관형·나무 LOD1·낮은 풀·잎 개체 색`

### Task 2: VegContext (지도 조회·제외 규칙)

**Files:**
- Create: `scripts/core/veg/veg_context.gd`
- Test: `tests/unit/test_veg_context.gd`

**Interfaces:**
- Consumes: `HeightField.height_at(x, z)`, `HeightField.normal_at(x, z)`, `HeightField.world_size`; zones·paths `Image`(FORMAT_R8 또는 L8, 값 = 구운 인덱스; paths 0 없음 1 흙길 2 포장길 3 수로 4 개천); markers `Array[Dictionary]` {kind, x, z, radius?, ...}; cfg `{"tower_radius": float, "lake_radius": float}`.
- Produces:
  - `class_name VegContext extends RefCounted`; `enum Layer { GRASS, SHRUB, TREE, ROCK }`
  - `func _init(field: HeightField, zones: Image, paths: Image, markers: Array, cfg := {}, water_level := Callable())` — water_level(x, z) -> float (수면 높이, 물 없음 = -INF). 비어 있으면 물 판정 없음.
  - `func zone_at(x: float, z: float) -> int` (0 초원, 1 활엽수림 — MapLegend.ZONES 순서; 이미지 밖은 가장자리 값)
  - `func edge_dist_zone(x: float, z: float, max_m := 20.0) -> float` — 다른 구역까지 거리(8방향 × 4 m 단계 표본, 없으면 max_m)
  - `func path_near(x: float, z: float, r: float) -> int` — 반경 r 안 8방향 + 중심 표본 중 가장 우선인 길 종류(개천 4 > 수로 3 > 포장 2 > 흙 1, 없음 0)
  - `func slope_ny(x: float, z: float) -> float`
  - `func excluded(layer: int, x: float, z: float) -> bool` — 설계서 4장 "제외" 전부 (길 1.5 / 수로 2 / 개천 3, 높이 < 0.8, 물 아래, 표식 반경, 정상 평탄지 나무 — 정상 = kind "peak" 표식에서 summit_radius(cfg, 기본 180) 안, 산마을 나무·바위만 r 35).
  - `func ground_y(x: float, z: float, foot := 0.0) -> float` — foot > 0 이면 (±foot, ±foot) 네 모서리 최솟값.

- [ ] **Step 1: 실패 테스트** — 128 m 합성 지도(HeightField 는 `MapBaker.encode_height` 로 만든 경사 이미지, zones 왼쪽 반 0 / 오른쪽 반 1, paths 가운데 세로 흙길 4 px, markers 마을 1·탑 1·peak 1): `test_zone_and_edge` (zone_at 좌·우, 경계 2 m 옆 edge_dist ≤ 4), `test_path_exclusion` (길 중심 1 m 옆 excluded(GRASS) true, 6 m 옆 false), `test_marker_exclusion` (마을 중심 40 m 안 모든 층 true; 산마을 30 m: TREE true, GRASS false), `test_water_and_sea` (높이 < 0.8 true; water_level 콜러블이 지면보다 높은 곳 true), `test_summit_no_trees` (peak 100 m: TREE true, ROCK false), `test_out_of_map_clamped` (x = world/2 + 50 에서 zone_at 오류 없이 가장자리 값).
- [ ] **Step 2: FAIL 확인**
- [ ] **Step 3: 구현** — 이미지 조회 픽셀 = round((x / world + 0.5) × (N − 1)) (굽기 관례), clamp.
- [ ] **Step 4: ALL PASSED**
- [ ] **Step 5: 커밋** `feat(veg): VegContext — 구역·길·표식·물 제외 규칙`

### Task 3: VegPlacement (블록 → 개체 목록)

**Files:**
- Create: `scripts/core/veg/veg_placement.gd`
- Test: `tests/unit/test_veg_placement.gd`

**Interfaces:**
- Consumes: VegContext (Task 2).
- Produces:
  - `class_name VegPlacement extends RefCounted`
  - `const BLOCK := {VegContext.Layer.GRASS: 16.0, SHRUB: 64.0, TREE: 128.0, ROCK: 128.0}`
  - 메시 id 문자열(카탈로그와 공유): 풀 `"grass_tuft_0" "grass_tuft_1" "grass_broad_0" "grass_broad_1" "grass_flower_0" "grass_flower_1" "grass_low_0" "grass_low_1"`; 덤불 `"shrub_0".."shrub_3"`, 꽃무리 = 풀 꽃 id 를 여러 개 반환; 나무 `"tree_<round|column|spread>_<0..5>"`; 바위 `"rock_<round|slab|pillar>_<0..3>"`.
  - `static func block(ctx: VegContext, layer: int, key: Vector2i, world_seed := 1337) -> Array` — 원소 `{"mesh": String, "xform": Transform3D, "custom": Color, "size": float}` (size = 바위·나무 크기 배율, 충돌 판단용). 블록 원점 = key × BLOCK[layer].
  - `static func noise(kind: String, world_seed: int) -> FastNoiseLite` — 캐시(static Dictionary), kind ∈ "clump_grass" (주파수 1/25), "clump_tree" (1/70), "species" (1/18).
- 수치: 설계서 4장 그대로 (풀 0.8 /m² 초원, 0.35 숲 바닥, 최대 1.6; 맨땅 clump 하위 25 %; 덤불 1/150·1/1500; 나무 숲 1/200 + clump_tree 상위 65 %, 초원 1/3000 무리 3~7; 형태 45/25/30 %; 최소 간격 4 m; 바위 1/150 경사·1/60 절벽 아래·1/4000 노두 무리 2~5; 크기 70/25/5 %; 묻힘 0.2~0.4; 기울기 풀 ≤ 8°, 바위 ≤ 25°). 후보 = 흔든 격자 (간격 = 1/√(최대 밀도)), 받아들임 확률 = 밀도/최대 밀도. 나무 위치 y = `ctx.ground_y(x, z, 0.5)`, 바위 y = `ctx.ground_y(x, z, size*0.4) − 묻힘`.
  - custom: 풀 r = rng 0..1(밀도 문턱), g 명도 rng, b = species 노이즈 기반(군락마다 색온도), a 꽃색 rng. 나무·바위 custom r = 0 (항상 보임).

- [ ] **Step 1: 실패 테스트** — Task 2 의 합성 지도 재사용(테스트 도우미를 `tests/unit/veg_fixture.gd` 로 빼서 둘이 공유): `test_deterministic` (같은 키 두 번 같은 목록, world_seed 다르면 다름), `test_exclusions_respected` (모든 층 블록 전체에서 개체 위치마다 `ctx.excluded(layer, x, z) == false`), `test_tree_density_forest_vs_meadow` (숲 쪽 블록 평균 나무 수 > 초원 × 5), `test_tree_slope_and_spacing` (normal_y ≥ 0.77, 같은 블록 쌍 거리 ≥ 4), `test_variety` (나무 최근접 쌍 중 같은 mesh 이고 |size 차| < 0.05 인 비율 < 0.1; 풀 블록 중 서로 다른 풀 종 ≥ 2 인 비율 > 0.6), `test_rock_not_floating` (경사 지형에서 각 바위 y ≤ 네 모서리 지면 최솟값 + 0.01), `test_edge_block` (지도 가장자리 키 → 오류 없음).
- [ ] **Step 2: FAIL 확인**
- [ ] **Step 3: 구현**
- [ ] **Step 4: ALL PASSED** (블록 하나 계산 시간도 출력: 풀 16 m 블록 < 3 ms, 나무 128 m < 15 ms 목표 — 넘으면 Task 5 에서 블록을 여러 프레임에 나눔)
- [ ] **Step 5: 커밋** `feat(veg): VegPlacement — 군락형 풀·덤불·트인 숲·바위 배치`

### Task 4: VegCatalog (메시·재질)

**Files:**
- Create: `scripts/core/veg/veg_catalog.gd`
- Test: `tests/unit/test_veg_catalog.gd`

**Interfaces:**
- Consumes: Task 1 생성기, Task 3 mesh id 목록, `StylePalette.DEPLETED/RESTORED`.
- Produces:
  - `class_name VegCatalog extends RefCounted`
  - `func _init()` — 모든 메시를 한 번 만든다 (나무는 LOD0·LOD1 둘 다).
  - `func mesh(id: String, lod := 0) -> ArrayMesh` (재질 적용됨; 나무 외 lod 무시)
  - `func ids() -> PackedStringArray`
  - `func rock_shape(id: String) -> ConvexPolygonShape3D` (메시 정점 → 볼록 껍질, 단위 크기; 호출 측이 크기 배율 적용)
  - `func trunk(id: String) -> Vector2` (줄기 반경, 높이 — 단위 크기)
  - 재질: 풀 `style_foliage` (grass·grass_tip, instance_tint true, fade 40/55), 덤불 (foliage·grass_tip, fade 120/160, density_depleted 1), 나무 잎 (style_test `_build_trees` 와 같은 값: density 1, height 1, wind 0.02, fade 무한) + 줄기 `style_lit` ground×0.55, 바위 `style_lit` rock.

- [ ] **Step 1: 실패 테스트** — `test_all_ids_build` (VegPlacement 가 낼 수 있는 모든 id 가 `ids()` 에 있고 mesh != null), `test_tree_lod` (나무 id 마다 mesh(id,1) 삼각형 ≤ 40), `test_rock_shape` (rock_shape 점 수 ≥ 8, 같은 id 두 번 = 같은 객체), `test_trunk` (나무마다 반경 > 0.1, 높이 > 0.8).
- [ ] **Step 2: FAIL 확인** · **Step 3: 구현** · **Step 4: ALL PASSED**
- [ ] **Step 5: 커밋** `feat(veg): VegCatalog — 식생·바위 메시와 재질`

### Task 5: VegetationField (스트리밍·MultiMesh·충돌)

**Files:**
- Create: `scripts/nodes/vegetation_field.gd`
- Test: `tests/unit/test_vegetation_field.gd`

**Interfaces:**
- Consumes: Task 2~4.
- Produces:
  - `class_name VegetationField extends Node3D`
  - `func setup(ctx: VegContext, catalog: VegCatalog, world_seed := 1337) -> void`
  - `func update_center(p: Vector3) -> void` — `_process` 가 활성 카메라 위치로 부른다 (테스트는 직접 부름).
  - `func step(budget_ms := 3.0) -> void` — 대기 블록을 예산 안에서 만든다 (`_process` 가 부름).
  - `func busy() -> bool`, `func stats() -> Dictionary` {blocks, instances, collision_blocks, pending}
  - `func block_keys(layer: int) -> Array` (테스트용)
  - 블록당: mesh id 별로 MultiMeshInstance3D 1개(나무는 LOD0·LOD1 두 개, visibility_range_end 260 / begin 240 end 700, margin 20; 풀 end 55, 덤불 160, 바위 500). 그림자: 나무·바위 LOD0 만 켬.
  - 충돌: 중심 48 m 안 TREE·ROCK 블록만 StaticBody3D(나무 = CylinderShape3D, 그룹 "no_climb"; 바위 size ≥ 1.2 = catalog.rock_shape 배율). 48 m 밖으로 나가면 지움.
  - 물: 블록 만들 때마다 `get_tree().get_nodes_in_group("water")` 로 water_level 다시 계산 (Review Focus 3).

- [ ] **Step 1: 실패 테스트** — 합성 fixture + VegetationField 를 테스트 트리에 붙임: `test_streams_around_center` (update_center 후 step 반복 → 풀 블록 중심이 모두 55 + 블록 대각 안), `test_releases_far_blocks` (중심을 500 m 옮기면 이전 풀 블록 0 — Review Focus 4, 새 블록은 가까운 것부터: 첫 step 뒤 만들어진 블록이 가장 가까운 것), `test_collision_only_near` (collision_blocks 의 블록 중심이 48 + 블록 대각 안), `test_no_climb_group` (나무 충돌체 그룹 "no_climb").
- [ ] **Step 2: FAIL 확인** · **Step 3: 구현** · **Step 4: ALL PASSED**
- [ ] **Step 5: 커밋** `feat(veg): VegetationField — 블록 스트리밍·거리 LOD·근처 충돌`

### Task 6: 2 km 장면 연결·측정

**Files:**
- Modify: `scripts/nodes/island_1km.gd` (VegetationField 생성: zones·paths Image = `load(BAKED + "zones.png")` 등 Image 리소스, markers, cfg = map.json 의 tower_radius·lake_radius·summit_radius; `busy()` 에 veg.busy(); 패널에 stats)
- Modify: `scripts/core/locomotion.gd` 또는 `scripts/nodes/player.gd` — 등반 감지가 "no_climb" 그룹 충돌체를 벽으로 쓰지 않게 (WallRay 충돌 대상 확인 후 제외)
- Modify: `tools/screenshot.gd` — 시점 "forest" 추가 (활엽수림 안, 설계서 1장 4시점용)
- Test: `tests/unit/test_island_1km_veg.gd` (장면을 열고 몇 프레임 뒤 `stats().blocks > 0`, Terrain field 준비 후 생성)

- [ ] **Step 1: 실패 테스트 → FAIL 확인**
- [ ] **Step 2: 구현 → `./run_tests.sh` ALL PASSED**
- [ ] **Step 3: 측정** (커밋 안 하는 프로브): `tests/_perf_1km.gd` 를 4시점(스폰 (690,·,705) / 해안 마을 (430,·,735) / 숲 / 정상 (-60,·,-190))으로 — 그리기 호출 ≤ 250, 삼각형 ≤ 60만, step ≤ 3 ms. 넘으면 밀도·거리 수치를 줄이고 설계서 표를 고친다.
- [ ] **Step 4: 등반 검사** `tests/_probe_1km_sweep.gd` ≥ 95 %, flips 0. 스크린샷 (`tools/screenshot.gd -- veg r0,r100 island_1km`).
- [ ] **Step 5: 커밋·푸시** `feat(island): 첫 지역 식생·바위 연결`
