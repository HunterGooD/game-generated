extends Node

# Routes NetManager messages into the game world.
# Lives as a child of game_world.tscn when multiplayer is active.
# Handles: remote players, class picks, chest spawns, skill replication (VFX),
#          host-authoritative enemy sync (spawn/state/death/hit).

const REMOTE_PLAYER_SCENE: PackedScene = preload("res://scenes/entities/remote_player.tscn")
const LOOT_CHEST_SCENE: PackedScene = preload("res://scenes/pickups/loot_chest.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss.tscn")
const MERCHANT_SCENE: PackedScene = preload("res://scenes/pickups/merchant.tscn")
const WAVE_PORTAL_SCENE: PackedScene = preload("res://scenes/pickups/wave_portal.tscn")
const NECRO_MINION_SCENE: PackedScene = preload("res://scenes/entities/necro_minion.tscn")
const SPIRIT_PET_SCENE: PackedScene = preload("res://scenes/entities/spirit_pet.tscn")

# Replicated VFX that must KEEP physics_process so they actually travel on the
# remote peer's screen. Their damage areas are already disabled by
# _disable_damage_areas, so they only animate — they don't double-hit.
const MOVING_PROJECTILE_PATHS: Dictionary = {
	"res://scenes/combat/player/magic_bolt.tscn": true,
	"res://scenes/combat/player/thrown_dagger.tscn": true,
	"res://scenes/combat/player/melee_swing.tscn": true,
}

var game_world: Node = null
var remote_players: Dictionary = {}  # player_id (int) -> RemotePlayer
var pending_classes: Dictionary = {}  # player_id -> class_id
var enemy_registry: Dictionary = {}  # network_id (int) -> Node (enemy or boss)
# Host-authoritative summons. On the host: real minions/pets (run AI + combat).
# On every other peer: visual puppets driven by host minion_state broadcasts.
var minion_registry: Dictionary = {}  # network_id (int) -> Node (minion or pet)
var next_minion_id: int = 1
var broadcast_timer: float = 0.0
var enemy_state_timer: float = 0.0
var next_enemy_id: int = 1

# Client-side replicated wave-break props. Host keeps its own copies via
# enemy_spawner — these are ONLY used by non-host peers.
var current_merchant_local: Node = null
var current_portal_local: Node = null

# Co-op pause arbitration. Tree only pauses when EVERY connected player
# has their pause menu open.
var local_pause_requested: bool = false
var peer_pause_state: Dictionary = {}  # player_id -> bool

const POS_BROADCAST_INTERVAL: float = 0.05  # 20 Hz player position
const ENEMY_STATE_INTERVAL: float = 0.1  # 10 Hz enemy state batch


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind_world(world: Node) -> void:
	game_world = world
	if NetManager:
		if not NetManager.message_received.is_connected(_on_net_message):
			NetManager.message_received.connect(_on_net_message)
		if not NetManager.player_disconnected.is_connected(_on_peer_disconnected):
			NetManager.player_disconnected.connect(_on_peer_disconnected)
	# Once bound, broadcast our class so peers' remote_players configure right.
	call_deferred("_broadcast_local_class")


func _broadcast_local_class() -> void:
	if NetManager == null or GameManager == null:
		return
	var class_id: String = String(GameManager.player_class)
	if class_id != "":
		NetManager.send("lobby_class", {"class_id": class_id})


func spawn_remote_players() -> void:
	if NetManager == null:
		return
	for pid in NetManager.max_players:
		if pid == NetManager.local_player_id:
			continue
		var rp: CharacterBody2D = REMOTE_PLAYER_SCENE.instantiate()
		rp.set_player_id(pid)
		game_world.add_child(rp)
		rp.call("set_initial_position", _spawn_offset_for(pid))
		remote_players[pid] = rp
		# If we already know their class (cached during lobby), apply now.
		if pending_classes.has(pid):
			rp.apply_class(String(pending_classes[pid]))


func _spawn_offset_for(pid: int) -> Vector2:
	var center := Vector2(1344, 864)
	var offsets: Array = [Vector2(0, 0), Vector2(140, 0), Vector2(-140, 0), Vector2(0, 140)]
	if pid < offsets.size():
		return center + offsets[pid]
	return center


func remove_remote_player(pid: int) -> void:
	if remote_players.has(pid):
		var rp = remote_players[pid]
		if is_instance_valid(rp):
			rp.queue_free()
		remote_players.erase(pid)


# ─────────────────────────────────────────────────────────────────────────────
# Broadcast loop
func _process(delta: float) -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	broadcast_timer -= delta
	if broadcast_timer <= 0.0:
		broadcast_timer = POS_BROADCAST_INTERVAL
		_broadcast_local_state()
	# Host also broadcasts enemy + summon state.
	if NetManager.is_host:
		enemy_state_timer -= delta
		if enemy_state_timer <= 0.0:
			enemy_state_timer = ENEMY_STATE_INTERVAL
			_broadcast_enemy_state()
			_broadcast_minion_state()


func _broadcast_local_state() -> void:
	if game_world == null:
		return
	var p = game_world.get_node_or_null("Player")
	if p == null or not is_instance_valid(p):
		return
	var anim_state: String = "idle"
	var sprite = p.get_node_or_null("Visual")
	if sprite and sprite is AnimatedSprite2D:
		anim_state = (sprite as AnimatedSprite2D).animation
	var facing: bool = true
	if p.get("facing_right") != null:
		facing = bool(p.get("facing_right"))
	(
		NetManager
		. send(
			"pos",
			{
				"x": (p as Node2D).global_position.x,
				"y": (p as Node2D).global_position.y,
				"fr": facing,
				"a": anim_state,
			}
		)
	)


func _broadcast_enemy_state() -> void:
	if enemy_registry.is_empty():
		return
	var batch: Array = []
	var to_remove: Array = []
	for id in enemy_registry.keys():
		var node = enemy_registry[id]
		if not is_instance_valid(node):
			to_remove.append(id)
			continue
		if node.has_method("get") and node.get("dead") == true:
			# Skip dead enemies; their death will be broadcast separately.
			continue
		var n2d := node as Node2D
		var hp_val: int = int(node.get("hp")) if node.get("hp") != null else 0
		(
			batch
			. append(
				{
					"id": int(id),
					"x": n2d.global_position.x,
					"y": n2d.global_position.y,
					"hp": hp_val,
				}
			)
		)
	for id in to_remove:
		enemy_registry.erase(id)
	if not batch.is_empty():
		NetManager.send("enemy_state", {"enemies": batch})


# ─────────────────────────────────────────────────────────────────────────────
# Host helpers — called by enemy_spawner when it spawns an enemy or boss.
func register_enemy(enemy: Node) -> int:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return -1
	var id: int = next_enemy_id
	next_enemy_id += 1
	enemy.set("network_id", id)
	enemy_registry[id] = enemy
	# Broadcast spawn immediately so clients instantiate puppets.
	var pos: Vector2 = (enemy as Node2D).global_position
	# Pull config off the enemy for clients.
	var cfg_type: String = (
		String(enemy.get("enemy_type")) if enemy.get("enemy_type") != null else "skeleton"
	)
	var max_hp: int = int(enemy.get("max_hp")) if enemy.get("max_hp") != null else 30
	var dmg: int = int(enemy.get("attack_damage")) if enemy.get("attack_damage") != null else 6
	var ranged: bool = bool(enemy.get("is_ranged")) if enemy.get("is_ranged") != null else false
	var scale_v: float = (
		float(enemy.get("sprite_scale")) if enemy.get("sprite_scale") != null else 0.34
	)
	(
		NetManager
		. send(
			"enemy_spawn",
			{
				"id": id,
				"type": cfg_type,
				"x": pos.x,
				"y": pos.y,
				"hp": max_hp,
				"dmg": dmg,
				"ranged": ranged,
				"scale": scale_v,
			}
		)
	)
	return id


func register_boss(boss: Node) -> int:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return -1
	var id: int = next_enemy_id
	next_enemy_id += 1
	boss.set("network_id", id)
	enemy_registry[id] = boss
	var pos: Vector2 = (boss as Node2D).global_position
	var boss_id: String = String(boss.get("boss_id")) if boss.get("boss_id") != null else ""
	var wave: int = int(boss.get("spawn_wave")) if boss.get("spawn_wave") != null else 1
	(
		NetManager
		. send(
			"boss_spawn",
			{
				"id": id,
				"boss_id": boss_id,
				"wave": wave,
				"x": pos.x,
				"y": pos.y,
			}
		)
	)
	return id


func broadcast_enemy_death(id: int, pos: Vector2, gold_min: int, gold_max: int, xp: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	(
		NetManager
		. send(
			"enemy_death",
			{
				"id": id,
				"x": pos.x,
				"y": pos.y,
				"gold_min": gold_min,
				"gold_max": gold_max,
				"xp": xp,
			}
		)
	)
	enemy_registry.erase(id)


# ─────────────────────────────────────────────────────────────────────────────
# Host-authoritative summons (pets / skeletons / knights).
#
# All summoned units live on the HOST, which owns enemy simulation — so they
# actually tank, pull aggro and deal damage. Clients never spawn real units:
# a client casting a summon sends `summon_request`; everyone (incl. the caster)
# receives `minion_spawn` and renders a visual puppet. `kind` is one of
# "skeleton" / "knight" / "spirit"; `pet` carries the spirit flavour (wolf/bear).

# Client → host: ask the host to spawn our summon. Called by summon skills when
# we're a non-host peer (the local copy plays only its cast flash).
func request_summon(
	kind: String, pet: String, pos: Vector2, count: int, dmg: int, armor: int
) -> void:
	if NetManager == null or not NetManager.is_multiplayer or NetManager.is_host:
		return
	(
		NetManager
		. send(
			"summon_request",
			{
				"kind": kind,
				"pet": pet,
				"x": pos.x,
				"y": pos.y,
				"count": count,
				"dmg": dmg,
				"armor": armor,
			}
		)
	)


# Client → host: empower our host-side minions (Blood Pact).
func request_blood_pact(duration: float, dmg_mult: float, speed_mult: float) -> void:
	if NetManager == null or not NetManager.is_multiplayer or NetManager.is_host:
		return
	(
		NetManager
		. send(
			"blood_pact",
			{"duration": duration, "dmg_mult": dmg_mult, "speed_mult": speed_mult}
		)
	)


# Host: spawn the authoritative summon(s) and replicate puppets to every peer.
# owner_pid identifies which player owns them (for follow + re-cast refresh).
func host_spawn_summon(
	kind: String, pet: String, owner_pid: int, pos: Vector2, count: int, dmg: int, armor: int
) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	if game_world == null:
		return
	_despawn_owner_minions(owner_pid, kind)
	var owner_node: Node = _summon_owner_node(owner_pid)
	var n: int = max(1, count)
	for i in n:
		var unit: Node2D = _make_summon_node(kind, pet, dmg, armor)
		if unit == null:
			continue
		game_world.add_child(unit)
		unit.global_position = _summon_spawn_pos(pos, i, n, kind)
		unit.set("owner_caster", owner_node)
		unit.set("owner_player_id", owner_pid)
		var nid: int = next_minion_id
		next_minion_id += 1
		unit.set("network_id", nid)
		minion_registry[nid] = unit
		(
			NetManager
			. send(
				"minion_spawn",
				{
					"id": nid,
					"kind": kind,
					"pet": pet,
					"x": unit.global_position.x,
					"y": unit.global_position.y,
					"owner": owner_pid,
					"dmg": dmg,
					"armor": armor,
				}
			)
		)


func _make_summon_node(kind: String, pet: String, dmg: int, armor: int) -> Node2D:
	if kind == "spirit":
		var pet_node: Node2D = SPIRIT_PET_SCENE.instantiate()
		if pet_node.has_method("configure"):
			pet_node.call("configure", pet if pet != "" else "wolf", dmg)
		return pet_node
	var minion: Node2D = NECRO_MINION_SCENE.instantiate()
	if minion.has_method("configure"):
		minion.call("configure", kind, dmg)
	if kind == "knight" and armor > 0 and minion.has_method("apply_knight_armor_bonus"):
		minion.call("apply_knight_armor_bonus", armor)
	return minion


func _summon_spawn_pos(center: Vector2, idx: int, count: int, kind: String) -> Vector2:
	if kind == "knight":
		return center + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	var spread: float = 60.0 if kind == "spirit" else 48.0
	var ang: float = (TAU / float(max(1, count))) * float(idx) + randf() * 0.3
	return center + Vector2(cos(ang), sin(ang)) * spread


func _summon_owner_node(owner_pid: int) -> Node:
	if NetManager and owner_pid == NetManager.local_player_id:
		return game_world.get_node_or_null("Player")
	return remote_players.get(owner_pid, null)


# Despawn an owner's existing summons before a re-cast (refresh semantics).
# Skeletons and knights share the necro_minion scene but have separate caps, so
# the kind is matched; "spirit" matches all of that owner's pets.
func _despawn_owner_minions(owner_pid: int, kind: String) -> void:
	for nid in minion_registry.keys().duplicate():
		var unit = minion_registry.get(nid, null)
		if not is_instance_valid(unit):
			minion_registry.erase(nid)
			continue
		if int(unit.get("owner_player_id")) != owner_pid:
			continue
		var matches: bool = false
		if kind == "spirit":
			matches = unit.is_in_group("spirit_pet")
		else:
			matches = (
				unit.is_in_group("necro_minion") and String(unit.get("minion_kind")) == kind
			)
		if matches:
			minion_registry.erase(nid)
			NetManager.send("minion_death", {"id": int(nid)})
			unit.queue_free()


func _broadcast_minion_state() -> void:
	if minion_registry.is_empty():
		return
	var batch: Array = []
	var to_remove: Array = []
	for id in minion_registry.keys():
		var node = minion_registry[id]
		if not is_instance_valid(node):
			to_remove.append(id)
			continue
		if node.get("dead") == true:
			continue
		var n2d := node as Node2D
		var hp_val: int = int(node.get("hp")) if node.get("hp") != null else 0
		batch.append({"id": int(id), "x": n2d.global_position.x, "y": n2d.global_position.y, "hp": hp_val})
	for id in to_remove:
		minion_registry.erase(id)
	if not batch.is_empty():
		NetManager.send("minion_state", {"minions": batch})


# Host: a local authoritative minion died — drop peers' puppets.
func broadcast_minion_death(network_id: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	minion_registry.erase(network_id)
	NetManager.send("minion_death", {"id": int(network_id)})


# Client: spawn a visual puppet mirroring the host's authoritative summon.
func _spawn_puppet_minion(msg: Dictionary) -> void:
	if game_world == null:
		return
	var id: int = int(msg.get("id", -1))
	if id < 0 or minion_registry.has(id):
		return
	var kind: String = String(msg.get("kind", "skeleton"))
	var pet: String = String(msg.get("pet", ""))
	var dmg: int = int(msg.get("dmg", 10))
	var armor: int = int(msg.get("armor", 0))
	var unit: Node2D = _make_summon_node(kind, pet, dmg, armor)
	if unit == null:
		return
	game_world.add_child(unit)
	unit.global_position = Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	unit.set("network_id", id)
	unit.set("owner_player_id", int(msg.get("owner", -1)))
	if unit.has_method("set_puppet"):
		unit.call("set_puppet")
	minion_registry[id] = unit


func _apply_minion_state(msg: Dictionary) -> void:
	var arr: Array = msg.get("minions", [])
	for entry in arr:
		var id: int = int(entry.get("id", -1))
		var node = minion_registry.get(id, null)
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("apply_remote_state"):
			node.call("apply_remote_state", entry)


func _apply_minion_death(msg: Dictionary) -> void:
	var id: int = int(msg.get("id", -1))
	var node = minion_registry.get(id, null)
	minion_registry.erase(id)
	if is_instance_valid(node):
		if node.has_method("_die"):
			node.call("_die")
		else:
			node.queue_free()


# Host: empower a player's authoritative necro minions (Blood Pact from a peer).
func host_apply_blood_pact(
	owner_pid: int, duration: float, dmg_mult: float, speed_mult: float
) -> void:
	if NetManager == null or not NetManager.is_host:
		return
	for nid in minion_registry.keys():
		var unit = minion_registry.get(nid, null)
		if not is_instance_valid(unit):
			continue
		if int(unit.get("owner_player_id")) != owner_pid:
			continue
		if unit.is_in_group("necro_minion") and unit.has_method("apply_blood_pact"):
			unit.call("apply_blood_pact", duration, dmg_mult, speed_mult)


# ─────────────────────────────────────────────────────────────────────────────
# Receive
func _on_net_message(type: String, msg: Dictionary, from_player: int) -> void:
	match type:
		"pos":
			var rp = remote_players.get(from_player, null)
			if rp and is_instance_valid(rp):
				rp.update_target(msg)
		"lobby_class", "class_pick":
			var class_id: String = String(msg.get("class_id", "mage"))
			pending_classes[from_player] = class_id
			var rp = remote_players.get(from_player, null)
			if rp and is_instance_valid(rp):
				rp.apply_class(class_id)
		"rp_hp":
			var target: int = int(msg.get("target", -1))
			var hp: int = int(msg.get("hp", 0))
			if target == NetManager.local_player_id:
				if GameManager:
					GameManager.player_hp = hp
					# Host-authoritative damage drove us to 0 → go downed
					# (co-op) instead of silently sitting at 0 HP.
					if hp <= 0:
						GameManager.register_lethal_blow()
					GameManager.player_stats_changed.emit()
			else:
				var rp2 = remote_players.get(target, null)
				if rp2 and is_instance_valid(rp2):
					rp2.apply_state({"hp": hp})
		"chest_spawn":
			var owner_id: int = int(msg.get("owner", 0))
			var wave: int = int(msg.get("wave", 1))
			var x: float = float(msg.get("x", 1344.0))
			var y: float = float(msg.get("y", 864.0))
			if owner_id == NetManager.local_player_id and game_world:
				var chest: Node2D = LOOT_CHEST_SCENE.instantiate()
				game_world.add_child(chest)
				chest.global_position = Vector2(x, y)
				if chest.has_method("configure"):
					chest.call("configure", wave)
				var forced_rar: String = String(msg.get("forced_rarity", ""))
				if forced_rar != "":
					chest.set_meta("forced_rarity", forced_rar)
		"skill_cast":
			_replicate_skill_cast(msg)
		"enemy_spawn":
			_spawn_puppet_enemy(msg)
		"enemy_state":
			_apply_enemy_state(msg)
		"enemy_death":
			_apply_enemy_death(msg)
		"enemy_hit":
			# Host applies damage from a client's hit message.
			if NetManager.is_host:
				var id: int = int(msg.get("id", -1))
				var damage: int = int(msg.get("damage", 0))
				var node = enemy_registry.get(id, null)
				if node and is_instance_valid(node) and node.has_method("take_damage"):
					node.call("take_damage", damage, Vector2.ZERO)
		"summon_request":
			# Client asked us (host) to spawn its summon authoritatively.
			if NetManager.is_host:
				host_spawn_summon(
					String(msg.get("kind", "skeleton")),
					String(msg.get("pet", "")),
					from_player,
					Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0))),
					int(msg.get("count", 1)),
					int(msg.get("dmg", 10)),
					int(msg.get("armor", 0))
				)
		"minion_spawn":
			_spawn_puppet_minion(msg)
		"minion_state":
			_apply_minion_state(msg)
		"minion_death":
			_apply_minion_death(msg)
		"blood_pact":
			if NetManager.is_host:
				host_apply_blood_pact(
					from_player,
					float(msg.get("duration", 10.0)),
					float(msg.get("dmg_mult", 1.75)),
					float(msg.get("speed_mult", 1.3))
				)
		"boss_spawn":
			_spawn_puppet_boss(msg)
		"boss_state":
			var bid: int = int(msg.get("id", -1))
			var b_node = enemy_registry.get(bid, null)
			if b_node and is_instance_valid(b_node) and b_node.has_method("apply_remote_state"):
				b_node.call("apply_remote_state", msg)
		"wave_started":
			_apply_wave_started(int(msg.get("wave", 1)))
		"wave_cleared":
			_apply_wave_cleared(int(msg.get("wave", 1)))
		"merchant_spawn":
			_spawn_remote_merchant(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
		"portal_spawn":
			_spawn_remote_portal(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
		"portal_consumed":
			_clear_remote_break_props()
		"portal_activate":
			# A client portal triggered — host advances the wave for everyone.
			if NetManager.is_host:
				var spawner: Node = _find_spawner()
				if spawner and spawner.has_method("portal_activate_from_client"):
					spawner.call("portal_activate_from_client")
		"pause_request":
			peer_pause_state[from_player] = bool(msg.get("paused", false))
			_recompute_pause()
		"druid_form":
			var form_id: String = String(msg.get("form", "human"))
			var rp = remote_players.get(from_player, null)
			if rp and is_instance_valid(rp) and rp.has_method("apply_druid_form"):
				rp.call("apply_druid_form", form_id)
		"item_gift":
			# Someone in the party is sending us an item. Only the addressed
			# recipient acts on it.
			var to_pid: int = int(msg.get("to", -1))
			if NetManager and to_pid == NetManager.local_player_id:
				var item_dict = msg.get("item", null)
				if item_dict is Dictionary and InventorySystem:
					var inst: ItemInstance = ItemInstance.from_dict(item_dict)
					if inst != null:
						InventorySystem.add_item(inst)
						if AudioManager:
							AudioManager.play_sfx_path(
								"res://assets/audio/sfx/ui/ui_merchant_purchase.mp3", -8.0
							)
						if VfxManager:
							VfxManager.screen_flash(Color(1.0, 0.85, 0.4, 0.18), 0.25)
		"player_downed":
			var rp_d = remote_players.get(from_player, null)
			if rp_d and is_instance_valid(rp_d) and rp_d.has_method("set_downed"):
				rp_d.call("set_downed", true)
		"player_revived":
			var rp_r = remote_players.get(from_player, null)
			if rp_r and is_instance_valid(rp_r):
				if rp_r.has_method("set_downed"):
					rp_r.call("set_downed", false)
				rp_r.call("apply_state", {"hp": int(msg.get("hp", 0))})
		"revive":
			# A teammate is reviving the addressed player. Only that player —
			# who owns their own life state — acts on it.
			var target_pid: int = int(msg.get("target", -1))
			if NetManager and target_pid == NetManager.local_player_id and GameManager:
				GameManager.revive_player()
		"player_dead":
			var rp_x = remote_players.get(from_player, null)
			if rp_x and is_instance_valid(rp_x) and rp_x.has_method("mark_dead"):
				rp_x.call("mark_dead")


# ─────────────────────────────────────────────────────────────────────────────
# Skill replication — visual-only on remote peers.
func broadcast_skill_cast(
	skill_id: String, scene_path: String, pos: Vector2, dir: Vector2, dmg: int
) -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	(
		NetManager
		. send(
			"skill_cast",
			{
				"sid": skill_id,
				"path": scene_path,
				"x": pos.x,
				"y": pos.y,
				"dx": dir.x,
				"dy": dir.y,
				"d": dmg,
			}
		)
	)


func _replicate_skill_cast(msg: Dictionary) -> void:
	if game_world == null:
		return
	var scene_path: String = String(msg.get("path", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var node: Node = packed.instantiate()
	(node as Node2D).position = Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	node.set_meta("visual_only", true)
	var dmg: int = int(msg.get("d", 0))
	var dir: Vector2 = Vector2(float(msg.get("dx", 1.0)), float(msg.get("dy", 0.0)))
	if node.has_method("setup_with_mods"):
		node.call("setup_with_mods", dir, dmg, {"visual_only": true})
	elif node.has_method("setup"):
		node.call("setup", dir, dmg)
	game_world.add_child(node)
	# Disable damage-area collision so the visual copy can't double-damage
	# enemies. For tick-based area skills (caltrops, poison_vial, fire_wall)
	# we also stop physics_process so they don't keep scanning disabled areas.
	# Moving projectiles (magic_bolt, thrown_dagger, melee_swing) MUST keep
	# physics_process — that's how they travel on the other peer's screen.
	_disable_damage_areas(node)
	var is_moving_projectile: bool = MOVING_PROJECTILE_PATHS.get(scene_path, false)
	if not is_moving_projectile and node.has_method("set_physics_process"):
		node.set_physics_process(false)
	# Hard 8s safety free attached as a child Timer so when the VFX dies on
	# its own the timer dies with it — no orphan lambda capture, no
	# "Lambda capture at index 0 was freed" spam in the console.
	var safety := Timer.new()
	safety.one_shot = true
	safety.wait_time = 8.0
	safety.autostart = true
	safety.process_mode = Node.PROCESS_MODE_ALWAYS
	safety.timeout.connect(node.queue_free)
	node.add_child(safety)


func _disable_damage_areas(node: Node) -> void:
	# Recursively find Area2D children with collision_mask hitting the enemy
	# hurtbox layer (16) and turn monitoring off so they're VFX-only.
	if node is Area2D:
		var area := node as Area2D
		if (area.collision_mask & 16) != 0:
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)
	for child in node.get_children():
		_disable_damage_areas(child)


# ─────────────────────────────────────────────────────────────────────────────
# Puppet enemy management (clients).
func _spawn_puppet_enemy(msg: Dictionary) -> void:
	if game_world == null:
		return
	var id: int = int(msg.get("id", -1))
	if id < 0 or enemy_registry.has(id):
		return
	var enemy: Node2D = ENEMY_SCENE.instantiate()
	game_world.add_child(enemy)
	enemy.global_position = Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	# Configure puppet to match host's enemy.
	var type_id: String = String(msg.get("type", "skeleton"))
	var cfg: Dictionary = _puppet_enemy_cfg(
		type_id,
		int(msg.get("hp", 30)),
		int(msg.get("dmg", 6)),
		bool(msg.get("ranged", false)),
		float(msg.get("scale", 0.34))
	)
	if enemy.has_method("configure"):
		enemy.call("configure", cfg)
	enemy.set("is_puppet", true)
	enemy.set("network_id", id)
	enemy_registry[id] = enemy


func _puppet_enemy_cfg(
	type_id: String, hp: int, dmg: int, ranged: bool, scale_v: float
) -> Dictionary:
	var sprite_base := "res://assets/sprites/characters/"
	var sprite_dir := ""
	var tint := Color(1, 1, 1, 1)
	var aoe := false
	var direct_paths: Dictionary = {}  # if set, used instead of dir-based ones
	match type_id:
		"cultist":
			sprite_dir = "dark_cultist"
			tint = Color(1, 0.9, 0.95, 1)
		"wraith":
			sprite_dir = "ruin_wraith"
			tint = Color(0.7, 0.85, 1.2, 0.85)
		"succubus":
			tint = Color(1, 0.85, 0.95, 1)
			aoe = true
			direct_paths = {
				"idle": "res://assets/sprites/characters/succubus_idle.png",
				"walk": "res://assets/sprites/characters/succubus_walk.png",
				"attack": "res://assets/sprites/characters/succubus_attack.png",
			}
		"spider_brood":
			direct_paths = {
				"idle": "res://assets/sprites/characters/spider_brood_idle.png",
				"walk": "res://assets/sprites/characters/spider_brood_walk.png",
				"attack": "res://assets/sprites/characters/spider_brood_attack.png",
			}
		"spider_hatchling":
			direct_paths = {
				"idle": "res://assets/sprites/characters/spider_hatchling_idle.png",
				"walk": "res://assets/sprites/characters/spider_hatchling_walk.png",
				"attack": "res://assets/sprites/characters/spider_hatchling_attack.png",
			}
		_:
			sprite_dir = "skeleton_warrior"
			tint = Color(1, 1, 1, 1)
	var p_idle: String = ""
	var p_walk: String = ""
	var p_atk: String = ""
	if not direct_paths.is_empty():
		p_idle = String(direct_paths.get("idle", ""))
		p_walk = String(direct_paths.get("walk", ""))
		p_atk = String(direct_paths.get("attack", ""))
	else:
		p_idle = "%s%s/%s_idle.png" % [sprite_base, sprite_dir, sprite_dir]
		p_walk = "%s%s/%s_walk.png" % [sprite_base, sprite_dir, sprite_dir]
		p_atk = "%s%s/%s_attack.png" % [sprite_base, sprite_dir, sprite_dir]
	return {
		"type": type_id,
		"max_hp": hp,
		"move_speed": 80.0,
		"attack_damage": dmg,
		"attack_range": 220.0 if aoe else 56.0,
		"attack_cooldown": 2.6 if aoe else 1.2,
		"detection_range": 520.0 if aoe else 380.0,
		"xp_value": 0,  # puppets don't grant XP locally
		"gold_min": 0,
		"gold_max": 0,
		"sprite_idle": p_idle,
		"sprite_walk": p_walk,
		"sprite_attack": p_atk,
		"sprite_scale": scale_v,
		"tint": tint,
		"ranged": ranged,
		"aoe": aoe,
	}


func _apply_enemy_state(msg: Dictionary) -> void:
	var arr: Array = msg.get("enemies", [])
	for entry in arr:
		var id: int = int(entry.get("id", -1))
		var node = enemy_registry.get(id, null)
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("apply_remote_state"):
			node.call("apply_remote_state", entry)


func _apply_enemy_death(msg: Dictionary) -> void:
	var id: int = int(msg.get("id", -1))
	var pos: Vector2 = Vector2(float(msg.get("x", 0)), float(msg.get("y", 0)))
	var node = enemy_registry.get(id, null)
	enemy_registry.erase(id)
	if node and is_instance_valid(node):
		if node.has_method("die_remote"):
			node.call("die_remote")
		else:
			node.queue_free()
	# Local gold + XP drops at the death position — each player gets their own.
	_spawn_local_drops(
		pos, int(msg.get("gold_min", 0)), int(msg.get("gold_max", 0)), int(msg.get("xp", 0))
	)


func _spawn_local_drops(pos: Vector2, gold_min: int, gold_max: int, xp: int) -> void:
	if game_world == null:
		return
	if xp > 0:
		var xp_scene: PackedScene = load("res://scenes/pickups/xp_drop.tscn") as PackedScene
		if xp_scene:
			var xp_node: Node2D = xp_scene.instantiate()
			# CRITICAL: set position BEFORE add_child so _ready() reads the correct
			# global_position when it captures its bob/arc tween targets. Setting
			# global_position after add_child causes the drop to start tweening
			# from (0,0) — visible bug on clients where drops landed in the
			# upper-left corner.
			xp_node.position = pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
			if xp_node.has_method("setup"):
				xp_node.call("setup", xp)
			game_world.add_child(xp_node)
	var amount: int = randi_range(max(0, gold_min), max(gold_min, gold_max))
	if amount > 0:
		var gold_scene: PackedScene = load("res://scenes/pickups/gold_drop.tscn") as PackedScene
		if gold_scene:
			var gold_node: Node2D = gold_scene.instantiate()
			gold_node.position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
			if gold_node.has_method("setup"):
				gold_node.call("setup", amount)
			game_world.add_child(gold_node)


# ─────────────────────────────────────────────────────────────────────────────
# Boss puppets (clients).
func _spawn_puppet_boss(msg: Dictionary) -> void:
	if game_world == null:
		return
	var id: int = int(msg.get("id", -1))
	if id < 0 or enemy_registry.has(id):
		return
	var boss: Node2D = BOSS_SCENE.instantiate()
	game_world.add_child(boss)
	boss.global_position = Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	if boss.has_method("configure"):
		boss.call("configure", String(msg.get("boss_id", "")), int(msg.get("wave", 1)))
	boss.set("is_puppet", true)
	boss.set("network_id", id)
	enemy_registry[id] = boss
	# Wire HUD boss bar to puppet.
	var hud := _find_hud()
	if hud and hud.has_method("show_boss_bar"):
		hud.call(
			"show_boss_bar",
			String(boss.get("boss_data").get("name", "BOSS")) if boss.get("boss_data") else "BOSS",
			boss
		)


func _find_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("HUD", true, false)


func _on_peer_disconnected(pid: int) -> void:
	if pid < 0:
		if NetManager:
			NetManager.is_multiplayer = false
		# Local connection dropped — make sure we don't strand the world paused.
		local_pause_requested = false
		peer_pause_state.clear()
		_recompute_pause()
		return
	remove_remote_player(pid)
	peer_pause_state.erase(pid)
	_recompute_pause()


# Public: broadcast our class on demand (used by lobby on entering game).
func broadcast_local_class(class_id: String) -> void:
	if NetManager == null:
		return
	NetManager.send("lobby_class", {"class_id": class_id})
	pending_classes[NetManager.local_player_id] = class_id


# ─────────────────────────────────────────────────────────────────────────────
# Host broadcasts — called by enemy_spawner. No-ops on clients / solo.
func broadcast_wave_started(wave: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	NetManager.send("wave_started", {"wave": wave})


func broadcast_wave_cleared(wave: int) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	NetManager.send("wave_cleared", {"wave": wave})


func broadcast_merchant_spawn(pos: Vector2) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	NetManager.send("merchant_spawn", {"x": pos.x, "y": pos.y})


func broadcast_portal_spawn(pos: Vector2) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	NetManager.send("portal_spawn", {"x": pos.x, "y": pos.y})


func broadcast_portal_consumed() -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	NetManager.send("portal_consumed", {})


# Druid: tell peers our local player has shapeshifted (or reverted).
func broadcast_druid_form(form_id: String, duration: float) -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	NetManager.send("druid_form", {"form": form_id, "dur": duration})


# Gift an item from the local player to a specified peer. The item is
# serialized and sent over the relay; recipient adds it to their inventory
# in response to the "item_gift" message handler above.
func broadcast_item_gift(to_pid: int, item: ItemInstance) -> bool:
	if NetManager == null or not NetManager.is_multiplayer or item == null:
		return false
	if to_pid < 0 or to_pid == NetManager.local_player_id:
		return false
	(
		NetManager
		. send(
			"item_gift",
			{
				"to": to_pid,
				"item": item.to_dict(),
			}
		)
	)
	return true


# Boss HP delta broadcast — host calls this on every boss take_damage so
# clients' boss bars track in real time.
func broadcast_boss_state(boss_network_id: int, hp_v: int, max_hp_v: int, pos: Vector2) -> void:
	if NetManager == null or not NetManager.is_multiplayer or not NetManager.is_host:
		return
	if boss_network_id < 0:
		return
	(
		NetManager
		. send(
			"boss_state",
			{
				"id": boss_network_id,
				"hp": hp_v,
				"max_hp": max_hp_v,
				"x": pos.x,
				"y": pos.y,
			}
		)
	)


# ─────────────────────────────────────────────────────────────────────────────
# Client-side appliers.
func _apply_wave_started(wave: int) -> void:
	# Repaint HUD wave banner/counter via the existing GameManager signal.
	if GameManager and GameManager.has_signal("wave_started"):
		GameManager.wave_started.emit(wave)
		if wave > GameManager.highest_wave:
			GameManager.highest_wave = wave


func _apply_wave_cleared(wave: int) -> void:
	if GameManager and GameManager.has_signal("wave_cleared"):
		GameManager.wave_cleared.emit(wave)


func _spawn_remote_merchant(x: float, y: float) -> void:
	if game_world == null:
		return
	# Avoid duplicates if the message arrives twice.
	if is_instance_valid(current_merchant_local):
		return
	var m: Node2D = MERCHANT_SCENE.instantiate()
	game_world.add_child(m)
	m.global_position = Vector2(x, y)
	current_merchant_local = m


func _spawn_remote_portal(x: float, y: float) -> void:
	if game_world == null:
		return
	if is_instance_valid(current_portal_local):
		return
	var portal: Node2D = WAVE_PORTAL_SCENE.instantiate()
	game_world.add_child(portal)
	portal.global_position = Vector2(x, y)
	current_portal_local = portal
	# When the local player triggers this portal, tell the host to advance.
	if portal.has_signal("activated"):
		portal.connect("activated", _on_local_portal_activated)


func _on_local_portal_activated() -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	# Clients send activation up to the host. The host's own portal calls
	# enemy_spawner._on_portal_activated() directly via its scene signal.
	if not NetManager.is_host:
		NetManager.send("portal_activate", {})


func _clear_remote_break_props() -> void:
	if is_instance_valid(current_merchant_local) and current_merchant_local.has_method("leave"):
		current_merchant_local.call("leave")
	current_merchant_local = null
	if is_instance_valid(current_portal_local):
		current_portal_local.queue_free()
	current_portal_local = null


func _find_spawner() -> Node:
	if game_world == null:
		return null
	# enemy_spawner is a child of game_world named "EnemySpawner" in the scene.
	var s := game_world.get_node_or_null("EnemySpawner")
	if s != null:
		return s
	# Fallback: search the tree.
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.find_child("EnemySpawner", true, false)


# ─────────────────────────────────────────────────────────────────────────────
# Co-op down / revive broadcasts. Each player owns their own life state and
# tells the party when it changes; `revive` is addressed to the downed player,
# who is the authority that actually gets back up.
func broadcast_player_downed() -> void:
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("player_downed", {})


func broadcast_player_revived(hp: int) -> void:
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("player_revived", {"hp": hp})


func broadcast_player_dead() -> void:
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("player_dead", {})


func send_revive(target_player_id: int) -> void:
	if NetManager and NetManager.is_multiplayer:
		NetManager.send("revive", {"target": target_player_id})


# ─────────────────────────────────────────────────────────────────────────────
# Co-op pause arbitration. The tree only freezes when EVERY connected player
# has their pause menu open. While only one is paused, the world keeps running
# so the other can keep fighting.
func request_pause(paused: bool) -> void:
	local_pause_requested = paused
	if NetManager != null and NetManager.is_multiplayer:
		NetManager.send("pause_request", {"paused": paused})
	_recompute_pause()


func _recompute_pause() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if NetManager == null or not NetManager.is_multiplayer:
		# Solo path — pause_menu.gd controls the tree directly. Don't touch it.
		return
	# All known connected peers must report paused too, AND the local player.
	var all_paused: bool = local_pause_requested
	if all_paused:
		var expected_peers: int = remote_players.size()
		var actually_paused: int = 0
		for pid in peer_pause_state.keys():
			if pid == NetManager.local_player_id:
				continue
			if bool(peer_pause_state[pid]):
				actually_paused += 1
		if actually_paused < expected_peers:
			all_paused = false
	tree.paused = all_paused
