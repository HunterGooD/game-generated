class_name DungeonEventPillar
extends Node2D

## The main loop-room content: a pillar the party activates by walking up to it. It grants
## a temporary effect (damage buff / shield / — rarely — a loot chest) and, while active,
## has a low chance each tick to spill a small enemy pack nearby. When the effect ends the
## enemies REMAIN, so they're a bonus XP/gold source you fight on the way past — no need to
## backtrack. Chest is the rarest roll because chest drops are the run's main strong reward.
##
## Built in code. The runner sets `spawner` (for host-gated spawns). Co-op: buffs apply per
## local player; enemy spawning is host/solo-gated (v1 parity limitation).

const DURATION := 14.0
const SPAWN_TICK := 3.0
const SPAWN_CHANCE := 0.4       # per tick, while active
const PICKUP_RANGE := 70.0
const CHEST_PATH := "res://scenes/pickups/loot_chest.tscn"
const PACK_TYPES := ["skeleton", "wraith", "cultist"]

var spawner: Node = null

var _claimed := false
var _active := false
var _effect := ""
var _t := 0.0
var _spawn_t := 0.0
var _pulse := 0.0
var _glow: Color = Color(0.6, 0.8, 1.0)


func _ready() -> void:
	z_index = 22
	add_to_group("dungeon_event_pillar")
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if GameManager and GameManager.game_over:
		return
	_pulse = fmod(_pulse + delta, TAU)
	if not _claimed:
		var p := _nearest_player()
		if p and p.global_position.distance_to(global_position) <= PICKUP_RANGE:
			_activate()
		queue_redraw()
		return
	if _active:
		_t += delta
		_spawn_t += delta
		if _spawn_t >= SPAWN_TICK:
			_spawn_t = 0.0
			_maybe_spill_enemies()
		if _t >= DURATION:
			_deactivate()
		queue_redraw()


func _activate() -> void:
	_claimed = true
	_active = true
	_effect = _roll_effect()
	var diff: int = GameManager.run_difficulty if GameManager else 0
	match _effect:
		"damage":
			_glow = Color(1.0, 0.5, 0.4)
			_buff_all(DURATION, 1.3, 1.0)
			_notice("Столп гнева — +30% к урону!", _glow)
		"shield":
			_glow = Color(0.5, 0.8, 1.0)
			_shield_all(40.0 + 15.0 * float(diff))
			_notice("Столп защиты — даровал щит!", _glow)
		"chest":
			_glow = Color(1.0, 0.84, 0.3)
			_spawn_chest()
			_notice("Столп удачи — поднимается тайник!", _glow)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/pickup/pickup_gold_pickup.mp3", -8.0)
	queue_redraw()


func _deactivate() -> void:
	_active = false
	if GameManager:
		GameManager.notice.emit("Сила столпа угасает — добейте отставших.", Color(0.7, 0.7, 0.8))
	queue_redraw()


# Effect roll: chest is the rarest (chest drops are the main strong reward).
func _roll_effect() -> String:
	var r: float = randf()
	if r < 0.12:
		return "chest"
	return "damage" if r < 0.56 else "shield"


func _maybe_spill_enemies() -> void:
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if not host_auth or spawner == null or not spawner.has_method("spawn_room_pack"):
		return
	if randf() > SPAWN_CHANCE:
		return
	spawner.call("spawn_room_pack", PACK_TYPES, global_position, 180.0, 2 + (randi() % 2), 0)


func _buff_all(dur: float, dmg: float, spd: float) -> void:
	for pl in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(pl) and pl.has_method("apply_buff"):
			pl.call("apply_buff", dur, dmg, spd)


func _shield_all(amount: float) -> void:
	for pl in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(pl) and pl.has_method("add_shield"):
			pl.call("add_shield", amount)


func _spawn_chest() -> void:
	if not ResourceLoader.exists(CHEST_PATH):
		return
	var scene: PackedScene = load(CHEST_PATH) as PackedScene
	if scene == null:
		return
	var chest: Node2D = scene.instantiate()
	get_parent().add_child(chest)
	chest.global_position = global_position + Vector2(0, 70)
	if chest.has_method("configure"):
		var wave: int = 6 + (GameManager.run_difficulty if GameManager else 0) * 2 + (GameManager.dungeon_depth if GameManager else 0) * 2
		chest.call("configure", wave)


func _notice(msg: String, col: Color) -> void:
	if GameManager:
		GameManager.notice.emit(msg, col)


func _draw() -> void:
	# Pillar base.
	draw_rect(Rect2(Vector2(-14, -54), Vector2(28, 72)), Color(0.32, 0.30, 0.40))
	var lit: bool = _active or not _claimed
	var a: float = (0.55 + 0.35 * sin(_pulse * 3.0)) if lit else 0.12
	# Glowing crystal on top.
	draw_circle(Vector2(0, -64), 16.0, Color(_glow.r, _glow.g, _glow.b, a))
	if _active:
		draw_arc(Vector2.ZERO, PICKUP_RANGE + 8.0, 0.0, TAU, 40, Color(_glow.r, _glow.g, _glow.b, 0.25 * a), 3.0, true)


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		var d: float = (p as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
