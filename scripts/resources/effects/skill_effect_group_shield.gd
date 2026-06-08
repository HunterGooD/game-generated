class_name SkillEffectGroupShield
extends SkillEffect

# Grants a shield (via add_shield) to allies of the listed groups within `radius` of
# the cast origin. The shield amount is `shield_frac` of the caster's max HP
# (GameManager.player_max_hp, matching the old bespoke approximation). Skipped on
# the visual-only remote copy.

@export var groups: PackedStringArray = PackedStringArray(["player", "remote_player"])
@export var radius: float = 260.0
@export var shield_frac: float = 0.18  # of caster max HP


func execute(ctx: SkillContext, host: Node2D) -> void:
	if ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
	var shield: float = max_hp * shield_frac
	var origin: Vector2 = host.global_position
	for g in groups:
		for a in tree.get_nodes_in_group(String(g)):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if origin.distance_to((a as Node2D).global_position) > radius:
				continue
			if a.has_method("add_shield"):
				a.call("add_shield", shield, -1.0)


static func from_data(d: Dictionary) -> SkillEffectGroupShield:
	var e := SkillEffectGroupShield.new()
	var gs: Array = d.get("groups", ["player", "remote_player"])
	var packed := PackedStringArray()
	for g in gs:
		packed.append(String(g))
	e.groups = packed
	e.radius = float(d.get("radius", 260.0))
	e.shield_frac = float(d.get("shield_frac", 0.18))
	return e
