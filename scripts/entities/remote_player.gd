extends CharacterBody2D

# Visual puppet for a remote co-op player. Receives position + state messages
# from the relay, interpolates between them, plays animations. Local damage is
# NEVER applied here — the host adjudicates HP and broadcasts updates.

signal died(player_id: int)

@export var player_id: int = -1
var class_id: String = "mage"
var class_color: Color = Color(0.7, 0.3, 0.8, 1)
var name_label_text: String = "P?"
var hp: int = 100
var max_hp: int = 100
var is_dead: bool = false
var is_downed: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _facing_right: bool = true
var _anim_state: String = "idle"

const LERP_WEIGHT: float = 12.0

@export var sprite: AnimatedSprite2D
@export var hp_bar: ProgressBar
@export var name_label: Label


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("player")  # so Battle Cry / heals pick remote allies up
	add_to_group("remote_player")
	z_index = 50
	# Anchor target at our spawn so we don't lerp to (0,0) before first state.
	_target_pos = global_position
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
		hp_bar.visible = true
	if name_label:
		name_label.text = name_label_text


func set_initial_position(pos: Vector2) -> void:
	global_position = pos
	_target_pos = pos


func set_player_id(id: int) -> void:
	player_id = id
	name_label_text = "P%d" % (id + 1)
	if name_label:
		name_label.text = name_label_text


func apply_class(class_id_in: String) -> void:
	class_id = class_id_in
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data(class_id)
	class_color = data.get("color", Color(0.7, 0.3, 0.8, 1))
	if name_label:
		name_label.add_theme_color_override("font_color", class_color)
	if sprite:
		var frames := SpriteFrames.new()
		var sample_tex: Texture2D = null
		for state_key in ["idle", "walk", "attack"]:
			var path: String = String(data.get("sprite_" + state_key, ""))
			if path != "" and ResourceLoader.exists(path):
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
		_normalize_sprite_scale(sample_tex)
	if hp_bar:
		max_hp = int(data.get("base", {}).get("max_hp", 100))
		hp = max_hp
		hp_bar.max_value = max_hp
		hp_bar.value = hp


func update_target(msg: Dictionary) -> void:
	_target_pos = Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	_facing_right = bool(msg.get("fr", true))
	_anim_state = String(msg.get("a", "idle"))


func apply_druid_form(form_id: String) -> void:
	# Only relevant when this puppet is the druid class.
	if class_id != "druid":
		return
	if sprite == null:
		return
	var paths: Dictionary
	match form_id:
		"wolf":
			paths = {
				"idle": "res://assets/sprites/characters/druid_wolf_idle.png",
				"walk": "res://assets/sprites/characters/druid_wolf_walk.png",
				"attack": "res://assets/sprites/characters/druid_wolf_attack.png",
			}
		"bear":
			paths = {
				"idle": "res://assets/sprites/characters/druid_bear_idle.png",
				"walk": "res://assets/sprites/characters/druid_bear_walk.png",
				"attack": "res://assets/sprites/characters/druid_bear_attack.png",
			}
		"eagle":
			paths = {
				"idle": "res://assets/sprites/characters/druid_eagle_idle.png",
				"walk": "res://assets/sprites/characters/druid_eagle_walk.png",
				"attack": "res://assets/sprites/characters/druid_eagle_attack.png",
			}
		_:
			paths = {
				"idle": "res://assets/sprites/characters/druid_human_idle.png",
				"walk": "res://assets/sprites/characters/druid_human_walk.png",
				"attack": "res://assets/sprites/characters/druid_human_attack.png",
			}
	var frames := SpriteFrames.new()
	var sample_tex: Texture2D = null
	for state_key in ["idle", "walk", "attack"]:
		var path: String = String(paths.get(state_key, ""))
		if path != "" and ResourceLoader.exists(path):
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
	_normalize_sprite_scale(sample_tex)


func _normalize_sprite_scale(sample_tex: Texture2D) -> void:
	if sprite == null or sample_tex == null:
		return
	var src_h: float = float(sample_tex.get_size().y)
	if src_h <= 1.0:
		return
	var target_h: float = 85.0
	var s: float = clamp(target_h / src_h, 0.08, 0.5)
	sprite.scale = Vector2(s, s)


func apply_state(msg: Dictionary) -> void:
	if msg.has("hp"):
		hp = int(msg.get("hp", hp))
		if hp_bar:
			hp_bar.value = hp
	if msg.has("max_hp"):
		max_hp = int(msg.get("max_hp", max_hp))
		if hp_bar:
			hp_bar.max_value = max_hp
	# Note: reaching 0 HP no longer auto-kills the puppet. The owning client
	# decides downed vs dead and broadcasts player_downed / player_dead, which
	# drive set_downed() / mark_dead() — see NetSync.


func _process(delta: float) -> void:
	if is_dead:
		return
	var w: float = clamp(LERP_WEIGHT * delta, 0.0, 1.0)
	global_position = global_position.lerp(_target_pos, w)
	if sprite:
		sprite.flip_h = not _facing_right
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(_anim_state):
			if sprite.animation != _anim_state:
				sprite.play(_anim_state)


func _die() -> void:
	is_dead = true
	if sprite:
		var tw := sprite.create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate:a", 0.3, 0.5)
		tw.tween_property(sprite, "scale", sprite.scale * 0.85, 0.5)
	if hp_bar:
		hp_bar.visible = false
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, class_color, 12)
	died.emit(player_id)


# Remote players act like enemies to enemies — they CAN be hit by enemy attacks
# (the host runs this code on its side), but a non-host instance just forwards
# the damage as a network message.
func take_damage(amount: int) -> void:
	if is_dead or is_downed:
		return
	if NetManager and NetManager.is_host:
		# Host applies and broadcasts. It does NOT decide death here — once HP
		# reaches 0 the owning client goes downed and echoes player_downed /
		# player_dead back, which drives set_downed() / mark_dead().
		hp = max(0, hp - amount)
		if hp_bar:
			hp_bar.value = hp
		NetManager.send("rp_hp", {"target": player_id, "hp": hp})
	# Non-host: do nothing locally; host will broadcast new HP via apply_state.


func set_downed(downed: bool) -> void:
	is_downed = downed
	if downed:
		if sprite:
			sprite.modulate = Color(0.55, 0.55, 0.65, 0.92)
			sprite.rotation = deg_to_rad(80.0)
		if hp_bar:
			hp_bar.value = 0
	else:
		if sprite:
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.rotation = 0.0
		if hp_bar:
			hp_bar.visible = true


func mark_dead() -> void:
	is_downed = false
	if not is_dead:
		_die()


# Enemy hitboxes route here via this puppet's HurtBoxComponent. Only the host
# adjudicates damage to remote players; other peers ignore it (they receive the
# resulting HP through the host's rp_hp broadcast).
func receive_damage_payload(payload: DamageInstance) -> bool:
	if payload == null or is_dead or is_downed:
		return false
	if NetManager == null or not NetManager.is_host:
		return false
	var amount: int = int(round(payload.amount))
	if amount <= 0:
		return false
	take_damage(amount)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.5, 0.4, 1), 5)
	return true
