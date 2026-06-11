class_name RewardDropComponent
extends Node

# Spawns XP + gold pickups when an actor dies. Owns the reward values; the host
# entity pushes them in from its spawn config (see Enemy.configure) and calls
# drop_at() from its death handler. Keeping the spawn logic here lets bosses and
# other droppers reuse the same behaviour.

const DROP_GOLD_SCENE: PackedScene = preload("res://scenes/pickups/gold_drop.tscn")

# xp_value is kept so the death handler can read the kill's XP (granted as a number
# now — XP orbs were removed). Only gold is dropped as a pickup.
@export var xp_value: int = 12
@export var gold_min: int = 1
@export var gold_max: int = 4


func drop_at(world_pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	# Gold drops (small cluster).
	var gold_amount: int = randi_range(gold_min, gold_max)
	if gold_amount > 0:
		var gold := DROP_GOLD_SCENE.instantiate()
		tree.current_scene.call_deferred("add_child", gold)
		gold.global_position = world_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		if gold.has_method("setup"):
			gold.call("setup", gold_amount)
