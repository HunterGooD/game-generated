extends Node2D

# Hex Mark — places a debuff on the nearest enemy at the target position.
# The mark ticks small damage every 0.6 s for 4 s, then DETONATES with a
# burst and applies weaker marks to nearby enemies (chains).
# Eternal Mark unique: the natural expiry doesn't fire — only Soul Tether
# or Blood Whip can detonate.

const DURATION: float = 4.0
const TICK_INTERVAL: float = 0.6
const TICK_FRAC: float = 0.15
const DETONATE_MULT: float = 2.4
const CHAIN_RADIUS: float = 180.0
const CHAIN_DURATION: float = 2.4

var damage: int = 14
var visual_only: bool = false
var eternal: bool = false
var marked_enemy: Node2D = null
var aura: Sprite2D = null
var tick_t: float = 0.0
var life_t: float = DURATION


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	# Eternal Mark unique modifies behavior.
	var caster = ctx.caster
	if caster and InventorySystem and InventorySystem.has_method("has_unique"):
		eternal = bool(InventorySystem.call("has_unique", "hexen_eternal_mark"))
	# Lingering Hex modifier — each stack ticks longer before detonating.
	life_t = DURATION + float(ctx.get_mod("duration_bonus", 0.0))


func _ready() -> void:
	z_index = 25
	if visual_only:
		# Visual-only on remote peers — just show the aura briefly and free.
		_show_aura_at(global_position)
		var t := get_tree().create_timer(DURATION + 0.4)
		t.timeout.connect(queue_free)
		return
	marked_enemy = _nearest_enemy(global_position, 120.0)
	if marked_enemy == null:
		# No enemy in range — pop the placement burst and disappear.
		_show_aura_at(global_position)
		var t := get_tree().create_timer(0.4)
		t.timeout.connect(queue_free)
		return
	# Tag enemy with a meta flag so Soul Tether can find marked enemies.
	marked_enemy.set_meta("hex_marked", true)
	marked_enemy.set_meta("hex_mark_node", self)
	# The mark IS a curse — feed the visible stack counter / curse synergies.
	if marked_enemy.has_method("add_curse_stack"):
		marked_enemy.call("add_curse_stack")
	# Crimson outline shader marks the enemy visibly.
	_apply_outline(marked_enemy, Color(1.0, 0.2, 0.35, 1.0))
	_show_aura_at(marked_enemy.global_position)


func _apply_outline(target: Node2D, color: Color) -> void:
	var spr: Node = target.get_node_or_null("Visual")
	if spr == null or not (spr is CanvasItem):
		return
	# Don't clobber the hit-flash material if one is installed — wrap the
	# existing material if we can; otherwise install a fresh outline material.
	# Simplest robust approach: store the original material on meta and swap
	# in the outline shader for the duration of the mark.
	var ci: CanvasItem = spr
	if not ci.has_meta("orig_material"):
		ci.set_meta("orig_material", ci.material)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/outline.gdshader")
	mat.set_shader_parameter("outline_color", color)
	mat.set_shader_parameter("outline_width", 2.5)
	mat.set_shader_parameter("outline_strength", 1.0)
	ci.material = mat


func _clear_outline(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var spr: Node = target.get_node_or_null("Visual")
	if spr == null or not (spr is CanvasItem):
		return
	var ci: CanvasItem = spr
	if ci.has_meta("orig_material"):
		ci.material = ci.get_meta("orig_material")
		ci.remove_meta("orig_material")


func _physics_process(delta: float) -> void:
	if visual_only:
		return
	if marked_enemy == null or not is_instance_valid(marked_enemy):
		_finish(false)
		return
	# Aura follows enemy.
	if aura:
		aura.global_position = marked_enemy.global_position + Vector2(0, -10)
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = TICK_INTERVAL
		if marked_enemy.has_method("take_damage"):
			marked_enemy.call("take_damage", int(round(float(damage) * TICK_FRAC)), global_position)
	if not eternal:
		life_t -= delta
		if life_t <= 0.0:
			detonate()


func detonate() -> void:
	if marked_enemy == null or not is_instance_valid(marked_enemy):
		_finish(false)
		return
	var pos: Vector2 = marked_enemy.global_position
	if marked_enemy.has_method("take_damage"):
		marked_enemy.call("take_damage", int(round(float(damage) * DETONATE_MULT)), pos)
	if VfxManager:
		VfxManager.spawn_explosion(pos, 0.85, Color(0.95, 0.2, 0.35, 1))
		VfxManager.screen_shake(2.0, 0.1)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_hexen_hex_mark_detonate.mp3", -10.0
		)
	# Chain weaker marks to nearby enemies.
	var tree := get_tree()
	if tree:
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or e == marked_enemy:
				continue
			if e.get("dead") == true:
				continue
			if pos.distance_to((e as Node2D).global_position) <= CHAIN_RADIUS:
				e.set_meta("hex_marked", true)
				# Light damage to chained targets.
				if e.has_method("take_damage"):
					e.call("take_damage", int(round(float(damage) * 0.6)), pos)
	_finish(true)


func _show_aura_at(pos: Vector2) -> void:
	aura = Sprite2D.new()
	var path: String = "res://assets/sprites/effects/hex_mark_aura.png"
	if ResourceLoader.exists(path):
		aura.texture = load(path) as Texture2D
	aura.modulate = Color(1.0, 0.25, 0.4, 0.95)
	aura.global_position = pos
	if aura.texture:
		var src_h: float = float(aura.texture.get_size().y)
		if src_h > 1.0:
			var s: float = clamp(70.0 / src_h, 0.05, 0.5)
			aura.scale = Vector2(s, s)
	get_tree().current_scene.add_child(aura)
	# Bob loop.
	var tw := aura.create_tween().set_loops()
	tw.tween_property(aura, "modulate:a", 0.6, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(aura, "modulate:a", 0.95, 0.5).set_trans(Tween.TRANS_SINE)


func _finish(detonated: bool) -> void:
	if marked_enemy and is_instance_valid(marked_enemy):
		marked_enemy.set_meta("hex_marked", false)
		marked_enemy.set_meta("hex_mark_node", null)
		_clear_outline(marked_enemy)
	if aura and is_instance_valid(aura):
		var tw := aura.create_tween()
		tw.tween_property(aura, "modulate:a", 0.0, 0.25)
		tw.tween_callback(aura.queue_free)
	# Avoid unused warning.
	var _ignore := detonated
	queue_free()


func _nearest_enemy(pos: Vector2, max_dist: float) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = max_dist
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		var d: float = pos.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best
