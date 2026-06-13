class_name Skill
extends Node2D

# Optional base for skill scenes. ADDITIVE: existing skills keep `extends Node2D`
# and work unchanged — this just gives NEW (and opportunistically-migrated) skills
# the common context plumbing + targeting / on-hit helpers so they don't re-derive
# the SkillContext boilerplate in every file.
#
# The caster path (SkillCaster / NetSync, via SkillContext.apply) calls
# setup_context(ctx); the default here stores ctx + damage + visual-only, then
# calls the `_on_context_ready()` virtual. A subclass overrides that virtual and
# reads `damage` / `_ctx` / the helpers — no per-file `var damage` / `var _ctx`.
# A subclass that needs custom setup can still override setup_context() directly.

var _ctx: SkillContext = null
var damage: int = 0
var _visual_only: bool = false


# Caster entry point. Stores the typed context, then hands off to the virtual.
func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	damage = ctx.damage
	_visual_only = ctx.is_visual_only
	_on_context_ready()


# Override in subclasses instead of re-implementing setup_context. `_ctx`,
# `damage` and `_visual_only` are populated by the time this runs.
func _on_context_ready() -> void:
	pass


# Nearest live enemy to `from` (defaults to this skill's position) within range.
func nearest(from: Vector2 = Vector2.INF, range_max: float = INF, exclude: Dictionary = {}) -> Node2D:
	var origin: Vector2 = global_position if from == Vector2.INF else from
	return SkillTargeting.nearest(get_tree(), origin, range_max, exclude)


# All live enemies within `radius` of `from` (defaults to this skill's position).
func in_radius(radius: float, from: Vector2 = Vector2.INF, exclude: Dictionary = {}) -> Array:
	var origin: Vector2 = global_position if from == Vector2.INF else from
	return SkillTargeting.in_radius(get_tree(), origin, radius, exclude)


# Apply this cast's tree-granted on-hit statuses (fire/bleed/frost/poison/curse)
# to a freshly-hit enemy. No-op on the visual-only remote copy (handled by ctx).
func apply_on_hit(target: Node) -> void:
	if _ctx != null:
		_ctx.apply_on_hit(target)
