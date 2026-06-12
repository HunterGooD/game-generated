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

# Emitted whenever the co-op vote tally changes, so the run-map UI repaints node badges.
signal votes_changed

# Only drive scene changes while RunFlow actually owns a live run (entered via start_run /
# open_map). Otherwise stray GameManager run signals — e.g. unit tests exercising
# start_run / run_travel_to directly — must NOT hijack the current scene.
var _flow_active: bool = false

# Co-op next-node votes: player_id -> node_id. The host tallies these; a unanimous vote
# (or the host force-resolving) broadcasts run_travel so the whole party moves together.
var votes: Dictionary = {}


func _ready() -> void:
	GameManager.run_node_entered.connect(_on_node_entered)
	GameManager.run_node_cleared.connect(_on_node_cleared)
	if NetManager and not NetManager.message_received.is_connected(_on_net_message):
		NetManager.message_received.connect(_on_net_message)
	if NetManager and not NetManager.player_disconnected.is_connected(_on_player_disconnected):
		NetManager.player_disconnected.connect(_on_player_disconnected)


# ── co-op helpers ──────────────────────────────────────────────────────────────
func is_coop() -> bool:
	return NetManager != null and NetManager.is_multiplayer


func is_coop_host() -> bool:
	return is_coop() and NetManager.is_host


func is_coop_client() -> bool:
	return is_coop() and not NetManager.is_host


# A peer left while on the run map — drop their stale vote so the tally (and the host's
# auto-resolve, which waits for everyone) reflects the now-smaller party.
func _on_player_disconnected(pid: int) -> void:
	if pid < 0:
		votes.clear()
	else:
		votes.erase(pid)
	votes_changed.emit()
	if is_coop_host():
		_try_resolve_votes()


# Begin a fresh run and show its map. A run started from the hub always begins
# at loop 0 — continue_run is the only way to carry the loop counter forward.
func start_run(difficulty: int, seed_value: int = -1) -> void:
	_flow_active = true
	GameManager.run_loop = 0
	GameManager.start_run(difficulty, seed_value)
	_change_scene(SCENE_RUN_MAP)


# Post-uber-boss "Continue": next loop, fresh map, build intact. Solo rolls the
# map directly; the co-op host broadcasts run_start (with the loop) so every
# client lands on the identical new map.
func continue_run(difficulty: int) -> void:
	if is_coop_client():
		return  # host-authoritative — clients follow the run_start broadcast
	GameManager.run_loop += 1
	if is_coop_host():
		host_start_run(difficulty, true)
		open_map()
	else:
		_flow_active = true
		GameManager.start_run(difficulty)
		_change_scene(SCENE_RUN_MAP)


func open_map() -> void:
	_flow_active = true
	_change_scene(SCENE_RUN_MAP)


# ── co-op run map: start / vote / travel ────────────────────────────────────────
# Host picks the difficulty (in the run-map picker). Generate the map locally, then
# broadcast (seed, difficulty) so every client rebuilds the identical DAG. Solo just
# starts the run. RunMapUI routes its difficulty buttons through here.
func host_start_run(difficulty: int, keep_loop: bool = false) -> void:
	_flow_active = true
	votes.clear()
	if not keep_loop:
		GameManager.run_loop = 0
	GameManager.start_run(difficulty)  # generates run_seed + map, emits run_started
	if is_coop_host():
		NetManager.send(
			"run_start",
			{
				"seed": GameManager.run_seed,
				"difficulty": GameManager.run_difficulty,
				"loop": GameManager.run_loop,
			}
		)


# A player clicked a reachable node. Solo travels immediately; co-op casts a vote that
# the host tallies. Re-clicking the same node keeps the vote (idempotent).
func cast_vote(node_id: int) -> void:
	if not is_coop():
		GameManager.run_travel_to(node_id)  # solo: direct travel (host-auth gate passes)
		return
	votes[NetManager.local_player_id] = node_id
	NetManager.send("run_vote", {"node": node_id})
	votes_changed.emit()
	if is_coop_host():
		_try_resolve_votes()


# Host-only: force the party onto the current leading node even without a unanimous vote
# (plurality; the host's own vote breaks ties). Enabled in the UI once everyone has voted.
func host_force_resolve() -> void:
	if not is_coop_host():
		return
	var node: int = _leading_vote()
	if node >= 0:
		_host_resolve_travel(node)


func party_size() -> int:
	if not is_coop():
		return 1
	return maxi(1, NetManager.connected_players)


# Votes that point at a node still reachable from the current position.
func _valid_votes() -> Dictionary:
	if GameManager.run_state == null:
		return {}
	var reachable: Array = GameManager.run_state.reachable()
	var out: Dictionary = {}
	for pid in votes:
		if int(votes[pid]) in reachable:
			out[pid] = int(votes[pid])
	return out


func _leading_vote() -> int:
	var tally: Dictionary = {}  # node_id -> count
	for pid in _valid_votes().values():
		tally[pid] = int(tally.get(pid, 0)) + 1
	var best: int = -1
	var best_n: int = 0
	# Host's own vote first so it wins ties deterministically.
	var host_vote: int = int(votes.get(NetManager.local_player_id, -1)) if is_coop() else -1
	for node in tally:
		var n: int = int(tally[node])
		if n > best_n or (n == best_n and node == host_vote):
			best = int(node)
			best_n = n
	return best


# Host tally check: travel automatically once every party member has voted AND they all
# chose the same node. Disagreement waits for more votes or the host's force button.
func _try_resolve_votes() -> void:
	var valid: Dictionary = _valid_votes()
	if valid.size() < party_size():
		return
	var unique: Dictionary = {}
	for node in valid.values():
		unique[node] = true
	if unique.size() == 1:
		_host_resolve_travel(int(valid.values()[0]))


func _host_resolve_travel(node_id: int) -> void:
	NetManager.send("run_travel", {"node": node_id})
	votes.clear()
	votes_changed.emit()
	GameManager.run_travel_to(node_id)  # host travels + loads the node; clients via run_travel


# ── relay receive ───────────────────────────────────────────────────────────────
func _on_net_message(type: String, msg: Dictionary, from_player: int) -> void:
	match type:
		"run_start":
			# Client: rebuild the identical map and join the party on it.
			if is_coop_client():
				_flow_active = true
				votes.clear()
				GameManager.run_loop = int(msg.get("loop", 0))
				GameManager.start_run(int(msg.get("difficulty", 0)), int(msg.get("seed", 0)))
				_change_scene(SCENE_RUN_MAP)
		"run_vote":
			votes[from_player] = int(msg.get("node", -1))
			votes_changed.emit()
			if is_coop_host():
				_try_resolve_votes()
		"run_travel":
			# Host already travelled when it resolved; clients apply the same move.
			if is_coop_client():
				votes.clear()
				votes_changed.emit()
				GameManager.coop_apply_travel(int(msg.get("node", -1)))
		"run_return":
			# Host finished a node — follow the party back to the map.
			if is_coop_client():
				votes.clear()
				votes_changed.emit()
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
	if t == RunMap.TYPE_MERCHANT or t == RunMap.TYPE_CAMPFIRE or t == RunMap.TYPE_EVENT:
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
	# Co-op host: pull the whole party back to the map together.
	if is_coop_host():
		NetManager.send("run_return", {})
	votes.clear()
	votes_changed.emit()
	_change_scene(SCENE_RUN_MAP)


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Deferred: scene changes are requested from signal handlers (mid-tree-iteration).
	tree.call_deferred("change_scene_to_file", path)
