class_name WeaponData
extends Resource
## 무기 1종의 수치 (02 설계서 4.3). 새 무기 = resources/weapons/ 에 .tres 추가.

enum Kind { MELEE, BOW }

@export var display_name := ""
@export var kind := Kind.MELEE

@export_group("근접")
@export var damage := 10.0              ## 활: 완전히 당겼을 때 피해
@export var heavy_damage := 25.0
@export var light_cooldown := 0.35      ## 활: 발사 간격
@export var heavy_cooldown := 0.7
@export var reach := 1.8                ## 공격 판정 거리 (m)
@export var arc_deg := 120.0            ## 공격 판정 정면 각 (전체)
@export var armor_pierce := false       ## 장갑 무시
@export var heavy_staggers := false     ## 강공격이 적의 공격을 끊음

@export_group("내구도")
@export var durability := 40.0

@export_group("활")
@export var draw_time := 0.6            ## 완전히 당기는 데 걸리는 시간 (s)
@export var min_draw_ratio := 0.3       ## 짧게 탭했을 때 피해 비율
@export var arrow_speed := 45.0
