# B2. 식생 "크게 적게" 개정 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 개별 풀 포기를 없애고 큰 나무·풀 덩어리·바위 무리·통나무로 바꾸며, 회복 0 상태에서 잎과 바위를 밝기·색온도·실루엣으로 구분한다.

**Architecture:** 기존 VegContext·VegPlacement·VegCatalog·VegetationField 구조를 유지하고 층 GRASS 를 PATCH 로 바꾼다(enum 이름은 유지해도 됨 — 의미만 "풀 덩어리"). 생성기에 풀 덩어리·꽃무리·통나무·그루터기 메시를 더하고, 셰이더·색표로 회복 0 구분과 초원 풀밭 질감을 만든다.

**Tech Stack:** Godot 4.7.2 GDScript, gl_compatibility, `./run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-10-13-vegetation-rocks-design.md` — **9장(B2 개정)이 3·4장보다 우선**.

## Global Constraints

- 9장 수치 그대로 (크기·밀도·거리·색 HEX).
- 성능: 4시점 그리기 호출 ≤ 250, 삼각형 ≤ 60만, 스트리밍 ≤ 3 ms (step 예산 2.5 ms 유지).
- 결정성·Compatibility(GLSL ES 3.0)·사진 텍스처 금지·한국어 주석 (기존과 같음).
- 등반 검사 ≥ 95 %.
- 커밋 꼬리: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_01PShdycDoYj1ffFPsLxdXpC`.

## Review Focus

1. 큰 나무 배율로 줄기 충돌·그림자 메시·LOD 메시가 같은 배율을 따르는지 (충돌 반경 = 줄기 × 배율 × 1.2).
2. 회복 0 ↔ 1 전환 중간값(0.5)에서도 잎이 바위보다 따뜻하고 밝은지 (색표 시험은 0 과 0.5 둘 다).
3. 풀 덩어리가 길·물 제외를 지키는지 (폭 3 m 메시라 중심만 검사하면 가장자리가 길에 걸침 — 중심 제외 반경을 덩어리 반지름만큼 넓힘).
4. 랜드마크 나무 5~8그루는 블록 단위 배치와 상관없이 지역 전체에서 결정적이어야 함 (블록 순서·스트리밍 위치에 따라 바뀌면 안 됨).
5. 지형 셰이더 결 얼룩이 멀리서 반짝이지 않는지 (40 m 밖 끔).

---

### Task 1: 생성기·색표·셰이더 (풀 덩어리·꽃무리·통나무·그루터기, 회복 0 구분, 풀밭 질감)

**Files:** Modify `scripts/core/gen/grass_gen.gd` (PATCH·FLOWER_PATCH), `scripts/core/gen/tree_gen.gd` (LOG·STUMP, 또는 새 `scripts/core/gen/debris_gen.gd`), `scripts/core/gen/rock_gen.gd` (윗면 표시: 법선 y > 0.6 면의 정점색 채널 하나 = 1), `scripts/core/style_palette.gd` (9.2 HEX: foliage·trunk·rock·moss·ground 회복 0/1), `shaders/style_foliage.gdshader` (회복 0 수관 오그라뜨림 15 %, 줄기색 분리), 바위용 셰이더(style_lit 에 moss 혼합 옵션 또는 새 `shaders/style_rock.gdshader`), `shaders/style_terrain.gdshader` (9.3 풀밭 질감 — 초원 구역만, 40 m 밖 결 얼룩 끔). Tests: `tests/unit/test_grass_gen.gd`, `tests/unit/test_tree_gen.gd` 또는 `test_debris_gen.gd`, `tests/unit/test_style_palette.gd`, `tests/unit/test_rock_gen.gd`.

**Interfaces — Produces:**
- `GrassGen.Kind.PATCH`, `GrassGen.Kind.FLOWER_PATCH` (기존 enum 끝에 추가), `GrassGen.build(kind, variant := 0)` 그대로.
- 통나무·그루터기: `DebrisGen.build(seed: int, kind: int) -> ArrayMesh` with `enum Kind { LOG, STUMP }` (또는 TreeGen 확장 — 하나만 고르고 보고).
- `RockGen.build` 결과 정점색에 윗면 표시 (어느 채널인지 보고).
- StylePalette 새 키: `"trunk"`, `"moss"`, 그리고 바뀐 `"foliage"`·`"rock"`·`"ground"`(초원 땅 회복 0) 값.

- [ ] 실패 테스트: 메시 삼각형 상한 (풀 덩어리 ≤ 120, 꽃무리 ≤ 200, 통나무·그루터기 ≤ 60), 풀 덩어리 AABB 폭 1.4~3.2 / 높이 0.5~1.3 (기본 배율), 결정성; 색표 — 회복 0 과 0.5 에서 잎·바위 상대 밝기 차 ≥ 12 %, 잎 R > B, 바위 B ≥ R; 바위 윗면 표시 정점 비율 15~60 %.
- [ ] FAIL 확인 → 구현 → `./run_tests.sh` ALL PASSED. 셰이더는 실제 렌더러로 컴파일 확인: `xvfb-run -a godot --rendering-driver opengl3 --rendering-method gl_compatibility --quit-after 60 scenes/style_test.tscn 2>&1 | grep -i "shader\|error"` (오류 없음).
- [ ] 커밋 `feat(gen): 풀 덩어리·꽃무리·통나무·그루터기, 회복 0 잎·바위 구분 색, 초원 풀밭 질감`

### Task 2: 배치·카탈로그·스트리밍 개정 (9.1)

**Files:** Modify `scripts/core/veg/veg_placement.gd`, `scripts/core/veg/veg_catalog.gd`, `scripts/nodes/vegetation_field.gd` (층 거리·LOD 0~300 / 280~1200·그리기 칸 크기 재조정), `scripts/core/veg/veg_context.gd` (제외 반경을 개체 반지름만큼 넓히는 인자 필요 시). Tests: `tests/unit/test_veg_placement.gd`, `tests/unit/test_veg_catalog.gd`, `tests/unit/test_vegetation_field.gd`.

**Interfaces — Consumes:** Task 1 메시·색표. **Produces:** `VegPlacement.mesh_ids()` 에 개별 풀 포기 id 없음; 새 id `"patch_<0..2>"`, `"flowers_<0..1>"`, `"log_<0..1>"`, `"stump_<0..1>"`; 나무 항목 `size` = 실제 배율(2.6~3.4, 랜드마크 4.5~5.5); 랜드마크는 `static func landmarks(ctx, world_seed) -> Array[Vector2]` (지역 전체 결정적, 블록과 무관 — Review Focus 4).

- [ ] 실패 테스트 (9.5 배치 항목 전부 + Review Focus 1·3·4): 숲 나무 최근접 ≥ 8 m, 랜드마크 5~8 & 서로 ≥ 250 m & 두 번 호출 같음, 바위 무리마다 큰 바위 1, 평지 노두 PILLAR 0, 풀 포기 id 0, 풀 덩어리 60 % 이상이 나무·바위·길·숲 가장자리 근처, 풀 덩어리 가장자리(중심 + 반지름)가 길 1.5 m 안에 들지 않음, 나무 충돌 반경 = 줄기 × size × 1.2.
- [ ] FAIL 확인 → 구현 → ALL PASSED.
- [ ] 커밋 `feat(veg): 크게 적게 — 큰 나무·랜드마크·풀 덩어리·바위 무리·통나무`

### Task 3: 장면 측정·조정·스크린샷

**Files:** 수치 조정만 (Task 2 파일, 설계서 9장 표), `tools/screenshot.gd` (필요 시 시점).

- [ ] 성능 프로브 4시점 (스폰 (690,·,705) / 해안 마을 (430,·,735) / 숲 (-620,·,80) / 정상 (-60,·,-190)), 4방향 최악: 그리기 호출 ≤ 250, 삼각형 ≤ 60만, step p99 ≤ 3 ms. 넘으면 수치를 줄이고 설계서 9장을 고친다.
- [ ] 스크린샷 r0·r100 (`tools/screenshot.gd -- b2 r0,r100 island_1km`) — 회복 0 에서 나무·바위 구분, 개별 풀 포기 없음, 큰 나무 실루엣, 공중에 뜬 물체 없음을 눈으로 확인하고 고친다.
- [ ] 등반 검사 ≥ 95 % (백그라운드, 약 20 분).
- [ ] 커밋·푸시 `feat(veg): B2 장면 조정`
