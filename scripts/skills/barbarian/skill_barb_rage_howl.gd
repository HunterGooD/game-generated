extends Node2D

# Rage Howl — Berserker transform of Battle Cry (slot 2). Instead of a defensive
# shout it is an aggressive one: restores the Barbarian's resource (mana/rage) and
# has a 50% chance to make each nearby enemy Bleed.

const RADIUS: float = 240.0
const MANA_RESTORE: float = 35.0
const BLEED_CHANCE: float = 0.5

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.3, Color(0.85, 0.2, 0.15, 1))
		VfxManager.screen_shake(4.0, 0.2)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_battlecry.mp3", -6.0)
	if not visual_only:
		if GameManager and GameManager.has_method("regen_mana"):
			GameManager.regen_mana(MANA_RESTORE)
		var tree := get_tree()
		if tree:
			for e in SkillTargeting.in_radius(tree, global_position, RADIUS):
				if randf() < BLEED_CHANCE and e.has_method("apply_bleed"):
					e.call("apply_bleed", 4.0, float(damage) * 0.4)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)
