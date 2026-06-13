extends Node2D

# Coven Pact — Coven Mother (Hexen) R. Binds nearby allies for 12s: they share
# damage (modeled as damage reduction) and the caster leeches life from cursed foes
# (a shield trickle). In solo it just shields + sustains the Hexen.

const LIFETIME: float = 12.0
const RADIUS: float = 260.0
const TICK: float = 1.0

var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.4, Color(0.6, 0.1, 0.5, 1))


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	var tree := get_tree()
	if tree == null:
		return
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("apply_aura"):
				a.call("apply_aura", 1.0, 0.25, 0.4)  # 25% shared/mitigated
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		# Cursed foes nearby sustain the caster with a small shield.
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			if global_position.distance_to((e as Node2D).global_position) > RADIUS:
				continue
			if (e.has_meta("hex_marked") or int(e.get("curse_stacks")) > 0) and caster and caster.has_method("add_shield"):
				caster.call("add_shield", 6.0, -1.0)
