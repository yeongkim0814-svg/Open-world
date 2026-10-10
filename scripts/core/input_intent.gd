class_name InputIntent
extends RefCounted
## 장치(터치·키보드·패드)와 무관한 한 틱의 입력 의도.

var move := Vector2.ZERO        ## 길이 ≤ 1, x = 오른쪽, y = 앞
var sprint := false
var jump_pressed := false       ## 이번 틱에 눌림
var jump_held := false
var camera_yaw := 0.0           ## 라디안. 이동 방향을 카메라 기준으로 돌릴 때 사용
