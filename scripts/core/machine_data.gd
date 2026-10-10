class_name MachineData
extends Resource
## 수호 기계 1종의 수치 (02 설계서 5장). 새 기계 = resources/machines/ 에 .tres 추가.

@export var display_name := ""
@export var ranged := false

@export_group("몸체")
@export var max_hp := 100.0
@export var armor := 1.0                ## 받는 피해 배율 (1 = 장갑 없음). 장갑 관통 무기는 무시
@export var move_speed := 3.0

@export_group("판단")
@export var alert_range := 15.0
@export var attack_range := 2.2         ## 근접: 공격 거리 / 원거리: 최대 사격 거리
@export var keep_min := 0.0             ## 원거리: 이보다 가까우면 물러남
@export var leash := 25.0               ## 집에서 이만큼 멀어지면 경계를 풀고 귀환

@export_group("공격")
@export var damage := 20.0
@export var attack_interval := 1.4
@export var telegraph := 0.6
@export var active := 0.2
@export var recover := 0.9
@export var red_every := 3              ## N번째 공격마다 🔴 (패링 불가)
@export var shot_speed := 14.0          ## 원거리 🟡 탄 속도
@export var red_shot_speed := 20.0      ## 원거리 🔴 탄 속도

@export_group("보상·부활")
@export var part_drop := 1
@export var respawn_time := 30.0
