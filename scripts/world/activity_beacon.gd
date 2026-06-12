extends Node2D

# Activity beacon — a glowing icon in a room corner the player walks up to and
# triggers with E (like the merchant). One-shot: fires its event, shows the result,
# then fades. The four types come from ACTIVITY_DEFS (the `name` is the event id):
#   chest   — Treasure: gold + a heal (safe reward)
#   altar   — Altar: 55% blessing (empower + heal) / 45% curse (HP drain)  [risk-reward]
#   roulette— Wheel: stake gold, 50% win 3×, 50% lose it  [gamble]
#   ritual  — Ritual: sacrifice HP for a strong, lasting empowerment  [risk-reward]
#
# Co-op: effects are per-player and local (gold/buff/HP of the interacting player) —
# no host authority needed. Each player triggers their own copy of the beacon.
# (Summoning an elite for a ritual reward is the V6 extension.)

const INTERACT_RANGE: float = 95.0
const STAKE: int = 50

@export var icon_sprite: Sprite2D
@export var label: Label

var activity_name: String = ""  # also the event id: chest / altar / roulette / ritual
var icon_key: String = ""
var label_text: String = ""
var _used: bool = false
var _player_in_range: bool = false


func configure(p_name: String, p_icon: String, p_label: String) -> void:
	activity_name = p_name
	icon_key = p_icon
	label_text = p_label
	_apply()


func _ready() -> void:
	if icon_key != "":
		_apply()
	# Gentle floating animation, bound to THIS node so freeing the node kills the tween.
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", position.y - 6.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "position:y", position.y + 6.0, 1.2).set_trans(Tween.TRANS_SINE)


func _apply() -> void:
	if icon_sprite and icon_key != "":
		var icon_path := "res://assets/sprites/items/%s.png" % icon_key
		if ResourceLoader.exists(icon_path):
			icon_sprite.texture = load(icon_path) as Texture2D
			var tex_size: Vector2 = (
				icon_sprite.texture.get_size() if icon_sprite.texture else Vector2(256, 256)
			)
			var max_dim: float = max(tex_size.x, tex_size.y)
			if max_dim > 0:
				var sc: float = 90.0 / max_dim
				icon_sprite.scale = Vector2(sc, sc)
	if label:
		label.text = label_text


func _process(_delta: float) -> void:
	if _used:
		return
	var p := _local_player()
	var in_range: bool = p != null and global_position.distance_to(p.global_position) <= INTERACT_RANGE
	if in_range != _player_in_range:
		_player_in_range = in_range
		if label:
			label.text = (label_text + "  [E]") if in_range else label_text
	if in_range and Input.is_action_just_pressed("interact"):
		_trigger(p)


func _local_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D and not p.is_in_group("remote_player"):
			return p as Node2D
	return null


func _trigger(player: Node2D) -> void:
	if _used:
		return
	_used = true
	var result: String = _apply_event(player)
	_feedback(result)
	_go_inert()


func _apply_event(player: Node2D) -> String:
	match activity_name:
		"chest":
			return event_treasure(player)
		"altar":
			return event_altar(player)
		"roulette":
			return event_roulette(player)
		"ritual":
			return event_ritual(player)
	return ""


# ── Event effects (per-player, host-free, deterministically testable via `roll`) ──
func event_treasure(_player: Node2D) -> String:
	var amt: int = 80 + (randi() % 70)
	if GameManager:
		GameManager.add_gold_with_bonus(amt)
		GameManager.heal_player(25)
	return "Сокровище  +%d золота" % amt


func event_altar(player: Node2D, roll: float = -1.0) -> String:
	if roll < 0.0:
		roll = randf()
	if roll < 0.55:
		if player and player.has_method("apply_buff"):
			player.call("apply_buff", 30.0, 1.30, 1.15)
		if GameManager:
			GameManager.heal_player(40)
		return "Благословение  +30% к силе"
	_lose_hp(0.15)
	return "Проклятие  жизненная сила истощена"


func event_roulette(_player: Node2D, roll: float = -1.0) -> String:
	if GameManager == null or GameManager.gold < STAKE:
		return "Недостаточно золота для ставки"
	GameManager.gold -= STAKE
	GameManager.gold_changed.emit(GameManager.gold)
	if roll < 0.0:
		roll = randf()
	if roll < 0.5:
		GameManager.add_gold(STAKE * 3)
		return "Джекпот  +%d золота" % (STAKE * 2)
	return "Проигрыш  -%d золота" % STAKE


func event_ritual(player: Node2D) -> String:
	# Sacrifice HP for a potent, lasting empowerment.
	_lose_hp(0.25)
	if player and player.has_method("apply_buff"):
		player.call("apply_buff", 45.0, 1.5, 1.25)
	return "Ритуал  сила за кровь"


func _lose_hp(frac: float) -> void:
	if GameManager == null:
		return
	var cost: int = int(round(float(GameManager.player_max_hp) * frac))
	GameManager.player_hp = maxi(1, GameManager.player_hp - cost)  # non-lethal
	GameManager.player_stats_changed.emit()


func _feedback(result: String) -> void:
	if label:
		label.text = result
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_greeting.mp3", -8.0)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.92, 0.55, 1), 16)
		VfxManager.screen_flash(Color(1.0, 0.9, 0.5, 0.18), 0.2)


func _go_inert() -> void:
	_player_in_range = false
	modulate = Color(0.6, 0.6, 0.62, 1)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
