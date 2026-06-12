extends BtAllyBody

# Necromancer minion — skeletal soldier or armored knight. Uses the shared ally
# chassis (BtAllyBody) for networking / puppet / death / BT; adds the blood-pact buff,
# the knight/soldier speed split, and skeleton sprites.

const MOVE_SPEED_SOLDIER: float = 240.0
const MOVE_SPEED_KNIGHT: float = 150.0
const ATTACK_COOLDOWN: float = 1.0
const DETECTION: float = 520.0

var minion_kind: String = "skeleton"  # "skeleton" or "knight"
# Blood Pact buff state.
var buff_t: float = 0.0
var dmg_mult: float = 1.0
var spd_mult: float = 1.0


func configure(kind: String, caster_dmg: int) -> void:
	minion_kind = kind
	if minion_kind == "knight":
		# Tank: high HP, modest damage, slow.
		max_hp = 200
		damage = max(10, int(round(float(caster_dmg) * 0.65)))
	else:
		# Soldier: low HP, fast.
		max_hp = 55
		damage = max(6, int(round(float(caster_dmg) * 0.45)))
	hp = max_hp


func apply_knight_armor_bonus(extra_hp: int) -> void:
	if minion_kind != "knight":
		return
	max_hp += extra_hp
	hp = max_hp


# Called by Blood Pact — empower this minion temporarily and full-heal.
func apply_blood_pact(duration: float, dmg_multiplier: float, speed_multiplier: float) -> void:
	if dead:
		return
	buff_t = max(buff_t, duration)
	dmg_mult = max(dmg_mult, dmg_multiplier)
	spd_mult = max(spd_mult, speed_multiplier)
	hp = max_hp
	if sprite:
		sprite.modulate = Color(1.4, 0.55, 0.9, 1)


# ── BtAllyBody overrides ──────────────────────────────────────────────────────
func _ai_group() -> String:
	return "necro_minion"


func _chase_speed() -> float:
	var base_speed: float = MOVE_SPEED_KNIGHT if minion_kind == "knight" else MOVE_SPEED_SOLDIER
	return base_speed * spd_mult


func _detection_range() -> float:
	return DETECTION


func _follow_stop_dist() -> float:
	return 110.0


func _bt_path() -> String:
	return "res://scenes/ai/minion_bt.tres"


func _base_modulate() -> Color:
	return Color(0.85, 0.78, 1.0, 0.95)


func _death_spark_color() -> Color:
	return Color(0.8, 0.55, 1.0, 1)


func _tick_ai_timers(delta: float) -> void:
	if buff_t > 0.0:
		buff_t -= delta
		if buff_t <= 0.0:
			dmg_mult = 1.0
			spd_mult = 1.0
			if sprite:
				sprite.modulate = _base_modulate()


func _attack(target: Node2D) -> void:
	attack_cd = ATTACK_COOLDOWN
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")
	var dmg: int = int(round(float(damage) * dmg_mult))
	if target.has_method("take_damage"):
		target.call("take_damage", dmg, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(target.global_position, Color(0.8, 0.55, 1.0, 1), 5)


func _apply_sprite_frames() -> void:
	if sprite == null:
		return
	var prefix: String = "necro_skeleton"
	if minion_kind == "knight":
		prefix = "necro_skeleton_knight"
	var frames := SpriteFrames.new()
	var sample_tex: Texture2D = null
	for state_key in ["idle", "walk", "attack"]:
		var path: String = "res://assets/sprites/characters/%s_%s.png" % [prefix, state_key]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				if sample_tex == null:
					sample_tex = tex
				frames.add_animation(state_key)
				frames.set_animation_loop(state_key, true)
				frames.set_animation_speed(state_key, 5.0)
				frames.add_frame(state_key, tex, 1.0)
	sprite.sprite_frames = frames
	if frames.has_animation("idle"):
		sprite.play("idle")
	# Knight is bigger; soldier is smaller.
	var target_h: float = 60.0 if minion_kind == "skeleton" else 85.0
	var s: float = 0.12
	if sample_tex:
		var src_h: float = float(sample_tex.get_size().y)
		if src_h > 1.0:
			s = clamp(target_h / src_h, 0.05, 0.5)
	sprite.scale = Vector2(s, s)
	# Subtle violet tint for the undead.
	sprite.modulate = _base_modulate()


# Gravewrought Regalia 5pc — minions detonate in a small bone nova on death.
func _die() -> void:
	if (
		not dead
		and not is_puppet
		and InventorySystem
		and InventorySystem.has_method("has_set_effect")
		and InventorySystem.has_set_effect("necro_grave_burst")
	):
		_grave_burst()
	super._die()


func _grave_burst() -> void:
	var burst_dmg: int = max(8, int(round(float(damage) * 1.5)))
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 0.9, Color(0.85, 0.8, 0.7, 1))
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		if global_position.distance_to((e as Node2D).global_position) <= 120.0:
			if e.has_method("take_damage"):
				e.call("take_damage", burst_dmg, global_position)
