extends Node2D

# Battlemage ascension (R) — Arcane Flameblade. Empowers the mage's melee for 20s
# with a damage + speed buff and a flash of fire. Full design (melee-range bonus,
# +2% shield per hit on a burning enemy up to 30%, optional fire wave every 3rd
# hit) lands in a follow-up increment; this is the working core.
# Self-buff only — no collision, so the multiplayer visual-only copy is harmless
# (remote peers get a null caster and just skip the buff).

const BUFF_DURATION: float = 20.0
const DMG_MULT: float = 1.35
const SPD_MULT: float = 1.1


func setup_context(ctx: SkillContext) -> void:
	var caster = ctx.caster
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", BUFF_DURATION, DMG_MULT, SPD_MULT)
	# Open the Flameblade window — empowers melee, ignites foes, and turns hits on
	# burning enemies into a shield (see player._flameblade_melee_proc).
	if caster and caster.has_method("start_flameblade"):
		caster.call("start_flameblade", BUFF_DURATION)
	if VfxManager:
		var pos: Vector2 = (
			(caster as Node2D).global_position if caster is Node2D else global_position
		)
		VfxManager.spawn_hit_sparks(pos, Color(1.0, 0.5, 0.2, 1), 16)
		VfxManager.screen_flash(Color(1.0, 0.55, 0.25, 0.18), 0.2)
	queue_free()
