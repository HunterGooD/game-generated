extends Node2D

# Commanding Shout — Warchief transform of Battle Cry (slot 2). A protective roar:
# the Barbarian and nearby allies gain a shield. (The shout's "raise downed allies
# faster" rider is a planned follow-up.)

const RADIUS: float = 260.0
const SHIELD_FRAC: float = 0.18  # of caster max HP

var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.2, Color(0.5, 0.8, 1.0, 1))
		VfxManager.screen_shake(3.0, 0.18)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_battlecry.mp3", -6.0)
	if not visual_only:
		var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
		var shield: float = max_hp * SHIELD_FRAC
		var tree := get_tree()
		if tree:
			for grp in ["player", "remote_player"]:
				for a in tree.get_nodes_in_group(grp):
					if not is_instance_valid(a) or not (a is Node2D):
						continue
					if global_position.distance_to((a as Node2D).global_position) > RADIUS:
						continue
					if a.has_method("add_shield"):
						a.call("add_shield", shield, -1.0)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)
