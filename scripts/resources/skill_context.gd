class_name SkillContext
extends RefCounted

# Typed bundle for a single skill cast. Replaces the loose
# `setup_with_mods(dir, dmg, mods)` triple: instead of every skill scene digging
# magic-string keys out of a Dictionary (`mods.get("caster")`,
# `mods.get("visual_only")`, ...), the caster hands the scene one SkillContext
# with typed fields plus the per-skill `mods` for the handful of tuning keys.
#
# Migration is incremental and SAFE: scenes implement `setup_context(ctx)` when
# converted, but `SkillContext.apply()` still falls back to the legacy
# `setup_with_mods` / `setup_meteor` / `setup` for any scene not yet migrated, so
# the tree stays green at every step. NetSync replication and sub-projectile
# spawns route through the same dispatcher.

enum NetMode { LOCAL, VISUAL_REMOTE }  # cast by THIS client — authoritative, applies damage  # replicated copy on a peer — visual only, no damage

var caster: Node = null
var direction: Vector2 = Vector2.RIGHT
# The aim point in world space (mouse_world). Skills could only derive a
# direction before; the actual target position is now available for skills that
# want to land AT the cursor (telegraphs, ground effects).
var target_pos: Vector2 = Vector2.ZERO
var damage: int = 0
var is_visual_only: bool = false
var net_mode: int = NetMode.LOCAL
# Slot-swap transform id ("" when none) — e.g. "ice_wall", "bone_spear".
var transform: String = ""
# On-hit status elements granted by skill-tree status nodes ("fire"/"bleed"/
# "frost"/"poison"/"curse"). Applied to enemies this cast hits via apply_on_hit().
var on_hit: Array = []
# Per-skill tuning keys the scene reads (duration_stacks, pierce, radius_stacks,
# jumps_bonus, ...). Everything that isn't promoted to a typed field above.
var mods: Dictionary = {}
# The resolved SkillDefinition for this cast. Set by SkillCaster / NetSync so the
# generic composed-skill runner can read `definition.effects`. May be null for
# legacy direct sub-spawns that don't go through the catalog.
var definition: SkillDefinition = null


# Build a context from the legacy mods dict. Used during migration so both the
# new SkillCaster path and old sub-spawn call sites converge on one shape.
static func from_mods(
	dir: Vector2, dmg: int, mods_in: Dictionary, target: Vector2 = Vector2.INF
) -> SkillContext:
	var ctx := SkillContext.new()
	ctx.direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	ctx.damage = dmg
	var m: Dictionary = mods_in if mods_in != null else {}
	ctx.caster = m.get("caster", null)
	ctx.is_visual_only = bool(m.get("visual_only", false))
	ctx.net_mode = NetMode.VISUAL_REMOTE if ctx.is_visual_only else NetMode.LOCAL
	ctx.transform = String(m.get("transform", ""))
	ctx.on_hit = m.get("on_hit", [])
	ctx.target_pos = target if target != Vector2.INF else ctx.direction  # best-effort
	# Keep the full dict as `mods` so per-skill keys still resolve via ctx.mods.
	ctx.mods = m
	return ctx


# Rebuild the legacy mods dict for dispatch to a not-yet-migrated scene. Mirrors
# the typed fields back into their string keys so old `setup_with_mods` bodies see
# exactly what they saw before.
func to_mods() -> Dictionary:
	var m: Dictionary = mods.duplicate()
	m["caster"] = caster
	m["visual_only"] = is_visual_only
	m["transform"] = transform
	return m


func get_mod(key: String, default_value: Variant = 0) -> Variant:
	return mods.get(key, default_value)


# Apply this cast's tree-granted on-hit statuses to a freshly-hit enemy. Reuses
# enemy.gd's status API (apply_burn/apply_bleed/apply_chill/apply_poison/
# add_curse_stack). Host-authoritative — skipped on the visual-only remote copy.
func apply_on_hit(target: Node) -> void:
	if is_visual_only or on_hit.is_empty() or target == null or not is_instance_valid(target):
		return
	if bool(target.get("dead")):
		return
	var dps: float = maxf(2.0, float(damage) * 0.15)
	for el in on_hit:
		match String(el):
			"fire":
				if target.has_method("apply_burn"):
					target.call("apply_burn", 4.0, dps)
			"bleed":
				if target.has_method("apply_bleed"):
					target.call("apply_bleed", 4.0, dps)
			"frost":
				if target.has_method("apply_chill"):
					target.call("apply_chill", 3.0, 1)
			"poison":
				if target.has_method("apply_poison"):
					target.call("apply_poison", 1, 5.0, dps * 0.7)
			"curse":
				if target.has_method("add_curse_stack"):
					target.call("add_curse_stack")


# Central dispatcher. Prefers the new typed entry; falls back to the legacy
# contract so migrated and un-migrated scenes coexist. Returns true if some setup
# method was found and invoked.
static func apply(node: Node, ctx: SkillContext) -> bool:
	if node.has_method("setup_context"):
		node.call("setup_context", ctx)
		return true
	if node.has_method("setup_with_mods"):
		node.call("setup_with_mods", ctx.direction, ctx.damage, ctx.to_mods())
		return true
	if node.has_method("setup_meteor"):
		node.call("setup_meteor", ctx.damage, ctx.to_mods())
		return true
	if node.has_method("setup"):
		node.call("setup", ctx.direction, ctx.damage)
		return true
	return false
