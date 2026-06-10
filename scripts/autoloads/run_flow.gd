extends Node
## RunFlow (autoload) — owns scene transitions for a run: map ↔ node gameplay.
##
## - start_run / open_map  → change to the run-map scene
## - run_node_entered       → combat node: load the gameplay scene; other nodes auto-resolve
## - run_node_cleared       → gameplay finished → back to the run map
##
## Co-op: travel is host-authoritative (GameManager gates clients), so RunFlow only drives
## scene changes on the peer that owns navigation. Full client-follow is a Phase-1 relay
## addition (a `run_nav` message); for now the host plays the run.

const SCENE_RUN_MAP := "res://scenes/ui/run_map.tscn"
const SCENE_COMBAT := "res://scenes/world/game_world.tscn"
const SCENE_DUNGEON := "res://scenes/world/dungeon.tscn"
const SCENE_HUB := "res://scenes/world/hub.tscn"
const SCENE_NODE_ROOM := "res://scenes/world/node_room.tscn"

# Only drive scene changes while RunFlow actually owns a live run (entered via start_run /
# open_map). Otherwise stray GameManager run signals — e.g. unit tests exercising
# start_run / run_travel_to directly — must NOT hijack the current scene.
var _flow_active: bool = false


func _ready() -> void:
	GameManager.run_node_entered.connect(_on_node_entered)
	GameManager.run_node_cleared.connect(_on_node_cleared)


# Begin a fresh run and show its map.
func start_run(difficulty: int, seed_value: int = -1) -> void:
	_flow_active = true
	GameManager.start_run(difficulty, seed_value)
	_change_scene(SCENE_RUN_MAP)


func open_map() -> void:
	_flow_active = true
	_change_scene(SCENE_RUN_MAP)


# Leave the run and return to the hub (the staging area). Abandons the current run.
func exit_to_hub() -> void:
	_flow_active = false
	GameManager.run_state = null
	GameManager.run_node_active = {}
	_change_scene(SCENE_HUB)


# Scene path for a node, or "" when the node auto-resolves on the map.
func target_for_node(node: Dictionary) -> String:
	var t: String = String(node.get("type", ""))
	if t == RunMap.TYPE_DUNGEON:
		return SCENE_DUNGEON  # graph-built explorable dungeon (own scene)
	if RunMap.is_combat_type(t):
		return SCENE_COMBAT
	if t == RunMap.TYPE_MERCHANT or t == RunMap.TYPE_CAMPFIRE:
		return SCENE_NODE_ROOM
	return ""


func _on_node_entered(node: Dictionary) -> void:
	if not _flow_active:
		return  # RunFlow isn't managing a run (e.g. unit tests) — don't touch the scene
	var target: String = target_for_node(node)
	if target == "":
		return  # non-combat node: nothing to load, stay on the map
	GameManager.begin_run_node(node)
	_change_scene(target)


func _on_node_cleared(_node: Dictionary) -> void:
	if not _flow_active:
		return
	_change_scene(SCENE_RUN_MAP)


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Deferred: scene changes are requested from signal handlers (mid-tree-iteration).
	tree.call_deferred("change_scene_to_file", path)
