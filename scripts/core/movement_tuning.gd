class_name MovementTuning
extends Resource
## 이동 관련 모든 튜닝 수치. 실제 값은 resources/movement_tuning.tres 에서 조정한다.

@export_group("속도")
@export var walk_speed := 4.0
@export var run_speed := 7.0
@export var run_threshold := 0.6      ## 스틱을 이 비율 이상 밀면 달리기
@export var run_cone_deg := 100.0     ## 달리기는 스틱이 정면 이 각도(전체) 안일 때만. 옆·뒤는 항상 걷기
@export var jump_velocity := 5.0
@export var gravity := 20.0
@export var climb_speed := 2.0
@export var glide_fall_speed := 2.0
@export var glide_speed := 8.0

@export_group("스태미나")
@export var stamina_max := 100.0
@export var stamina_regen := 25.0
@export var stamina_regen_delay := 1.0
@export var run_cost := 10.0          ## 달리기(직접·자동) 초당 소모. 걷기는 0
@export var climb_cost := 10.0
@export var climb_jump_cost := 20.0
@export var glide_cost := 8.0
@export var exhausted_recover_ratio := 0.3

@export_group("등반")
@export var climb_grab_angle_deg := 40.0   ## 이동 방향과 벽 정면의 각이 이 이내일 때만 자동 등반

@export_group("안전")
@export var fall_respawn_y := -50.0
