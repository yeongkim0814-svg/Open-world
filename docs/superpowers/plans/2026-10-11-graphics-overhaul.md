# 그래픽 개편 1차 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 첫 섬을 "도형"에서 "장소"로 — 광활한 하늘·공기 원근·원경, 텍스처 섞기 지형, 바람 부는 풀, 실사 재질 바위·구조물, 물 반사를 넣고, 회색↔컬러 회복 연출을 새 그래픽 전체에 적용한다. 태블릿 Forward+에서 평균 45 FPS 이상 유지.

**Architecture:** 그래픽 요소는 각자 독립 리소스·씬으로 만든다(`shaders/`, `scenes/env/`, `resources/env/`) → 마지막에 `first_island.tscn`에 연결. 그래서 하늘·풀·바위 작업을 서로 다른 에이전트가 **병렬**로 진행하고 씬 파일 충돌을 피한다. 회색↔컬러는 기존 전역 셰이더 변수 `vitality_center`/`vitality_radius`(+ 새 전역 `vitality_global`: 하늘·안개용 0~1)로 통일. 결과는 **헤드리스 스크린샷**(xvfb + lavapipe, Forward+)으로 찍어 눈으로 검증한다.

**Tech Stack:** Godot 4.7.2 Forward+, GDScript, spatial/sky 셰이더, MultiMesh, 자체 테스트 러너.

**Spec:** `docs/design/03-art-direction.md` v0.2 (특히 2·4·5·6·7·8·10장), `docs/superpowers/specs/2026-10-10-m4-first-island-design.md` 5.3(회복 연출)

## Global Constraints

- 렌더러 Forward+, 태블릿 하한 **평균 45 FPS** (장면 4곳: 마을·둑 위·탑 꼭대기·정지 순간). 효과는 단계마다 측정.
- 예산: 화면당 삼각형 약 50만, 풀 2~4만 덩어리, 그림자 빛 1개(거리 약 80m), 텍스처 1K.
- 색: 회복 후 하늘 `#3E7FC4`→지평선 `#BFD6EA`, 풀 `#8CC63F`/`#4E8F2A`, 흰 뭉게구름 (03 설계서 4장). 회복 전 = 같은 장면의 채도 약 15% + 푸른 기, 흐린 납빛 하늘.
- 고채도 예외(생명력 빛·🟡🔴 신호·청록 코어)는 회색 처리 금지.
- 에셋은 **CC0만** (라이선스 파일 `assets/LICENSES.md`에 출처 기록). 저장소 증가분 100MB 이하.
- 게임 규칙·충돌은 바꾸지 않는다 (지형 해상도를 올려도 등반 스윕 99% 유지).

## Review Focus

1. **회복 전 화면이 그냥 "어두운 버전"이 되는 것:** 잿빛 세계도 형태·깊이가 읽혀야 한다 → 각 작업의 스크린샷 쌍(회복 전/후) 검토.
2. **노출 과다/과소:** 현재 장면은 하얗게 날아가 있다 → Task 1에서 톤매핑·노출 기준값을 고정하고 이후 작업은 바꾸지 않는다.
3. **풀·지형 해상도 상승으로 등반·이동이 깨짐:** 높이 지도 512 + 1m 격자 후 등반 스윕·경로 탐침 재실행 → Task 2.
4. **타일 반복이 보이는 텍스처:** 넓은 초원에서 같은 무늬 반복 → Task 2 스크린샷(둑 위 전경)으로 확인.
5. **태블릿 FPS 급락:** 단계별 측정 양식 → Task 6.

---

## 에이전트 운용 (중요도 · 토큰 효율)

| 작업 | 중요도 | 담당 | 모델 | 병렬 그룹 |
|---|---|---|---|---|
| 0. 에셋 확보·스크린샷 도구 | 기반 | 메인(직접) | — | 먼저 단독 |
| 1. 하늘·대기·원경·노출 | ★★★ (광활함 최대 효과, 비용 최소) | 구현 에이전트 A | opus (셰이더 판단) | **그룹 1** |
| 3. 풀 | ★★ | 구현 에이전트 B | sonnet (규격 명확) | **그룹 1** |
| 4a. 바위 생성기 | ★★ | 구현 에이전트 C | sonnet | **그룹 1** |
| 2. 지형 셰이더·512 높이 지도 | ★★★ | 구현 에이전트 D | opus | 그룹 2 (1 이후 — 노출 기준 필요) |
| 4b. 구조물 재질 + 연결 | ★★ | 메인 | — | 그룹 2 이후 |
| 5. 물 | ★ | 구현 에이전트 E | sonnet | 그룹 2와 병렬 |
| 시각 검토 | 각 그룹 끝 | 검토 에이전트 | opus | — |
| 최종 코드 리뷰 | 1회 | 리뷰 에이전트 | opus | — |

**토큰 절약 규칙:**
- 각 에이전트는 **자기 작업의 파일만** 읽는다: 브리프에 경로·인터페이스·값을 다 적어 저장소 탐색을 막는다.
- 결과는 독립 리소스·씬으로 받아, 씬 파일(`first_island.tscn`) 연결은 메인이 한 번에 한다. 병렬 충돌 0.
- 스크린샷은 **고정 시점 4장**(마을·둑 위·탑 꼭대기·서쪽 고원)만, 회복 전/후 쌍 = 최대 8장. 검토 에이전트만 이미지를 본다. 메인은 판정 요약만 받는다.
- 수치 튜닝 반복(밝기·색)은 구현 에이전트 안에서 스크린샷으로 끝낸다. 메인 컨텍스트로 이미지를 가져오지 않는다.
- 에이전트 보고는 "바뀐 파일 / 측정값 / 스크린샷 경로 / 남은 문제" 10줄 이내로 요구.

---

### Task 0: 에셋 확보 · 스크린샷 도구 (메인)

**Files:** Create `tools/screenshot.gd`, `tools/shots.sh`, `assets/LICENSES.md`, `assets/textures/terrain/…`

**Interfaces:**
- Produces: `tools/shots.sh <tag>` → `/tmp/claude-0/shots/<tag>_{village,dam,tower,plateau}_{grey,color}.png` (1280×720, Forward+, xvfb). 시점(위치·yaw·pitch)은 스크립트에 고정. `--recovered`면 `vitality_radius=1e5`, `vitality_global=1`.
- Produces: 지형 텍스처 4세트 `assets/textures/terrain/{grass,dirt,rock,sand}_{diff,nor,arm}.jpg` (1K, CC0).

- [ ] **Step 1:** 스크린샷 도구 (`tests/_shot.gd` 검증된 방식 → `tools/screenshot.gd`로 정식화, 시점 4곳 + 회복 전/후).
- [ ] **Step 2: 텍스처 확보 (우선순위):**
  1. 사용자가 환경 네트워크 허용 목록에 `dl.polyhaven.org`, `api.polyhaven.com` 추가 → Polyhaven CC0 1K (풀: `aerial_grass_rock`/`grass_path_2` 계열, 흙, 바위: `rock_face`/`cliff_side` 계열, 모래) 직접 받기
  2. 또는 사용자가 태블릿 Termux에서 `tools/fetch_textures.sh` 실행 → 커밋·푸시
  3. 둘 다 안 되면: **절차적 생성**(노이즈 기반 색·노멀·거칠기 텍스처, `tools/gen_textures.gd`) — 품질은 낮지만 막히지 않음
- [ ] **Step 3:** 기준 스크린샷 `before` 세트 촬영 (이후 비교 기준). 커밋 `chore: 스크린샷 도구·지형 텍스처(CC0)`

### Task 1: 하늘 · 대기 · 원경 · 노출 (에이전트 A, opus)

**Files:** Create `shaders/sky.gdshader`, `resources/env/first_island_env.tres`, `scenes/env/backdrop.tscn`(원경 산 링) · Modify `project.godot`(전역 셰이더 변수 `vitality_global`)

**Interfaces:**
- Produces: `sky.gdshader` — 절차적 하늘: 높이 그라데이션 + **FBM 뭉게구름**(화면 위쪽 크게, 지평선 쪽 납작하게, 천천히 흐름) + 해 원반. `global uniform float vitality_global` 0 = 흐림(납빛, 낮은 구름층 두껍게, 채도 낮음), 1 = 맑음(03 설계서 4장 색, 흰 뭉게구름). 하늘 radiance는 갱신 빈도 낮게(성능).
- Produces: `first_island_env.tres` — 톤매핑(ACES/Filmic 중 스크린샷 비교로 고정)·노출 기준값, SSAO·SSIL·글로우, 거리 안개(공기 원근: 하늘 지평선 색), 높이 안개, 약한 볼류메트릭 안개. 안개 색·밀도는 `vitality_global`에 맞춰 `FirstIsland`가 보간할 수 있게 두 세트(흐림/맑음) 값을 문서화.
- Produces: `backdrop.tscn` — 섬 밖 1~3km 산 능선 링(저폴리 메시 3겹, 거리별 안개에 녹음), 충돌 없음.
- `FirstIsland.stop_tower()`의 하늘 트윈은 `vitality_global` 0→1 트윈으로 교체(메인이 연결 시).

- [ ] **Step 1:** 구현 → `tools/shots.sh sky` 회복 전/후 촬영 → 03 설계서 4장 색·"하늘이 화면 절반 이상, 원경이 겹겹이" 기준으로 자체 조정 (최대 4회 반복).
- [ ] **Step 2:** `./run_tests.sh` ALL PASSED. 보고: 노출·톤매핑 값, 스크린샷 경로.
- [ ] **Step 3:** 커밋 `feat(gfx): 절차적 뭉게구름 하늘·공기 원근·원경 산·노출 기준`

### Task 3: 풀 (에이전트 B, sonnet) — 그룹 1 병렬

**Files:** Create `shaders/grass.gdshader`, `scripts/nodes/grass_field.gd`, `scenes/env/grass_field.tscn`, `tests/unit/test_grass_placement.gd`

**Interfaces:**
- Consumes: `HeightField`(높이·법선), 전역 `vitality_center/radius`.
- Produces: `GrassField` (Node3D) — `@export var terrain: Terrain`, `radius := 40.0`, `density := 6.0`(m²당), 카메라 주변 청크(8m) 단위 MultiMesh 재배치. 배치 규칙은 순수 함수 `GrassPlacement.points(field, chunk_origin, size, density, seed) -> PackedVector3Array`: 경사 30° 초과·물 아래·높이 2m 미만(모래)은 제외.
- `grass.gdshader`: 덩어리 카드(삼각형 3~6개), 뿌리 어둡게→끝 밝게, 바람(시간+위치 노이즈 굽힘), 역광, 거리 페이드. 회복 전 = 키 40%·누런 회색·바람 약함, 회복 후 = 키 100%·`#8CC63F`/`#4E8F2A`·흰 꽃 점 약간.

- [ ] **Step 1: 실패 테스트** — `test_points_skip_steep_and_water` (경사 45° 칸·물 아래 칸에 점 0개), `test_density_matches` (평지 8×8m·밀도 6 → 384±10%), `test_deterministic_with_seed`.
- [ ] **Step 2:** FAIL 확인 → 구현 → ALL PASSED.
- [ ] **Step 3:** 단독 시험 씬에서 스크린샷(회복 전/후) + 인스턴스 수·삼각형 수 보고.
- [ ] **Step 4:** 커밋 `feat(gfx): 바람 부는 풀(MultiMesh), 회복 전/후 변화`

### Task 4a: 바위 생성기 (에이전트 C, sonnet) — 그룹 1 병렬

**Files:** Create `tools/gen_rocks.gd`, `assets/meshes/rocks/rock_{1..5}.res`, `scenes/env/rock_scatter.gd`, `tests/unit/test_rock_scatter.gd`

**Interfaces:**
- Produces: 노이즈로 변형한 저폴리 바위 메시 5종(정점 400~1500, 부드러운 법선, 삼면 투영 UV 불필요 — 재질이 삼면 투영). 충돌 = 단순 볼록 모양.
- Produces: `RockScatter` (Node3D) — `@export var terrain: Terrain`, 규칙 순수 함수 `RockScatter.points(field, seed, count) -> Array[Transform3D]`: 경사 35~70° 가장자리(둑 바깥·협곡·산·고원 가장자리) 우선, 길·수문·마을 반경 15m 제외, 크기 1~6m.
- 바위 재질 = Task 2의 지형 셰이더 바위 층과 같은 텍스처(삼면 투영), 회색↔컬러 동일.

- [ ] **Step 1: 실패 테스트** — `test_rocks_avoid_village_and_sluices`, `test_rocks_prefer_slopes`(70% 이상이 경사 35° 이상 칸), `test_deterministic`.
- [ ] **Step 2:** 구현 → ALL PASSED → 등반 스윕 재실행(바위가 길을 막지 않는지, 바위 자체도 오를 수 있는지).
- [ ] **Step 3:** 커밋 `feat(gfx): 절차적 바위 5종·경사 가장자리 배치`

### Task 2: 지형 셰이더 · 512 높이 지도 (에이전트 D, opus) — 그룹 2

**Files:** Modify `tools/gen_first_island.gd`(512, 침식 느낌 FBM 디테일), `assets/terrain/first_island.png`, `scripts/core/terrain_mesh.gd`(부드러운 법선·격자 1m), `scripts/nodes/terrain.gd` · Create `shaders/terrain.gdshader`

**Interfaces:**
- Consumes: Task 0 텍스처, Task 1 노출 기준(바꾸지 않음).
- `terrain.gdshader`: 4층(풀·흙·바위·모래) 섞기 = 경사(바위, 삼면 투영) · 높이(모래, 물가) · 저주파 노이즈(풀/흙 얼룩) + 높이 기반 경계(Spaceship `GroundBase` 방식). 두 배율 섞기로 타일 반복 숨김. 노멀·ORM 적용. 회색↔컬러 = `vitality` 공용 함수(셰이더 include로 분리: `shaders/vitality.gdshaderinc`, 기존 `vitality.gdshader`도 이걸 쓰도록).
- 높이 지도 512: 기존 지형 요소·좌표·높이는 그대로(설계서 4장, 기존 지도 테스트 통과), 그 위에 진폭 0.5~2m FBM 디테일(평지 굴곡·절벽 결). 지형 메시 1m 격자(약 18만 삼각형), 충돌은 2m 유지 가능(등반 스윕으로 결정).

- [ ] **Step 1:** 기존 테스트(`test_first_island_map`, `test_terrain`) + 새 테스트 `test_smooth_normals`(인접 정점 법선 공유) FAIL→PASS.
- [ ] **Step 2:** 등반 스윕(`tests/_probe_climb_sweep.gd`) 99% 이상, 경로·탑·저수호 탐침 통과 (Review Focus 3).
- [ ] **Step 3:** 스크린샷 회복 전/후 — 타일 반복(Review Focus 4), 노출 유지 확인.
- [ ] **Step 4:** 커밋 `feat(gfx): 512 높이 지도·부드러운 지형·텍스처 섞기 셰이더`

### Task 5: 물 (에이전트 E, sonnet) — 그룹 2와 병렬

**Files:** Create `shaders/water.gdshader` · Modify `scenes/first_island.tscn`의 바다·저수호 재질만 (메인이 연결 시 교체)

**Interfaces:**
- 깊이에 따른 색(얕음 청록 → 깊음 짙은 청), 노멀 두 장 흐름(절차적 노이즈), 하늘 반사(프레넬, 하늘 radiance), 물가 거품 띠(깊이 차). 회색↔컬러: 회복 전 탁한 청회색·반사 약함 → 회복 후 03 설계서 색.
- [ ] **Step 1:** 구현 → 저수호·바다 스크린샷 → 커밋 `feat(gfx): 물 셰이더(깊이 색·반사·물가 거품)`

### Task 4b: 구조물 재질 · 씬 연결 (메인)

**Files:** Modify `scenes/first_island.tscn`, `scenes/tower.tscn`, `scenes/sluice.tscn`, `scenes/machine_*.tscn`, `scripts/nodes/first_island.gd`

- [ ] **Step 1:** 둑길·돌기둥·수문·탑·집·바위벽에 돌/금속 삼면 투영 재질(지형 셰이더의 바위 층 재사용) + `vitality` 회색 처리. 건물 상자 모서리 경사(bevel 메시로 교체).
- [ ] **Step 2:** 하늘·풀·바위·물·원경을 `first_island.tscn`에 연결, `stop_tower()`에서 `vitality_global` 트윈 + 안개 두 세트 보간.
- [ ] **Step 3:** 전체 테스트·모든 탐침 통과, 스크린샷 `after` 세트.
- [ ] **Step 4:** 커밋 `feat(gfx): 구조물 재질·그래픽 요소 연결·회복 연출 통합`

### 시각 검토 (검토 에이전트, opus) — 그룹 1 끝, 최종

- 입력: 03 설계서 2~5장, `before`/현재 스크린샷 쌍, 컨셉 이미지 설명(광활함·색감). 출력: 항목별 판정(광활함·노출·회복 전 가독성·색 일치·반복 무늬) + 고칠 값 제안 5개 이내.

### Task 6: 태블릿 측정 (사용자) · 최종 리뷰

- [ ] `docs/perf/gfx-overhaul-check.md`: 장면 4곳 FPS·발열, 회복 전/후 인상, 풀·하늘·지형 체감.
- [ ] 45 미만이면 끄는 순서: 볼류메트릭 안개 → SSIL → 풀 밀도 → 지형 1m→2m.
- [ ] 최종 코드 리뷰 (opus, 1회).
