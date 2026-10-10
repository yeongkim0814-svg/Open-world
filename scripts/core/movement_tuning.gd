class_name MovementTuning
extends Resource
## 이동 관련 모든 튜닝 수치. 실제 값은 resources/movement_tuning.tres 에서 조정한다.

@export_group("속도")
@export var walk_speed := 4.0
@export var run_speed := 6.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var gravity := 20.0
@export var climb_speed := 2.0
@export var glide_fall_speed := 2.0
@export var glide_speed := 8.0

@export_group("스태미나")
@export var stamina_max := 100.0
@export var stamina_regen := 25.0
@export var stamina_regen_delay := 1.0
@export var sprint_cost := 20.0
@export var climb_cost := 10.0
@export var climb_jump_cost := 20.0
@export var glide_cost := 8.0
@export var exhausted_recover_ratio := 0.3

@export_group("안전")
@export var fall_respawn_y := -50.0
