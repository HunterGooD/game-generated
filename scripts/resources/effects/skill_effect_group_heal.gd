class_name SkillEffectGroupHeal
extends SkillEffect

# Heals every node of a group within `radius` of the cast origin by `heal_frac` of
# that target's own max_hp (reads/writes the `hp` / `max_hp` properties). Used by
# rally-style skills that mend the caster's minions. Skipped on the visual-only
# remote copy (the host owns minion HP).

@export var group: String = ""
@export var radius: float = 200.0
@export var heal_frac: float = 0.25  # of each target's max_hp


func execute(ctx: SkillContext, host: Node2D) -> void:
	if ctx.is_visual_only or group == "":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var origin: Vector2 = host.global_position
	for m in tree.get_nodes_in_group(group):
		if not is_instance_valid(m) or not (m is Node2D):
			continue
		if origin.distance_to((m as Node2D).global_position) > radius:
			continue
		var mhp: int = int(m.get("hp"))
		var mmax: int = int(m.get("max_hp"))
		m.set("hp", mini(mmax, mhp + int(round(float(mmax) * heal_frac))))


static func from_data(d: Dictionary) -> SkillEffectGroupHeal:
	var e := SkillEffectGroupHeal.new()
	e.group = String(d.get("group", ""))
	e.radius = float(d.get("radius", 200.0))
	e.heal_frac = float(d.get("heal_frac", 0.25))
	return e
