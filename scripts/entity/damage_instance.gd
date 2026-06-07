class_name DamageInstance
extends RefCounted


var amount: float
var attacker: Node
var source: Node
var tags: Array[StringName]
var status_effects: Array[StatusEffectResource]
var crit: bool
var knockback: Vector2
var is_stealth: bool


func _init(
	_amount: float,
	_attacker: Node,
	_source: Node,
	_tags: Array[StringName] = [],
	_status_effects: Array[StatusEffectResource] = [],
	_crit: bool = false,
	_knockback: Vector2 = Vector2.ZERO,
	_is_stealth: bool = false
) -> void:
	amount = _amount
	attacker = _attacker
	source = _source
	tags = _tags.duplicate()
	status_effects = _status_effects.duplicate()
	crit = _crit
	knockback = _knockback
	is_stealth = _is_stealth
