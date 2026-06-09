extends BtAllyBody

# Spirit pet — small allied creature (druid Summon Spirit). Uses the shared ally
# chassis (BtAllyBody) for networking / puppet / death / BT; adds the ghost-wolf
# pounce and the spirit sprites.

const MOVE_SPEED: float = 220.0
const ATTACK_COOLDOWN: float = 1.0
const DETECTION: float = 480.0

var pet_type: String = "wolf"  # "wolf" or "bear"

# Ghost-wolf pounce: close a mid-range gap in one leap, then melee normally.
const LEAP_MIN: float = 90.0
const LEAP_MAX: float = 300.0
const LEAP_TIME: float = 0.22
const LEAP_COOLDOWN: float = 4.0
const LEAP_LAND_GAP: float = 45.0  # land this close to the target (inside melee)
var _leap_t: float = 0.0
var _leap_cd: float = 0.0


func configure(p_type: String, dmg: int) -> void:
	pet_type = p_type
	# Druid spirit pets are DISTRACTIONS — low damage, low HP. The whole point is
	# enemies attack the pet for a few seconds instead of the player. Bear is tankier.
	max_hp = 45
	damage = max(3, int(round(float(dmg) * 0.30)))
	if pet_type == "bear":
		max_hp = 110
		damage = max(6, int(round(float(dmg) * 0.55)))
	hp = max_hp


# ── BtAllyBody overrides ──────────────────────────────────────────────────────
func _ai_group() -> String:
	return "spirit_pet"


func _chase_speed() -> float:
	return MOVE_SPEED


func _detection_range() -> float:
	return DETECTION


func _follow_stop_dist() -> float:
	return 90.0


func _bt_path() -> String:
	return "res://scenes/ai/spirit_bt.tres"


func _base_modulate() -> Color:
	return Color(0.7, 0.95, 1.05, 0.9)


func _death_spark_color() -> Color:
	return Color(0.55, 0.95, 1.0, 1)


func _tick_ai_timers(delta: float) -> void:
	if _leap_cd > 0.0:
		_leap_cd -= delta
	if _leap_t > 0.0:
		_leap_t -= delta


func _attack(target: Node2D) -> void:
	attack_cd = ATTACK_COOLDOWN
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")
	if target.has_method("take_damage"):
		target.call("take_damage", damage, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(target.global_position, Color(0.55, 0.95, 1.0, 1), 5)


func _apply_sprite_frames() -> void:
	if sprite == null:
		return
	var prefix: String = "spirit_wolf"
	if pet_type == "bear":
		prefix = "spirit_bear"
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
	# Normalize visual height to ~55 px regardless of source PNG resolution.
	var target_h: float = 55.0
	var s: float = 0.12
	if sample_tex:
		var src_h: float = float(sample_tex.get_size().y)
		if src_h > 1.0:
			s = clamp(target_h / src_h, 0.05, 0.5)
	sprite.scale = Vector2(s, s)
	sprite.modulate = _base_modulate()


# ── Ghost-wolf pounce (BT only) ───────────────────────────────────────────────
func bt_is_leaping() -> bool:
	return _leap_t > 0.0


func bt_can_leap(target_pos: Vector2) -> bool:
	if _leap_cd > 0.0 or bt_is_leaping():
		return false
	var d: float = global_position.distance_to(target_pos)
	return d >= LEAP_MIN and d <= LEAP_MAX


# Leap toward the target, landing just inside melee range; the tween moves the body
# directly (a short flight), then normal chase/attack resumes.
func bt_start_leap(target: Node2D) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var dest: Vector2 = target.global_position - dir * LEAP_LAND_GAP
	_face(target.global_position)
	velocity = Vector2.ZERO
	_leap_t = LEAP_TIME
	_leap_cd = LEAP_COOLDOWN
	var tw := create_tween()
	(
		tw.tween_property(self, "global_position", dest, LEAP_TIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.55, 0.95, 1.0, 1), 4)
