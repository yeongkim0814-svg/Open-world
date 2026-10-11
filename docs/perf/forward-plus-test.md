# Forward+ 렌더러 실험 (태블릿)

목적: S11 Ultra에서 Forward+ (SSAO·SSIL·볼류메트릭 안개·글로우)가 쓸 만한 FPS로 도는지 확인 → 그래픽 방향(03 설계서) 결정.

## 준비
1. `cd ~/storage/shared/Open-world && git pull`
   - `project.godot` 충돌이 나면: `git diff project.godot` 확인 → 에디터 자동 변경뿐이면 `git checkout -- project.godot && git pull`
2. Godot 에디터를 **완전히 종료 후 다시 열기** (렌더러가 바뀌어 재시작 필요).
3. 실행 → 좌상단 HUD 첫 줄 `FPS 00 [forward_plus]` 확인. `[mobile]`이면 적용 안 된 것.

## 기록 (각 장면 30초, HUD 값)
| 장면 | 평균 FPS | 최악 ms | 발열 (상/중/하) |
|---|---|---|---|
| 마을에서 둑·탑 바라보기 |  |  |  |
| 둑 위에서 저수호 전경 |  |  |  |
| 탑 꼭대기에서 섬 전경 |  |  |  |
| 정지 순간 (입자 터짐) |  |  |  |

- 눈으로 본 차이 (안개·그림자·물체가 땅에 붙어 보이는지): ___
- 에디터 자체가 느려지거나 멈췄는가: ___

## 결과 (2026-10-11, 사용자 실측)
- 평균 FPS **48~78** (장면별 70후반~40후반) → **채택**. 지형 일부(둑 안쪽·바깥쪽 벽, 서쪽 수문 고원) 오르기 어려움 보고 → 별도 수정.

## 판정
- 평균 45+ → Forward+ 채택, 데모 수준 효과 사용
- 30~45 → Forward+ + 효과 일부 끄기(SSIL 먼저) 또는 해상도 스케일 조정
- 30 미만 / 실행 불가 → Mobile 복귀, 흉내 기법(구운 AO·하늘 이미지·안개)으로 진행

## 되돌리기 (문제가 생기면)
`project.godot`에서 `rendering_method="forward_plus"` → `"mobile"`, `rendering_method.mobile` 줄 삭제, `"Forward Plus"` → `"Mobile"` 후 에디터 재시작. 또는 저에게 말해 주세요.

기록 후: `git add docs/perf && git commit -m "perf: Forward+ 실험" && git push`
