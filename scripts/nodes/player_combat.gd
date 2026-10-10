class_name PlayerCombat
extends Node
## 플레이어 전투: 체력, 무기(근접·활·교체·내구도), 공격(3단 콤보·강공격·자동 조준), 방어/패링, 적 공격 판정 처리.
## Player가 매 물리 틱 tick()을 호출한다.

signal died

const ENEMY_DAMAGE_STUN := 1.0      ## 가드 브레이크 경직 (s)
const FLURRY_COOLDOWN := 0.12       ## 슬로우모션 연타 중 공격 간격
const WEAPON_BLOCK_LEAK := 0.3      ## 방패 없이 무기로 막으면 피해의 30%가 들어옴 (3.3)

@export var combat_tuning: CombatTuning = preload("res://resources/combat_tuning.tres")
@export var has_shield := false     ## M2: 디버그용. 장비 시스템은 이후

var hp: float
var guard: Guard
var flurry: Flurry
var state: CombatState
var arsenal: Arsenal
var last_result := ""               ## HUD 표시용: 패링! / 막기 / 가드 브레이크 / 피격 / 회피
var engaged_this_tick := false

var _player: Player
var _combo_step := 0
var _combo_timer := 0.0
var _cooldown := 0.0
var _stun := 0.0
var _draw: BowDraw                  ## 장착한 활의 당기기 상태 (활이 아니면 null)


func setup(player: Player) -> void:
	_player = player
	hp = combat_tuning.player_max_hp
	guard = Guard.new(combat_tuning)
	flurry = Flurry.new(combat_tuning)
	state = CombatState.new(combat_tuning)
	var weapons: Array[WeaponData] = [
		preload("res://resources/weapons/sword.tres"),
		preload("res://resources/weapons/greatsword.tres"),
		preload("res://resources/weapons/bow.tres"),
	]
	arsenal = Arsenal.new(weapons)


func is_drawing() -> bool:
	return _draw != null and _draw.drawing


func is_stunned() -> bool:
	return _stun > 0.0


## 쓰러진 뒤 재시작: 체력·경직·방어·연타·콤보를 모두 초기화.
func reset() -> void:
	hp = combat_tuning.player_max_hp
	_stun = 0.0
	_cooldown = 0.0
	_combo_step = 0
	_combo_timer = 0.0
	if _draw:
		_draw.cancel()
	guard = Guard.new(combat_tuning)
	flurry = Flurry.new(combat_tuning)


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
	if intent.switch_weapon_pressed:
		switch_weapon()
	var w := arsenal.current()
	if w.kind == WeaponData.Kind.BOW:
		_tick_bow(w, intent, delta)
		return
	if is_stunned() or _cooldown > 0.0:
		return
	if intent.heavy_released:
		_swing(w, true, w.heavy_cooldown)
	elif intent.attack_pressed:
		_swing(w, false, FLURRY_COOLDOWN if flurry.active else w.light_cooldown)


## 다음 무기로 교체. 콤보는 처음부터.
func switch_weapon() -> void:
	if _draw:
		_draw.cancel()          # 당기던 화살은 쏘지 않는다
	arsenal.cycle()
	_draw = BowDraw.new(arsenal.current()) if arsenal.current().kind == WeaponData.Kind.BOW else null
	_combo_step = 0
	_combo_timer = 0.0


## 활: 누르고 있으면 당기고, 떼면 발사 (C18). 한 틱보다 짧은 탭도 최소 비율로 발사.
func _tick_bow(w: WeaponData, intent: InputIntent, delta: float) -> void:
	if _draw == null:
		_draw = BowDraw.new(w)
	if is_stunned():
		_draw.cancel()
		return
	var released := intent.attack_pressed or intent.heavy_released
	if not _draw.drawing and _cooldown <= 0.0 and (intent.attack_held or released):
		_draw.start()
	_draw.tick(delta)
	if _draw.drawing and (released or not intent.attack_held):
		_fire(w, _draw.release())


func _fire(w: WeaponData, ratio: float) -> void:
	engaged_this_tick = true
	_cooldown = w.light_cooldown
	var dmg := w.damage * ratio
	if arsenal.durability().is_broken():
		dmg *= combat_tuning.broken_damage_mult
	arsenal.durability().wear(combat_tuning.wear_hit)
	_player.fire_arrow(Hit.make(dmg), w.arrow_speed * lerpf(0.5, 1.0, ratio))


## 근접 무기 한 번의 피해. 파손이면 broken_damage_mult, 대검 강공격은 적의 공격을 끊는다.
func melee_hit(weapon: WeaponData, heavy: bool) -> Hit:
	var dmg := weapon.heavy_damage if heavy else weapon.damage
	if arsenal.durability().is_broken():
		dmg *= combat_tuning.broken_damage_mult
	return Hit.make(dmg, weapon.armor_pierce, heavy and weapon.heavy_staggers)


## 적 공격(근접 일격·탄)이 닿는 순간 호출. source = 공격한 적 또는 탄 — 패링되면 source.on_parried().
func on_enemy_hit(parryable: bool, source: Node3D, damage: float) -> void:
	engaged_this_tick = true
	if _player.locomotion.is_invulnerable():
		last_result = "회피"
		return
	var stamina := _player.stamina
	var can_afford := not stamina.exhausted and stamina.value >= combat_tuning.guard_cost
	match guard.resolve(parryable, has_shield, can_afford):
		Guard.Result.PARRIED:
			last_result = "패링!"
			flurry.start()
			if not has_shield:
				arsenal.durability().wear(combat_tuning.wear_parry)
			if source.has_method("on_parried"):
				source.on_parried()
		Guard.Result.BLOCKED:
			last_result = "막기"
			stamina.spend(combat_tuning.guard_cost)
			if not has_shield:
				arsenal.durability().wear(combat_tuning.wear_block)
				_take_damage(damage * WEAPON_BLOCK_LEAK)
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
func _swing(weapon: WeaponData, heavy: bool, cooldown: float) -> void:
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
	_player.play_swing(_combo_step, heavy)
	var fwd := _player.facing_forward()
	var hit := melee_hit(weapon, heavy)
	var landed := false
	for e in enemies:
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		if to.length() <= weapon.reach and fwd.angle_to(to) <= deg_to_rad(weapon.arc_deg) * 0.5:
			e.take_hit(hit)
			landed = true
	if landed:          # 허공 휘두르기는 닳지 않는다
		arsenal.durability().wear(combat_tuning.wear_hit)


func _alive_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(func(e): return e.is_alive())
