extends GutTest

# Merchant / campfire run-map nodes: the walkable NodeRoom builds the right content, and the
# campfire RestChoice boons apply (heal / XP / gold).

const NODE_ROOM := "res://scenes/world/node_room.tscn"

var _node0: Dictionary
var _hp0: int
var _gold0: int


func before_each() -> void:
	_node0 = GameManager.run_node_active
	_hp0 = GameManager.player_hp
	_gold0 = GameManager.gold


func after_each() -> void:
	GameManager.run_node_active = _node0
	GameManager.player_hp = _hp0
	GameManager.gold = _gold0


# ── NodeRoom ──────────────────────────────────────────────────────────────────
func test_merchant_node_builds_merchant() -> void:
	GameManager.run_node_active = {"type": "merchant"}
	var room: Node = (load(NODE_ROOM) as PackedScene).instantiate()
	add_child_autofree(room)
	assert_eq(room.content_kind, "merchant")


func test_campfire_node_builds_campfire() -> void:
	GameManager.run_node_active = {"type": "campfire"}
	var room: Node = (load(NODE_ROOM) as PackedScene).instantiate()
	add_child_autofree(room)
	assert_eq(room.content_kind, "campfire")
	assert_not_null(room._campfire, "campfire prop present")


# ── RestChoice boons ──────────────────────────────────────────────────────────
func test_rest_mend_full_heals() -> void:
	GameManager.player_hp = 1
	var r := RestChoice.new()
	add_child_autofree(r)
	r._mend()
	assert_eq(GameManager.player_hp, GameManager.player_max_hp, "mend full-heals")


func test_rest_train_grants_xp() -> void:
	var r := RestChoice.new()
	add_child_autofree(r)
	watch_signals(GameManager)
	r._train()
	assert_signal_emitted(GameManager, "xp_gained")


func test_rest_prosper_grants_gold() -> void:
	var r := RestChoice.new()
	add_child_autofree(r)
	r._prosper()
	assert_eq(GameManager.gold, _gold0 + RestChoice.GOLD_BONUS)
