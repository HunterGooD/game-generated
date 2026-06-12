extends Area2D

# Loot chest — spawns at the end of each wave. Player walks up and presses E
# (or stays close for auto-open after 3 seconds) to start the roulette.

signal opened

const ROULETTE_SCENE: PackedScene = preload("res://scenes/ui/loot_roulette.tscn")
const MINI_REVEAL_SCRIPT: Script = preload("res://scripts/ui/loot_reveal_mini.gd")
const OPEN_RANGE: float = 60.0
const AUTO_OPEN_DELAY: float = 4.0
# A live enemy within this range = "in combat" → use the compact, non-blocking
# corner reveal so opening a chest never gets you killed.
const COMBAT_RANGE: float = 600.0

@export var sprite: Sprite2D
@export var prompt: Label
@export var glow: PointLight2D

var wave_number: int = 1
var opened_already: bool = false
var t_in_range: float = 0.0
var player: Node2D = null


func configure(wave: int) -> void:
	wave_number = max(1, wave)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player hurtbox
	monitoring = true
	z_index = 60
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt:
		prompt.visible = false
	# Feet shadow stays put while the chest bobs above it (reads as a float).
	if sprite:
		BlobShadow.attach_at_feet(self, sprite, 40.0, 14.0)
	# Bob + glow loop.
	if sprite:
		var tw := sprite.create_tween().set_loops()
		tw.tween_property(sprite, "position:y", -10.0, 1.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(sprite, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	if glow:
		var tw2 := glow.create_tween().set_loops()
		tw2.tween_property(glow, "energy", 1.8, 1.2).set_trans(Tween.TRANS_SINE)
		tw2.tween_property(glow, "energy", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if opened_already:
		return
	if player and is_instance_valid(player):
		var dist: float = global_position.distance_to((player as Node2D).global_position)
		if dist <= OPEN_RANGE * 1.6:
			t_in_range += delta
			if prompt:
				prompt.visible = true
			if Input.is_action_just_pressed("interact"):
				open()
			elif t_in_range >= AUTO_OPEN_DELAY:
				open()
		else:
			t_in_range = max(0.0, t_in_range - delta)
			if prompt:
				prompt.visible = false


# "In combat" = any live enemy near the opener. Drives compact vs full-screen reveal.
func _in_combat() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var origin: Vector2 = global_position
	if player != null and is_instance_valid(player):
		origin = (player as Node2D).global_position
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if (e as Node2D).global_position.distance_to(origin) <= COMBAT_RANGE:
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and not body.is_in_group("remote_player"):
		player = body as Node2D


func _on_body_exited(body: Node) -> void:
	if body == player:
		t_in_range = 0.0
		if prompt:
			prompt.visible = false


func open() -> void:
	if opened_already:
		return
	opened_already = true
	# Defer monitoring change — _process can run during physics flushing.
	set_deferred("monitoring", false)
	if prompt:
		prompt.visible = false
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -6.0)
	# Spawn roulette overlay.
	var class_id: String = GameManager.player_class if GameManager else "mage"
	var diff: int = GameManager.run_difficulty if GameManager else 0
	var item: ItemInstance = LootRoller.roll_item(wave_number, class_id, diff)
	# Boss chests have a forced minimum rarity stamped on as metadata.
	var forced: String = String(get_meta("forced_rarity", ""))
	# Обычные сундуки иногда отдают самоцвет вместо экипировки (босс-сундуки — нет).
	if forced == "" and randf() < 0.10:
		var luck: float = Difficulty.value(diff, "loot_rarity_bonus", 0.0)
		if GameManager:
			luck += GameManager.dungeon_loot_luck + GameManager.loop_loot_luck()
		item = LootRoller.roll_gem_item(luck)
	if forced != "" and item != null:
		# Re-roll until we get at least the forced rarity. Limit attempts.
		var ranks: Dictionary = {"common": 0, "rare": 1, "legendary": 2, "unique": 3}
		var target_rank: int = int(ranks.get(forced, 0))
		for _i in 12:
			if int(ranks.get(item.rarity, 0)) >= target_rank:
				break
			item = LootRoller.roll_item(wave_number + 5, class_id, diff)
	if item == null:
		queue_free()
		return
	# In combat → compact non-blocking corner reveal (can't get you killed, auto-takes
	# the item, sped up). Out of combat → the full-screen roulette with Take/Salvage.
	if _in_combat():
		var mini := CanvasLayer.new()
		mini.set_script(MINI_REVEAL_SCRIPT)
		get_tree().current_scene.add_child(mini)
		mini.call("start", item, wave_number, class_id, 1.3)
	else:
		var roulette: CanvasLayer = ROULETTE_SCENE.instantiate()
		get_tree().current_scene.add_child(roulette)
		if roulette.has_method("start"):
			roulette.call("start", item, wave_number, class_id)
	opened.emit()
	# Fade chest out after revealing.
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
