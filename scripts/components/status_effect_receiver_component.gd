class_name StatusEffectReceiverComponent
extends Node


@export var main_stats: StatsComponent
@export var health_component: HealthComponent

var current_effects: Dictionary[StringName, StatusEffectInstance] = {}


func _process(delta: float) -> void:
	for effect_id in current_effects.keys().duplicate():
		var instance: StatusEffectInstance = current_effects[effect_id]
		instance.remaining_time -= delta

		match instance.definition.effect_type:
			StatusEffectResource.EffectType.DOT:
				_process_dot(instance, delta)
			StatusEffectResource.EffectType.SPEED:
				pass
			StatusEffectResource.EffectType.MAX_HP:
				pass

		if instance.remaining_time <= 0.0:
			_remove_effect(effect_id)


func apply_effects(effects: Array[StatusEffectResource], damage: DamageInstance) -> void:
	for effect_resource in effects:
		apply_effect(effect_resource, damage)


func apply_effect(effect_def: StatusEffectResource, damage: DamageInstance) -> void:
	if effect_def == null:
		return

	match effect_def.effect_type:
		StatusEffectResource.EffectType.SPEED:
			_apply_speed(effect_def, damage)
		StatusEffectResource.EffectType.DOT:
			_apply_dot(effect_def, damage)
		StatusEffectResource.EffectType.MAX_HP:
			_apply_max_hp(effect_def, damage)


func _apply_speed(effect_def: StatusEffectResource, _damage: DamageInstance) -> void:
	if main_stats == null:
		return

	var effect_id := effect_def.id
	var source_id := StringName("status:%s:%s" % [str(effect_id), str(get_instance_id())])
	var instance := _get_or_create_instance(effect_def, null, source_id)

	if effect_def.max_stacks >= 0:
		instance.stacks = mini(instance.stacks, effect_def.max_stacks)

	var stack_multiplier := float(instance.stacks)
	var modifier_value: float
	if effect_def.speed_type == StatusEffectResource.SpeedType.POSITIVE:
		modifier_value = 1.0 + (effect_def.speed_percent * stack_multiplier)
	else:
		modifier_value = max(0.05, 1.0 - (effect_def.speed_percent * stack_multiplier))

	main_stats.remove_modifiers_by_source(source_id)
	main_stats.add_modifier(
		StatModifierInstance.new(
			StatEnums.StatType.MOVE_SPEED,
			StatEnums.Mode.MULTIPLY,
			modifier_value,
			source_id,
			[&"status", &"speed"],
		)
	)


func _apply_dot(effect_def: StatusEffectResource, damage: DamageInstance) -> void:
	var effect_id := effect_def.id
	var source_id := StringName("status:%s:%s" % [str(effect_id), str(get_instance_id())])
	var instance := _get_or_create_instance(effect_def, damage, source_id)
	instance.source_damage = damage

	if effect_def.max_stacks >= 0:
		instance.stacks = mini(instance.stacks, effect_def.max_stacks)


func _apply_max_hp(effect_def: StatusEffectResource, _damage: DamageInstance) -> void:
	if main_stats == null:
		return

	var effect_id := effect_def.id
	var source_id := StringName("status:%s:%s" % [str(effect_id), str(get_instance_id())])
	var instance := _get_or_create_instance(effect_def, null, source_id)

	if effect_def.max_stacks >= 0:
		instance.stacks = mini(instance.stacks, effect_def.max_stacks)

	main_stats.remove_modifiers_by_source(source_id)
	main_stats.add_modifier(
		StatModifierInstance.new(
			StatEnums.StatType.MAX_HEALTH,
			StatEnums.Mode.FLAT,
			effect_def.max_hp_delta * float(instance.stacks),
			source_id,
			[&"status", &"max_hp"],
		)
	)


func _process_dot(instance: StatusEffectInstance, delta: float) -> void:
	instance.tick_timer += delta
	if instance.tick_timer < instance.definition.tick_interval:
		return

	instance.tick_timer = 0.0
	if health_component == null:
		return

	var tick_damage := instance.definition.damage_per_stack * float(instance.stacks)
	var source_damage := instance.source_damage
	var attacker := source_damage.attacker if source_damage != null else null
	var tags: Array[StringName] = [
		StringName(StatusEffectResource.DOTType.keys()[instance.definition.dot_type].to_lower()),
		&"damage_over_time",
	]
	var dot_damage := DamageInstance.new(tick_damage, attacker, self, tags, [])
	health_component.apply_damage(dot_damage)


func _remove_effect(effect_id: StringName) -> void:
	if not current_effects.has(effect_id):
		return

	var instance: StatusEffectInstance = current_effects[effect_id]
	if main_stats != null and not String(instance.source_id).is_empty():
		main_stats.remove_modifiers_by_source(instance.source_id)

	current_effects.erase(effect_id)


func _get_or_create_instance(
	effect_def: StatusEffectResource,
	damage: DamageInstance,
	source_id: StringName
) -> StatusEffectInstance:
	var effect_id := effect_def.id
	var instance: StatusEffectInstance
	if current_effects.has(effect_id):
		instance = current_effects[effect_id]
		instance.stacks += 1
		instance.remaining_time = effect_def.duration
	else:
		instance = StatusEffectInstance.new(effect_def, damage, source_id)
		current_effects[effect_id] = instance
	return instance
