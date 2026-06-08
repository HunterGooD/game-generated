class_name SkillEffectVfx
extends SkillEffect

# Cosmetic burst at the cast point: hit sparks + optional screen flash + shake.
# Plays for both the local cast and the multiplayer visual-only copy (the old
# bespoke scripts did the same), so remote peers see the effect. A part is skipped
# when its driving value is zero (sparks_count == 0 / flash_time <= 0 / shake_time
# <= 0), so an effect can do just sparks, just a flash, etc.

@export var sparks_color: Color = Color(1, 1, 1, 1)
@export var sparks_count: int = 0
@export var flash_color: Color = Color(1, 1, 1, 0)
@export var flash_time: float = 0.0
@export var shake_strength: float = 0.0
@export var shake_time: float = 0.0


func execute(ctx: SkillContext, host: Node2D) -> void:
	if VfxManager == null:
		return
	var pos: Vector2 = host.global_position
	if ctx.caster is Node2D:
		pos = (ctx.caster as Node2D).global_position
	if sparks_count > 0:
		VfxManager.spawn_hit_sparks(pos, sparks_color, sparks_count)
	if flash_time > 0.0:
		VfxManager.screen_flash(flash_color, flash_time)
	if shake_time > 0.0:
		VfxManager.screen_shake(shake_strength, shake_time)


static func from_data(d: Dictionary) -> SkillEffectVfx:
	var e := SkillEffectVfx.new()
	e.sparks_color = d.get("sparks_color", Color(1, 1, 1, 1))
	e.sparks_count = int(d.get("sparks_count", 0))
	e.flash_color = d.get("flash_color", Color(1, 1, 1, 0))
	e.flash_time = float(d.get("flash_time", 0.0))
	e.shake_strength = float(d.get("shake_strength", 0.0))
	e.shake_time = float(d.get("shake_time", 0.0))
	return e
