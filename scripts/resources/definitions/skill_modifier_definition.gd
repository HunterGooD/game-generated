class_name SkillModifierDefinition
extends RefCounted

# Typed view of one entry in RewardData.SKILL_MODIFIERS — a passive skill tweak
# offered at level-up and surfaced as a skill-tree passive's name/desc.
# SKILL_MODIFIERS stays the authoring source; RewardData.find_modifier() returns
# a cached SkillModifierDefinition (the level-up offer pool accessors
# modifiers_for_class/uniques_for_class still hand out raw dicts, pending the
# level_up_choice offer-pipeline migration). Unknown id -> unknown() placeholder.

var id: String = ""
var slot: int = -1
var title: String = ""
var desc: String = ""
var rarity: String = "common"
var stack_bonus: String = ""


static func from_dict(d: Dictionary) -> SkillModifierDefinition:
	var m := SkillModifierDefinition.new()
	m.id = String(d.get("id", ""))
	m.slot = int(d.get("slot", -1))
	m.title = String(d.get("title", ""))
	m.desc = String(d.get("desc", ""))
	m.rarity = String(d.get("rarity", "common"))
	m.stack_bonus = String(d.get("stack_bonus", ""))
	return m


static func unknown(modifier_id: String) -> SkillModifierDefinition:
	var m := SkillModifierDefinition.new()
	m.id = modifier_id
	return m
