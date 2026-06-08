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


func execute(ctx: SkillContext, _host: Node2D) -> void:
	if group == "" or method == "":
		return
	if skip_if_visual and ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n in tree.get_nodes_in_group(group):
		if is_instance_valid(n) and n.has_method(method):
			n.callv(method, args)


static func from_data(d: Dictionary) -> SkillEffectGroupCall:
	var e := SkillEffectGroupCall.new()
	e.group = String(d.get("group", ""))
	e.method = String(d.get("method", ""))
	e.args = d.get("args", [])
	e.skip_if_visual = bool(d.get("skip_if_visual", false))
	return e
