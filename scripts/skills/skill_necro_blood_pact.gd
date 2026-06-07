extends Node2D

# Blood Pact — sacrifices 15% of the necromancer's current HP to fully heal all
# owned minions AND grant them +75% damage and +30% move speed for 10 s.
# Crimson Vow stacks add +25% pact damage per stack.

const BUFF_DURATION: float = 10.0
const BASE_DMG_MULT: float = 1.75
const SPEED_MULT: float = 1.30
const HP_COST_PCT: float = 0.15

var visual_only: bool = false


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	var caster = mods.get("caster", null)
	if visual_only or caster == null:
		return
	# Sacrifice HP — never enough to kill the caster.
	if GameManager:
		var cost: int = max(1, int(round(float(GameManager.player_hp) * HP_COST_PCT)))
		var new_hp: int = max(1, GameManager.player_hp - cost)
		GameManager.player_hp = new_hp
		GameManager.player_stats_changed.emit()
		if VfxManager:
			VfxManager.spawn_damage_number(
				caster.global_position + Vector2(0, -22), cost, Color(1.0, 0.2, 0.3, 1)
			)
	# Pact-power upgrade.
	var pact_power: float = BASE_DMG_MULT
	var ss = caster.get_node_or_null("SkillSystem")
	if ss and ss.has_method("get_modifier"):
		var stacks: int = int(ss.call("get_modifier", 2, "necro_pact_power"))
		pact_power += 0.25 * float(stacks)
	# Multiplayer: a non-host caster's minions live on the host — ask the host to
	# empower them. Solo and host apply directly to their local minions.
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		var ns := _find_net_sync()
		if ns:
			ns.call(
				"request_blood_pact", BUFF_DURATION, pact_power, SPEED_MULT
			)
		return
	# Empower every minion owned by THIS necromancer.
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("necro_minion"):
		if not is_instance_valid(n):
			continue
		if n.get("owner_caster") != caster:
			continue
		if n.has_method("apply_blood_pact"):
			n.call("apply_blood_pact", BUFF_DURATION, pact_power, SPEED_MULT)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("NetSync")


func _ready() -> void:
	z_index = 70
	var ring := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(path):
		ring.texture = load(path) as Texture2D
	ring.modulate = Color(1.0, 0.25, 0.4, 0.85)
	ring.scale = Vector2(0.6, 0.6)
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.6, 2.6), 0.55)
	tw.tween_property(ring, "modulate:a", 0.0, 0.55)
	if VfxManager:
		VfxManager.screen_flash(Color(0.85, 0.1, 0.2, 0.18), 0.25)
		VfxManager.screen_shake(2.0, 0.12)
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(queue_free)
