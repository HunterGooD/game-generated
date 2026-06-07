class_name HealthComponent
extends Node


signal hp_change(hp: float, max_hp: float)
signal dead(damage_payload: DamageInstance)


@export var main_stats: StatsComponent

var max_hp: float = 0.0
var current_hp: float = 0.0
var is_dead: bool = false
var invulnerable: bool = false
var history_damage_taken: Array[DamageInstance] = []


func _ready() -> void:
	if main_stats == null:
		push_warning("main_stats is not set in HealthComponent")
		return

	max_hp = max(1.0, main_stats.get_max_health())
	current_hp = max_hp
	main_stats.stats_changed.connect(_on_stats_changed)
	hp_change.emit(current_hp, max_hp)


func apply_damage(damage_payload: DamageInstance) -> void:
	if is_dead or invulnerable or damage_payload == null:
		return

	if main_stats == null:
		return

	var damage := _apply_armor(damage_payload.amount)
	if damage <= 0.0:
		return

	current_hp = clampf(current_hp - damage, 0.0, max_hp)
	history_damage_taken.append(damage_payload)
	hp_change.emit(current_hp, max_hp)

	if current_hp <= 0.0:
		is_dead = true
		dead.emit(damage_payload)


func apply_heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return

	current_hp = clampf(current_hp + amount, 0.0, max_hp)
	hp_change.emit(current_hp, max_hp)


func set_invulnerable(value: bool) -> void:
	invulnerable = value


func revive(health_fraction: float = 1.0) -> void:
	is_dead = false
	current_hp = clampf(max_hp * health_fraction, 1.0, max_hp)
	hp_change.emit(current_hp, max_hp)


func _apply_armor(amount: float) -> float:
	var armor: float = main_stats.get_armor() if main_stats != null else 0.0
	return max(0.0, amount - armor)


func _on_stats_changed() -> void:
	var new_max_hp: float = max(1.0, main_stats.get_max_health())
	if is_equal_approx(new_max_hp, max_hp):
		return

	current_hp = clampf(current_hp + (new_max_hp - max_hp), 0.0, new_max_hp)
	max_hp = new_max_hp
	hp_change.emit(current_hp, max_hp)
