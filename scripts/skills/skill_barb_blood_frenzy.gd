extends Node2D

# Blood Frenzy — Berserker (Barbarian) ascension R. A 15s rage: faster attacks and
# movement, lifesteal on hit, but +15% damage taken. The offensive payoff comes
# from the Pain Engine passive (the lower the HP, the harder the hits). Kills near
# the Barbarian extend the frenzy (player._on_enemy_died_frenzy).

const FRENZY_DURATION: float = 15.0


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	var caster = mods.get("caster", null)
	if caster and caster.has_method("start_frenzy"):
		caster.call("start_frenzy", FRENZY_DURATION)
	if VfxManager:
		var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
		VfxManager.spawn_hit_sparks(pos, Color(0.9, 0.1, 0.12, 1), 20)
		VfxManager.screen_flash(Color(0.7, 0.05, 0.08, 0.22), 0.25)
		VfxManager.screen_shake(4.0, 0.2)
	queue_free()
