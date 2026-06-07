class_name StatusEffectResource
extends Resource


enum EffectType {
	SPEED,
	DOT,
	MAX_HP,
}


enum DOTType {
	FIRE,
	POISON,
	ICE,
	CURSED,
}


enum SpeedType {
	NEGATIVE,
	POSITIVE,
}


@export var id: StringName = &""
@export var effect_type: EffectType = EffectType.SPEED
@export var duration: float = 1.0

@export_group("Speed")
@export var speed_percent: float = 0.0
@export var speed_type: SpeedType = SpeedType.NEGATIVE

@export_group("Damage Over Time")
@export var damage_per_stack: float = 0.0
@export var tick_interval: float = 1.0
@export var max_stacks: int = -1
@export var dot_type: DOTType = DOTType.POISON

@export_group("Max HP")
@export var max_hp_delta: float = 0.0
