extends Node2D

# Death Pulse — instant AOE nova around the caster. Damages every enemy hit
# and heals the necromancer 8% max HP per enemy struck (cap 40%).

const BASE_RADIUS: float = 220.0
const HEAL_PCT_PER_HIT: float = 0.08
const HEAL_CAP_PCT: float = 0.40

var damage: int = 24
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	var caster = ctx.caster
	if visual_only or caster == null:
		return
	# Radius upgrade.
	var radius: float = BASE_RADIUS
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		var stacks: int = int(ss.call("get_modifier", 3, "necro_pulse_radius"))
		radius *= (1.0 + 0.3 * float(stacks))
	var tree := get_tree()
	if tree == null:
		return
	var hits: int = 0
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		var d: float = caster.global_position.distance_to((e as Node2D).global_position)
		if d <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage, caster.global_position)
			hits += 1
	# Heal up to the cap.
	if hits > 0 and GameManager:
		var heal_pct: float = clamp(HEAL_PCT_PER_HIT * float(hits), 0.0, HEAL_CAP_PCT)
		var heal_amt: int = int(round(float(GameManager.player_max_hp) * heal_pct))
		if heal_amt > 0:
			GameManager.heal_player(heal_amt)


func _ready() -> void:
	z_index = 60
	var s := Sprite2D.new()
	var path := "res://assets/sprites/effects/death_pulse_ring.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	s.modulate = Color(0.85, 0.5, 1.0, 0.95)
	s.scale = Vector2(0.4, 0.4)
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2(2.4, 2.4), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(s, "modulate:a", 0.0, 0.6)
	if VfxManager:
		VfxManager.screen_shake(4.0, 0.18)
		VfxManager.screen_flash(Color(0.7, 0.4, 1.0, 0.18), 0.25)
	# Camera punch — sells the nova as a heavy beat.
	var tree := get_tree()
	if tree:
		for p in tree.get_nodes_in_group("player"):
			if not p.is_in_group("remote_player") and p.has_method("camera_punch"):
				p.call("camera_punch", 0.08, 0.28)
				break
	var done := get_tree().create_timer(0.75)
	done.timeout.connect(queue_free)
