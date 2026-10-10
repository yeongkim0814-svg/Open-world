class_name CombatTuning
extends Resource
## 전투 관련 모든 튜닝 수치. 실제 값은 resources/combat_tuning.tres 에서 조정한다.

@export_group("전투 상태")
@export var combat_enter_dist := 15.0
@export var combat_exit_dist := 25.0
@export var combat_exit_delay := 3.0

@export_group("회피")
@export var dodge_speed := 8.0
@export var dodge_duration := 0.45
@export var dodge_iframes := 0.3
@export var dodge_cost := 15.0

@export_group("방어·패링")
@export var parry_window_weapon := 0.2
@export var parry_window_shield := 0.35
@export var parry_spam_window := 1.0     ## 이 시간 안에 다시 누르면 판정 창 축소
@export var parry_spam_shrink := 0.3     ## 재입력마다 창 30% 축소
@export var parry_min_ratio := 0.4       ## 창은 원래의 40% 아래로 줄지 않음
@export var guard_cost := 15.0           ## 막기 1회당 스태미나

@export_group("연타")
@export var flurry_duration := 1.5
@export var flurry_enemy_time_scale := 0.2

@export_group("카메라")
@export var camera_follow_deg_per_sec := 180.0
@export var camera_resume_delay := 0.5

@export_group("공격")
@export var target_range := 6.0
@export var target_cone_deg := 120.0
@export var heavy_hold_time := 0.4
@export var combo_window := 0.6
@export var player_max_hp := 100.0

@export_group("무기·내구도")
@export var broken_damage_mult := 0.25   ## 파손 무기 피해 배율
@export var weak_point_mult := 2.0       ## 약점(코어) 명중 배율
@export var wear_hit := 1.0              ## 적을 맞힐 때 (활은 발사마다)
@export var wear_block := 3.0            ## 무기로 막을 때
@export var wear_parry := 1.0            ## 무기로 패링할 때
@export var hit_stagger_time := 0.8      ## 대검 강공격에 맞은 적의 경직 (s)
@export var arrow_gravity := 6.0
@export var arrow_max_dist := 80.0
