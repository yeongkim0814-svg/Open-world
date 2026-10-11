# 첫 섬 교체 A — 색칠 지도 → 1km 지형 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 색칠 지도 PNG 4장을 구워 1024m 섬(구역 LOD 지형·충돌·바다·저수호)을 만들고, 초안 지도와 그리기 안내서를 제공한다.

**Architecture:** 순수 계산(색 판정·띠 → 높이·표식·도장·굽기·청크 메시·LOD)은 `scripts/core/map/`, `scripts/core/terrain/`의 노드 비의존 클래스로 TDD. 도구(`tools/bake_map.gd`, `tools/draft_first_island.gd`)는 이들을 묶는 얇은 껍데기. 게임은 구운 결과만 읽는 `ChunkedTerrain` 노드로 1km를 구역 단위 LOD로 그린다.

**Tech Stack:** Godot 4.7.2, GDScript, Compatibility 렌더러, `./run_tests.sh`, `tools/shots.sh`.

**Spec:** `docs/superpowers/specs/2026-10-12-painted-map-terrain-design.md`

## Global Constraints

- 맵 1024m × 1024m, 중심 = 원점, 이미지 좌상 = (−512, −512), x 오른쪽, z 아래(남쪽) — 기존 `HeightField` 좌표 관례.
- 범례 색·목표 높이·표식 색은 설계서 3장 그대로. 판정 = 가장 가까운 범례색, RGB 거리(0~255 기준 유클리드) > 60 또는 흰색·투명(α < 128) = 비어 있음.
- 구운 높이: RGB8 16비트(R 상위·G 하위), 범위 −16 ~ 90m, 1024×1024.
- 저수호 도장 = M4 수치: 반경 48m, 바닥 −6m, 둑 꼭대기 16m (둑 폭 약 10m), 탑 섬 윗면 18m. 마을 반경 40m 평지.
- LOD: 64m 구역, 거리 < 160m → 1m, < 480m → 4m, 그 밖 → 16m. 프레임당 메시 생성 ≤ 4ms. 충돌 = 플레이어 주변 3×3 구역, 1m.
- 예산: 그리기 호출 < 150, 삼각형 < 30만. 기존 테스트 전부 유지, `first_island.tscn` 무변경.
- 굽기·생성 모두 결정적. 한국어 주석·`class_name`·탭.

## Review Focus

1. **지도 이미지가 1024가 아님 / 정사각형 아님:** 1024로 맞추고, 정사각형이 아니면 오류 메시지(경로·크기)로 굽기 중단 → Task 1 `test_resize_and_reject_non_square`.
2. **흐린 펜 경계(중간색 픽셀):** 두 범례색 사이 픽셀은 가까운 쪽, 문턱 밖은 비어 있음 → Task 1 `test_blended_edge_pixels`.
3. **절벽 선이 끊겨 있음(작은 틈):** 틈으로 평활화가 새어 절벽이 무너지지 않게 선을 2px 팽창 → Task 2 `test_cliff_line_with_gap_still_steep`.
4. **표식이 없음 / 같은 종류 여러 개:** 탑·저수호·시작 위치가 없으면 굽기 오류, 수문은 최대 3(넘으면 경고 후 앞 3개) → Task 3 `test_required_markers`.
5. **구역 LOD 경계 틈:** 1m 구역 옆 4m 구역 경계에서 틈이 보이지 않음(치마 깊이 ≥ 인접 높이 차) → Task 5 `test_skirt_covers_lod_seam`.

---

### Task 1: 범례·이미지 판정 (`MapLegend`)

**Files:** Create `scripts/core/map/map_legend.gd` · Test `tests/unit/test_map_legend.gd`

**Interfaces — Produces:** `class_name MapLegend`
- `const HEIGHT := [{"color": Color8(...), "name": "deep_sea", "h": -12.0}, ...]` (설계서 3.1 순서), `const CLIFF := Color8(0xE0,0x21,0x8A)`
- `const ZONES := [...]` (3.2 순서, 인덱스 0 = 초원), `const PATHS := [...]` (3.3, 인덱스 1부터; 0 = 없음), `const MARKERS := {"start": Color, "tower": ..., "lake": ..., "sluice": ..., "village": ..., "ruin": ..., "lookout": ..., "bridge": ...}`
- `static func classify(c: Color, palette: Array[Color]) -> int` (가장 가까운 인덱스, 비어 있음 = −1)
- `static func load_layer(img: Image, palette: Array[Color], size := 1024) -> PackedInt32Array` (크기 맞춤은 nearest, 정사각형 아니면 `push_error` 후 빈 배열)

- [ ] **Step 1: 실패 테스트** — `test_exact_colors_classify`, `test_white_and_transparent_are_empty`, `test_blended_edge_pixels` (Review 2: 두 색 50:50 → 둘 중 하나, 문턱 밖 회색 → −1), `test_resize_and_reject_non_square` (Review 1: 256² → 1024² 길이, 300×200 → 빈 배열)
- [ ] **Step 2~4:** FAIL → 구현 → ALL PASSED · **Step 5:** 커밋 `feat(map): 색칠 지도 범례·색 판정`

### Task 2: 띠 → 높이 (`HeightBands`)

**Files:** Create `scripts/core/map/height_bands.gd` · Test `tests/unit/test_height_bands.gd`

**Interfaces — Consumes:** `MapLegend.load_layer`, `MapLegend.HEIGHT`, `MapLegend.CLIFF`. **Produces:** `class_name HeightBands` — `static func build(bands: PackedInt32Array, size: int, cliff: PackedByteArray, smooth_radius := 12.0, detail := 1.5, seed := 1) -> PackedFloat32Array` (m, 행 우선). 순서: 빈칸 = 가장 가까운 칠한 칸(BFS) → 가장자리 32px 깊은 바다 → 절벽 선 2px 팽창(장벽) → 장벽을 넘지 않는 반복 상자 평활화(3회, 반경 합 ≈ smooth_radius) → 저주파 굴곡(바다·절벽 6m 이내 0).

- [ ] **Step 1: 실패 테스트** — `test_band_targets` (평지만 → 모두 4±1.5), `test_empty_filled_from_nearest`, `test_edge_is_deep_sea` (가장자리 −12), `test_smooth_between_bands` (평지|언덕 경계에서 경사 < 30°), `test_cliff_line_keeps_wall_steep` (평지|절벽선|고원 → 선 주변 3m 안 높이 차 ≥ 15m), `test_cliff_line_with_gap_still_steep` (Review 3: 선에 1px 틈 → 여전히 ≥ 12m)
- [ ] **Step 2~4** · **Step 5:** 커밋 `feat(map): 높이 색 띠 → 높이 (평활화·절벽 장벽·굴곡)`

### Task 3: 표식·도장 (`MarkerReader`, `MapStamps`)

**Files:** Create `scripts/core/map/marker_reader.gd`, `scripts/core/map/map_stamps.gd` · Test `tests/unit/test_markers_stamps.gd`

**Interfaces — Produces:**
- `class_name MarkerReader` — `static func read(img: Image, size := 1024, world := 1024.0) -> Array[Dictionary]` (`{kind: String, x: float, z: float, yaw: float}`; 이어진 같은 색 덩어리(4방향) 중심; yaw = 마을·저수호 쪽, 없으면 0), `static func validate(markers: Array) -> PackedStringArray` (오류 목록: 시작·탑·저수호 필수, 수문 > 3 경고)
- `class_name MapStamps` — `static func apply(h: PackedFloat32Array, size: int, world: float, markers: Array) -> void` (저수호: 반경 48 분지 바닥 −6, 반경 48~58 둑 꼭대기 16, 바깥 비탈 18m에 걸쳐 원지형으로; 탑 섬: 반경 10 윗면 18 (저수호 안); 마을: 반경 40 평균 높이로 평평, 가장자리 15m 섞기)

- [ ] **Step 1: 실패 테스트** — `test_blob_centroid`, `test_yaw_faces_village`, `test_required_markers` (Review 4), `test_lake_stamp_numbers` (중심 −6, 반경 53 ≈ 16, 반경 30 −6), `test_tower_island_top`, `test_village_flattened` (반경 30 안 높이 편차 < 0.3)
- [ ] **Step 2~4** · **Step 5:** 커밋 `feat(map): 표식 읽기·저수호·탑 섬·마을 도장`

### Task 4: 굽기 (`MapBaker` + `tools/bake_map.gd`)

**Files:** Create `scripts/core/map/map_baker.gd`, `tools/bake_map.gd` · Test `tests/unit/test_map_baker.gd`

**Interfaces — Consumes:** Task 1~3. **Produces:**
- `class_name MapBaker` — `static func bake(layers: Dictionary, size := 1024, world := 1024.0) -> Dictionary` (`layers` = `{"height": Image, "zones": Image, "paths": Image, "markers": Image}`, 없는 장 허용(height·markers 제외); 반환 `{"height": PackedFloat32Array, "zones": PackedByteArray, "paths": PackedByteArray, "markers": Array, "errors": PackedStringArray}`). 길 효과: 흙길·포장길 → 길 방향 수직으로 2m 평균(최대 0.5m 변화), 수로 → 1.5m 파냄. 구역 비어 있음 = 초원(0).
- `static func encode_height(h: PackedFloat32Array, size: int) -> Image` (−16~90m → RGB8 16비트), `static func preview(baked: Dictionary, size: int) -> Image` (음영 + 구역색 + 길 + 표식 점, 512px)
- `tools/bake_map.gd -- <map>`: `res://maps/<map>/{height,zones,paths,markers}.png` → `res://maps/<map>/baked/{height.png, zones.png, paths.png, markers.json, preview.png}`; 오류가 있으면 출력 후 종료 코드 1.

- [ ] **Step 1: 실패 테스트** — `test_bake_deterministic`, `test_encode_roundtrip` (HeightField로 읽은 값 오차 < 0.01m), `test_path_dig_and_flatten`, `test_missing_required_layer_errors`
- [ ] **Step 2~4** · **Step 5:** 커밋 `feat(map): 굽기 (높이·구역·길·표식·미리보기)`

### Task 5: 청크 지형 (`TerrainLod`, `ChunkMesh`, `ChunkedTerrain`)

**Files:** Create `scripts/core/terrain/terrain_lod.gd`, `scripts/core/terrain/chunk_mesh.gd`, `scripts/nodes/chunked_terrain.gd` · Test `tests/unit/test_chunked_terrain.gd`

**Interfaces — Consumes:** 기존 `HeightField`. **Produces:**
- `class_name TerrainLod` — `const CHUNK := 64.0`, `static func step_for(dist: float) -> float` (1 / 4 / 16), `static func wanted(cam_xz: Vector2, world: float) -> Dictionary` (`Vector2i → step`, 전 구역)
- `class_name ChunkMesh` — `static func build(field: HeightField, origin: Vector2, size: float, step: float, skirt: float) -> ArrayMesh` (부드러운 법선 = `field.normal_at`, 테두리 치마 깊이 skirt)
- `class_name ChunkedTerrain extends Node3D` — `@export var baked_dir: String`, `var field: HeightField`, `@export var material: Material`, `func load_map() -> void`, `_process`: 카메라 기준 `wanted` 비교 → 대기열 → 프레임당 4ms까지 생성/교체; 충돌 3×3(`HeightMapShape3D`, 1m) 교체; `func stats() -> Dictionary` (`chunks`, `pending`, `last_build_ms`)
- [ ] **Step 1: 실패 테스트** — `test_step_for_distances`, `test_wanted_covers_world` (256 구역), `test_chunk_vertex_count` (64m/4m → 17² + 치마), `test_skirt_covers_lod_seam` (Review 5: 1m·4m 이웃 경계 최대 높이 차 ≤ 치마 깊이), `test_chunk_matches_field` (정점 높이 = height_at)
- [ ] **Step 2~4** · **Step 5:** 커밋 `feat(terrain): 1km 구역 LOD 지형 + 주변 충돌`

### Task 6: 초안 지도 (`tools/draft_first_island.gd`)

**Files:** Create `tools/draft_first_island.gd`, `maps/first_island/{height,zones,paths,markers}.png`, `maps/first_island/baked/*`

설계서 6장 배치로 1024² PNG 4장을 그린다(`MapLegend` 색만 사용, 다각형·선·원 칠하기). 실행: `godot --headless -s tools/draft_first_island.gd` → `godot --headless -s tools/bake_map.gd -- first_island` → 오류 0, `preview.png` 확인(시각). 커밋 `feat(map): 첫 섬 1km 초안 지도 + 굽기 결과`.

### Task 7: 지형 재질 구역·길 색 + 물

**Files:** Modify `shaders/style_terrain.gdshader` (`uniform sampler2D zone_map : filter_nearest`, `path_map`, `map_rect: vec4`; 구역별 땅 색 표 = `StylePalette`에 키 추가: `zone_<name>` 고갈/회복, 길 흙·돌), `scripts/core/style_palette.gd`, 테스트 `tests/unit/test_style_palette.gd`(새 키 채도 규칙 유지). 물: 바다 = `style_water`(`use_here`), 저수호 수면 = 기존 `Lake` 노드 + 스타일 물 재질.
- [ ] 팔레트 새 키 실패 테스트 → 구현 → 통과 · 커밋 `feat(gfx): 지형 구역·길 땅 색`

### Task 8: 시험 장면 · 탐침 · 측정

**Files:** Create `scripts/nodes/island_1km.gd`, `scenes/island_1km.tscn`; Modify `tools/screenshot.gd` (`island_1km` 시점: `start`, `lake`, `north`, `west`, `air`)
- 장면: 환경(style_env) · 해 · `ChunkedTerrain`(baked_dir) · 바다 · 저수호(도장 위치·`Lake`) · 회복 지도(섬 전체 지역, 슬라이더) · 플레이어(시작 표식) · 표식 디버그 기둥(색) · 디버그 패널(FPS·구역·대기열·생성 ms·삼각형).
- [ ] 헤드리스 실행 SCRIPT ERROR 0 · 탐침 `tests/_probe_1km_sweep.gd`(가파른 칸 표본 200, 성공 ≥ 95%, 깜빡임 0), 수영(저수호), 해안 → 산 걷기 · `tools/shots.sh i1 r0,r100 island_1km` + 미리보기 시각 검토 · 성능(그리기·삼각형·생성 ms) 기록
- [ ] 커밋 `feat(map): 1km 시험 장면 + 탐침`

### Task 9: 안내서 · 문서

**Files:** Create `docs/guides/map-painting.md` (설계서 7장), `docs/perf/island-1km-check.md` (태블릿 양식); Modify `docs/design/03-art-direction.md` 6장(다음) 갱신.
- [ ] 커밋·푸시 `docs: 색칠 지도 그리기 안내서 + 1km 확인 양식`

## 실행 순서

- 메인: Task 1 (범례 — 모두가 씀)
- 병렬 에이전트: **X** = Task 2 → 3 → 4 (지도 파이프라인), **Y** = Task 5 (청크 지형, HeightField만 의존)
- 메인(병렬): Task 6 초안 그리기(굽기는 X 병합 후) · Task 7
- 메인: 병합 → Task 6 굽기 → Task 8 → Task 9 → 최종 리뷰(opus)
