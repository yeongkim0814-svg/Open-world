class_name PlayerCombat
extends Node
## 플레이어 전투: 체력, 공격(3단 콤보·강공격·자동 조준), 방어/패링, 적 공격 판정 처리.
## Player가 매 물리 틱 tick()을 호출한다.

signal died

const ENEMY_DAMAGE_STUN := 1.0      ## 가드 브레이크 경직 (s)
const ATTACK_REACH := 1.8           ## 공격 판정 거리 (m)
const ATTACK_ARC_DEG := 120.0       ## 공격 판정 정면 각 (전체)
const LIGHT_COOLDOWN := 0.35
const HEAVY_COOLDOWN := 0.7
const FLURRY_COOLDOWN := 0.12       ## 슬로우모션 연타 중 공격 간격

@export var combat_tuning: CombatTuning = preload("res://resources/combat_tuning.tres")
@export var has_shield := false     ## M2: 디버그용. 장비 시스템은 이후

var hp: float
var guard: Guard
var flurry: Flurry
var state: CombatState
var last_result := ""               ## HUD 표시용: 패링! / 막기 / 가드 브레이크 / 피격 / 회피
var engaged_this_tick := false

var _player: Player
var _combo_step := 0
var _combo_timer := 0.0
var _cooldown := 0.0
var _stun := 0.0


func setup(player: Player) -> void:
	_player = player
	hp = combat_tuning.player_max_hp
	guard = Guard.new(combat_tuning)
	flurry = Flurry.new(combat_tuning)
	state = CombatState.new(combat_tuning)


func is_stunned() -> bool:
	return _stun > 0.0


func reset_hp() -> void:
	hp = combat_tuning.player_max_hp


func tick(intent: InputIntent, delta: float) -> void:
	engaged_this_tick = false
	guard.tick(delta)
	flurry.tick(delta)
	_stun = maxf(_stun - delta, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0:
		_combo_step = 0
	if intent.guard_pressed:
		guard.press()
	if not intent.guard_held and guard.holding:
		guard.release()
	if is_stunned() or _cooldown > 0.0:
		return
	if intent.heavy_released:
		_swing(combat_tuning.heavy_damage, HEAVY_COOLDOWN)
	elif intent.attack_pressed:
		_swing(combat_tuning.attack_damage, FLURRY_COOLDOWN if flurry.active else LIGHT_COOLDOWN)


## 적 공격이 맞는 순간 TrainingDummy가 호출.
func on_enemy_hit(attack: EnemyAttack, enemy: Node3D, damage: float) -> void:
	engaged_this_tick = true
	if _player.locomotion.is_invulnerable():
		last_result = "회피"
		return
	match guard.resolve(attack.parryable, has_shield):
		Guard.Result.PARRIED:
			last_result = "패링!"
			flurry.start()
			if enemy.has_method("stagger"):
				enemy.stagger()
		Guard.Result.BLOCKED:
			last_result = "막기"
			_player.stamina.spend(combat_tuning.guard_cost)
		Guard.Result.GUARD_BREAK:
			last_result = "가드 브레이크"
			_stun = ENEMY_DAMAGE_STUN
			_take_damage(damage)
		Guard.Result.HIT:
			last_result = "피격"
			_take_damage(damage)


func _take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		died.emit()


## 휘두르기: 적이 없어도 동작한다. 자동 조준 대상이 있으면 그쪽으로 즉시 돌아선다.
func _swing(damage: float, cooldown: float) -> void:
	engaged_this_tick = true
	_cooldown = cooldown
	_combo_step = (_combo_step % 3) + 1
	_combo_timer = combat_tuning.combo_window + cooldown
	var enemies := _alive_enemies()
	var positions: Array[Vector3] = []
	for e in enemies:
		positions.append(e.global_position)
	var origin := _player.global_position
	var target := Targeting.pick(origin, _player.facing_forward(), positions, combat_tuning.target_range, combat_tuning.target_cone_deg)
	if target != -1:
		_player.face_toward(positions[target])
	_player.play_swing(_combo_step, damage > combat_tuning.attack_damage)
	var fwd := _player.facing_forward()
	for e in enemies:
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		if to.length() <= ATTACK_REACH and fwd.angle_to(to) <= deg_to_rad(ATTACK_ARC_DEG) * 0.5:
			e.take_hit(damage)


func _alive_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(func(e): return e.is_alive())
