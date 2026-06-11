extends GutTest

# Hub flow: last-played hero persistence (GameManager.set_last_class), the wardrobe
# hero-select overlay applying + remembering a hero, and the hub scene spawning the player
# as the last hero with its three props (wardrobe + portal + co-op beacon).

const HUB_SCENE := "res://scenes/world/hub.tscn"

var _class0: String
var _last0: String
var _state0
var _node0: Dictionary


func before_each() -> void:
	_class0 = GameManager.player_class
	_last0 = GameManager.last_class
	_state0 = GameManager.run_state
	_node0 = GameManager.run_node_active
	GameManager.last_class = "barbarian"  # deterministic baseline (no disk write)


func after_each() -> void:
	GameManager.player_class = _class0
	GameManager.last_class = _last0
	GameManager.run_state = _state0
	GameManager.run_node_active = _node0


# ── last-class persistence ────────────────────────────────────────────────────
func test_set_last_class_records_valid_hero() -> void:
	GameManager.set_last_class("rogue")
	assert_eq(GameManager.last_class, "rogue")


func test_set_last_class_rejects_unknown() -> void:
	GameManager.set_last_class("rogue")
	GameManager.set_last_class("dragon")  # not a real class
	assert_eq(GameManager.last_class, "rogue", "unknown class is ignored")


# ── wardrobe hero select ──────────────────────────────────────────────────────
func test_hero_select_applies_and_remembers() -> void:
	var hs := HeroSelect.new()
	add_child_autofree(hs)
	hs._choose("mage")
	assert_eq(GameManager.player_class, "mage", "chosen hero applied live")
	assert_eq(GameManager.last_class, "mage", "chosen hero remembered for next time")


func test_hero_select_builds_a_card_per_class() -> void:
	var hs := HeroSelect.new()
	add_child_autofree(hs)
	var buttons: int = 0
	for n in _all(hs):
		if n is Button:
			buttons += 1
	assert_eq(buttons, HeroSelect.CLASS_ORDER.size(), "one card per hero")


# ── hub scene ─────────────────────────────────────────────────────────────────
func test_hub_spawns_last_hero_with_props() -> void:
	GameManager.last_class = "rogue"
	var hub: Node = (load(HUB_SCENE) as PackedScene).instantiate()
	add_child_autofree(hub)
	assert_not_null(hub.get_node_or_null("Player"), "player spawned in the hub")
	assert_eq(GameManager.player_class, "rogue", "spawned as the last-played hero")
	assert_eq(hub._props.size(), 3, "wardrobe + portal + co-op beacon props present")


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
