class_name SkillEffectTelegraph
extends SkillEffect

# One-shot delayed area burst: shows a telegraph sprite at the cast origin, waits
# `delay`, then detonates — explosion/shake/flash plus a radius hit that damages
# enemies (optional distance falloff / element mark / slow / hard-freeze chill),
# shields nearby allies, and pays the caster (shield, cooldown refund, control
# notify). The SceneTree timer outlives the immediately-freed composed host. Gameplay
# (everything but the visuals) is skipped on the visual-only remote copy.

@export var delay: float = 0.5
@export var radius: float = 150.0
@export var damage_mult: float = 1.0
@export var falloff: bool = false
@export var mark_element: String = ""
@export var slow_duration: float = 0.0
@export var slow_mult: float = 1.0
@export var chill_duration: float = 0.0
@export var chill_stacks: int = 0
@export var ally_shield_frac: float = 0.0  # ally shield = ctx.damage * this
@export var caster_shield_frac: float = 0.0  # caster shield = ctx.damage * this
@export var cooldown_refund: float = 0.0  # caster.skill_system.reduce_all_cooldowns
@export var notify_control: bool = false
@export var telegraph_color: Color = Color(1, 0.4, 0.4, 0.85)
@export var telegraph_texture: String = ""
@export var telegraph_scale: float = 1.0
@export var explosion_scale: float = 0.0
@export var explosion_color: Color = Color(1, 1, 1, 1)
@export var shake_strength: float = 0.0
@export var shake_time: float = 0.0
@export var flash_color: Color = Color(1, 1, 1, 0)
@export var flash_time: float = 0.0


func execute(ctx: SkillContext, host: Node2D) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var origin: Vector2 = host.global_position

	var tel := Sprite2D.new()
	if telegraph_texture != "" and ResourceLoader.exists(telegraph_texture):
		tel.texture = load(telegraph_texture) as Texture2D
	tel.modulate = telegraph_color
	tel.global_position = origin
	tel.scale = Vector2(telegraph_scale, telegraph_scale)
	tel.z_index = 50
	tree.current_scene.add_child(tel)

	# Copy fields to locals so the detonation closure captures values, not self.
	var dmg: int = int(round(float(ctx.damage) * damage_mult))
	var base_dmg: int = ctx.damage
	var caster := ctx.caster
	var is_visual: bool = ctx.is_visual_only
	var l_radius := radius
	var l_falloff := falloff
	var l_mark := mark_element
	var l_slow_d := slow_duration
	var l_slow_m := slow_mult
	var l_chill_d := chill_duration
	var l_chill_s := chill_stacks
	var l_ally := ally_shield_frac
	var l_cshield := caster_shield_frac
	var l_cd := cooldown_refund
	var l_control := notify_control
	var l_expl := explosion_scale
	var l_expl_c := explosion_color
	var l_shake := shake_strength
	var l_shake_t := shake_time
	var l_flash_c := flash_color
	var l_flash_t := flash_time

	var t := tree.create_timer(delay)
	t.timeout.connect(
		func() -> void:
			if is_instance_valid(tel):
				tel.queue_free()
			if VfxManager:
				if l_expl > 0.0:
					VfxManager.spawn_explosion(origin, l_expl, l_expl_c)
				if l_shake_t > 0.0:
					VfxManager.screen_shake(l_shake, l_shake_t)
				if l_flash_t > 0.0:
					VfxManager.screen_flash(l_flash_c, l_flash_t)
			if is_visual:
				return
			var tr := Engine.get_main_loop() as SceneTree
			if tr == null:
				return
			for e in tr.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var dist: float = origin.distance_to((e as Node2D).global_position)
				if dist > l_radius:
					continue
				var d: int = dmg
				if l_falloff:
					d = int(round(float(dmg) * clampf(1.0 - (dist / l_radius) * 0.5, 0.4, 1.0)))
				if e.has_method("take_damage"):
					e.call("take_damage", d, origin)
					ctx.apply_on_hit(e)
				if l_mark != "" and e.has_method("mark_element"):
					e.call("mark_element", l_mark)
				if l_chill_d > 0.0 and e.has_method("apply_chill"):
					e.call("apply_chill", l_chill_d, l_chill_s)
				elif l_slow_d > 0.0 and e.has_method("apply_slow"):
					e.call("apply_slow", l_slow_d, l_slow_m)
			if l_ally > 0.0:
				for grp in ["player", "remote_player"]:
					for a in tr.get_nodes_in_group(grp):
						if not is_instance_valid(a) or not (a is Node2D):
							continue
						if origin.distance_to((a as Node2D).global_position) > l_radius:
							continue
						if a.has_method("add_shield"):
							a.call("add_shield", float(base_dmg) * l_ally, -1.0)
			if caster and is_instance_valid(caster):
				if l_cshield > 0.0 and caster.has_method("add_shield"):
					caster.call("add_shield", float(base_dmg) * l_cshield, -1.0)
				if l_cd > 0.0:
					var ss = caster.get("skill_system")
					if ss and ss.has_method("reduce_all_cooldowns"):
						ss.call("reduce_all_cooldowns", l_cd)
				if l_control and caster.has_method("notify_control_applied"):
					caster.call("notify_control_applied")
	)


static func from_data(d: Dictionary) -> SkillEffectTelegraph:
	var e := SkillEffectTelegraph.new()
	e.delay = float(d.get("delay", 0.5))
	e.radius = float(d.get("radius", 150.0))
	e.damage_mult = float(d.get("damage_mult", 1.0))
	e.falloff = bool(d.get("falloff", false))
	e.mark_element = String(d.get("mark_element", ""))
	e.slow_duration = float(d.get("slow_duration", 0.0))
	e.slow_mult = float(d.get("slow_mult", 1.0))
	e.chill_duration = float(d.get("chill_duration", 0.0))
	e.chill_stacks = int(d.get("chill_stacks", 0))
	e.ally_shield_frac = float(d.get("ally_shield_frac", 0.0))
	e.caster_shield_frac = float(d.get("caster_shield_frac", 0.0))
	e.cooldown_refund = float(d.get("cooldown_refund", 0.0))
	e.notify_control = bool(d.get("notify_control", false))
	e.telegraph_color = d.get("telegraph_color", Color(1, 0.4, 0.4, 0.85))
	e.telegraph_texture = String(d.get("telegraph_texture", ""))
	e.telegraph_scale = float(d.get("telegraph_scale", 1.0))
	e.explosion_scale = float(d.get("explosion_scale", 0.0))
	e.explosion_color = d.get("explosion_color", Color(1, 1, 1, 1))
	e.shake_strength = float(d.get("shake_strength", 0.0))
	e.shake_time = float(d.get("shake_time", 0.0))
	e.flash_color = d.get("flash_color", Color(1, 1, 1, 0))
	e.flash_time = float(d.get("flash_time", 0.0))
	return e
