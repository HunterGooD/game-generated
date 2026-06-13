class_name SkillEffectGroupCall
extends SkillEffect

# Calls a method on every node of a group (e.g. buff all "necro_minion" via
# apply_blood_pact, or all "pet_ally"). `skip_if_visual` is false by default to
# match the old bespoke scripts (which ran the group loop regardless of the
# visual-only copy); set it true for host-authoritative effects that must not
# double-apply on a replicated cast.

@export var group: String = ""
@export var method: String = ""
@export var args: Array = []
@export var skip_if_visual: bool = false
# 0 = whole group (no distance filter, original behaviour). > 0 restricts to
# group members within `radius` of the host (cast point) — covers radius-gated
# party buffs like the druid's Barkskin Aura. Filtered members must be Node2D.
@export var radius: float = 0.0


func execute(ctx: SkillContext, host: Node2D) -> void:
	if group == "" or method == "":
		return
	if skip_if_visual and ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var center: Vector2 = host.global_position if host != null else Vector2.ZERO
	for n in tree.get_nodes_in_group(group):
		if not is_instance_valid(n) or not n.has_method(method):
			continue
		if radius > 0.0:
			if not (n is Node2D) or center.distance_to((n as Node2D).global_position) > radius:
				continue
		n.callv(method, args)


static func from_data(d: Dictionary) -> SkillEffectGroupCall:
	var e := SkillEffectGroupCall.new()
	e.group = String(d.get("group", ""))
	e.method = String(d.get("method", ""))
	e.args = d.get("args", [])
	e.skip_if_visual = bool(d.get("skip_if_visual", false))
	e.radius = float(d.get("radius", 0.0))
	return e
