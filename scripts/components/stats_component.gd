class_name StatsComponent
extends Node


signal stats_changed


@export var base_stats: ActorStatsResource

var modifiers: Array[StatModifierInstance] = []


func add_modifier(modifier: StatModifierInstance) -> void:
	if modifier == null:
		return
	modifiers.append(modifier)
	stats_changed.emit()


func remove_modifiers_by_source(source_id: StringName) -> void:
	if String(source_id).is_empty():
		return

	var removed := false
	for idx in range(modifiers.size() - 1, -1, -1):
		if modifiers[idx].source_id == source_id:
			modifiers.remove_at(idx)
			removed = true

	if removed:
		stats_changed.emit()


func clear_modifiers() -> void:
	if modifiers.is_empty():
		return
	modifiers.clear()
	stats_changed.emit()


func get_stat(stat_id: StatEnums.StatType) -> float:
	var value := _get_base_value(stat_id)

	for modifier in modifiers:
		if modifier.stat_type == stat_id and modifier.mode == StatEnums.Mode.FLAT:
			value += modifier.value

	for modifier in modifiers:
		if modifier.stat_type == stat_id and modifier.mode == StatEnums.Mode.MULTIPLY:
			value *= modifier.value

	return value


func get_max_health() -> float:
	return get_stat(StatEnums.StatType.MAX_HEALTH)


func get_move_speed() -> float:
	return get_stat(StatEnums.StatType.MOVE_SPEED)


func get_armor() -> float:
	return get_stat(StatEnums.StatType.ARMOR)


func get_damage() -> float:
	return get_stat(StatEnums.StatType.DAMAGE)


func get_max_mana() -> float:
	return get_stat(StatEnums.StatType.MAX_MANA)


func get_mana_regen() -> float:
	return get_stat(StatEnums.StatType.MANA_REGEN)


func get_attack_speed() -> float:
	return get_stat(StatEnums.StatType.ATTACK_SPEED)


func get_crit_chance() -> float:
	return get_stat(StatEnums.StatType.CRIT_CHANCE)


func get_crit_damage() -> float:
	return get_stat(StatEnums.StatType.CRIT_DAMAGE)


func get_dash_charges() -> int:
	return max(0, int(round(get_stat(StatEnums.StatType.DASH_CHARGES))))


func _get_base_value(stat_id: StatEnums.StatType) -> float:
	if base_stats == null:
		return 0.0

	match stat_id:
		StatEnums.StatType.MAX_HEALTH:
			return base_stats.max_health
		StatEnums.StatType.MOVE_SPEED:
			return base_stats.move_speed
		StatEnums.StatType.ARMOR:
			return base_stats.armor
		StatEnums.StatType.DAMAGE:
			return base_stats.damage
		StatEnums.StatType.MAX_MANA:
			return base_stats.max_mana
		StatEnums.StatType.MANA_REGEN:
			return base_stats.mana_regen
		StatEnums.StatType.ATTACK_SPEED:
			return base_stats.attack_speed
		StatEnums.StatType.CRIT_CHANCE:
			return base_stats.crit_chance
		StatEnums.StatType.CRIT_DAMAGE:
			return base_stats.crit_damage
		StatEnums.StatType.DASH_CHARGES:
			return float(base_stats.dash_charges)
		_:
			return 0.0
