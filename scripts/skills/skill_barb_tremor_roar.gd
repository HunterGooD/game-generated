extends Node2D

# Tremor Roar — Titanbreaker transform of Battle Cry (slot 2). A seismic shout that
# sends out a shockwave: enemies are knocked back and slowed. Counts as control
# (feeds Seismic Momentum).

const RADIUS: float = 280.0
const KNOCKBACK: float = 320.0
const SLOW_DURATION: float = 2.5
const SLOW_MULT: float = 0.55

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.6, Color(0.7, 0.5, 0.3, 1))
		VfxManager.screen_shake(7.0, 0.3)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_battlecry.mp3", -5.0)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var ep: Vector2 = (e as Node2D).global_position
				if global_position.distance_to(ep) > RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, global_position)
				if e.has_method("apply_slow"):
					e.call("apply_slow", SLOW_DURATION, SLOW_MULT)
				if e.has_method("set"):
					(e as Node2D).set("velocity", (ep - global_position).normalized() * KNOCKBACK)
				if caster and caster.has_method("notify_control_applied"):
					caster.call("notify_control_applied")
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)
