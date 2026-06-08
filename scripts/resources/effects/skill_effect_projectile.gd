class_name SkillEffectProjectile
extends SkillEffect

# Launches one or more projectile scenes from the cast origin. Each projectile is
# instantiated, positioned `spawn_offset` from the origin along its own direction,
# set up via SkillContext.apply (so its bespoke scene script runs its movement /
# collision), and added to the scene. `count` (+ optional `count_modifier` upgrade
# stacks) projectiles are spread over `arc`: radial from RIGHT when not `aimed`, or
# a fan centred on ctx.direction when `aimed`. An optional `unique_meta` is stamped
# on each projectile when that unique item is equipped (e.g. venomweave daggers).
#
# Does NOT skip on the visual-only copy by default (matches the bespoke fan skills,
# whose remote copies still spawn projectiles with a null caster); set
# `skip_if_visual` for projectiles that must only fire on the authoritative cast.

@export var scene_path: String = ""
@export var count: int = 1
@export var count_modifier: String = ""  # ctx.mods key added to count
@export var arc: float = TAU             # TAU = full radial burst
@export var aimed: bool = false          # true: fan centred on ctx.direction
@export var spawn_offset: float = 24.0
@export var unique_meta: String = ""     # set this meta if the unique is equipped
@export var skip_if_visual: bool = false


func execute(ctx: SkillContext, host: Node2D) -> void:
	if skip_if_visual and ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var total: int = count
	if count_modifier != "":
		total += int(ctx.get_mod(count_modifier, 0))
	total = maxi(1, total)
	var stamp: bool = (
		unique_meta != ""
		and InventorySystem != null
		and InventorySystem.has_method("has_unique")
		and bool(InventorySystem.call("has_unique", unique_meta))
	)
	var origin: Vector2 = host.global_position
	var base_ang: float = ctx.direction.angle()
	for i in total:
		var ang: float
		if aimed:
			if total <= 1:
				ang = base_ang
			else:
				ang = base_ang - arc * 0.5 + arc * (float(i) / float(total - 1))
		else:
			ang = (float(i) / float(total)) * arc
		var dir := Vector2.RIGHT.rotated(ang)
		var p: Node2D = packed.instantiate()
		p.position = origin + dir * spawn_offset
		SkillContext.apply(p, SkillContext.from_mods(dir, ctx.damage, {"caster": ctx.caster}))
		if stamp and p.has_method("set_meta"):
			p.set_meta(unique_meta, true)
		tree.current_scene.add_child(p)


static func from_data(d: Dictionary) -> SkillEffectProjectile:
	var e := SkillEffectProjectile.new()
	e.scene_path = String(d.get("scene_path", ""))
	e.count = int(d.get("count", 1))
	e.count_modifier = String(d.get("count_modifier", ""))
	e.arc = float(d.get("arc", TAU))
	e.aimed = bool(d.get("aimed", false))
	e.spawn_offset = float(d.get("spawn_offset", 24.0))
	e.unique_meta = String(d.get("unique_meta", ""))
	e.skip_if_visual = bool(d.get("skip_if_visual", false))
	return e
