class_name InputIntent
extends RefCounted
## 장치(터치·키보드·패드)와 무관한 한 틱의 입력 의도.

var move := Vector2.ZERO        ## 길이 ≤ 1, x = 오른쪽, y = 앞
var auto_run := false           ## 자동 달리기 고정 중 (카메라 정면으로 달림)
var camera_held := false        ## 오른손으로 시점 조작 중 → 걷기·달리기 시 바라보는 방향 유지
var jump_pressed := false       ## 이번 틱에 눌림
var jump_held := false
var in_combat := false          ## 전투 상태 (걷기도 이동 방향으로 회전)
var threatened := false         ## 근처 적이 공격 중(예고~공격 끝) → 스틱+점프 = 회피
var facing_yaw := 0.0           ## 캐릭터가 바라보는 방향 (회피 종류 판정용)
var attack_pressed := false     ## 공격 버튼 탭 (짧게 눌렀다 뗌)
var heavy_released := false     ## 공격 버튼을 heavy_hold_time 이상 누르다 뗌 → 강공격
var guard_pressed := false      ## 방어 버튼을 누른 순간 (패링 판정 시작)
var guard_held := false         ## 방어 버튼을 누르고 있음 (방어 자세)
var camera_yaw := 0.0           ## 라디안. 이동 방향을 카메라 기준으로 돌릴 때 사용
