class_name StatModifierInstance
extends RefCounted


var stat_type: StatEnums.StatType
var mode: StatEnums.Mode
var value: float
var source_id: StringName = &""
var tags: Array[StringName] = []


func _init(
	_stat_type: StatEnums.StatType,
	_mode: StatEnums.Mode,
	_value: float,
	_source_id: StringName = &"",
	_tags: Array[StringName] = []
) -> void:
	stat_type = _stat_type
	mode = _mode
	value = _value
	source_id = _source_id
	tags = _tags.duplicate()
