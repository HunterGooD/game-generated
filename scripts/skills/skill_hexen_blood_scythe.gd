extends Node2D

# Blood Scythe — Blood Witch transform of Blood Whip. A wide melee sweep that hits
# harder against cursed / hex-marked foes.

const RADIUS: float = 170.0
const ARC_DOT: float = -0.2
const CURSE_BONUS: float = 0.4

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
# Scarlet Possession: the trance empowers the scythe exactly like the whip it
# replaced (low-HP bonus, HP cost, every-3rd-strike heal).
var _caster: Node = null
var _possessed: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	_caster = ctx.caster
	if _caster and _caster.has_method("is_possessed"):
		_possessed = bool(_caster.call("is_possessed"))
	if _possessed and _caster and _caster.has_method("possession_whip_mult"):
		damage = int(round(float(damage) * float(_caster.call("possession_whip_mult"))))
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()


func _ready() -> void:
	z_index = 50
	# Procedural blood slash (replaces the flat PNG arc).
	SlashFx.spawn(self, "blood", Vector2(90, 0), 1.0, 0.3)
	if not visual_only:
		_hit()
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _hit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var struck: int = 0
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var rel: Vector2 = (e as Node2D).global_position - global_position
		if rel.length() > RADIUS or direction.dot(rel.normalized()) < ARC_DOT:
			continue
		var dmg: int = damage
		if (e.has_meta("hex_marked")) or int(e.get("curse_stacks")) > 0:
			dmg = int(round(float(dmg) * (1.0 + CURSE_BONUS)))
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, global_position)
		if e.has_method("apply_bleed"):
			e.call("apply_bleed", 3.0, float(damage) * 0.3)
		struck += 1
	if _possessed and _caster and _caster.has_method("possession_on_whip"):
		_caster.call("possession_on_whip", struck)
