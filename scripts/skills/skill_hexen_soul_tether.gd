extends Node2D

# Soul Tether — links every currently hex-marked enemy with crimson chains.
# Any damage one takes mirrors at 35% to every linked enemy for 8 s.
# Tether Shock unique: large hits stun linked enemies briefly.

const LINK_DURATION: float = 8.0
const MIRROR_FRAC: float = 0.35
const SHOCK_THRESHOLD_PCT: float = 0.50

var damage: int = 14
var visual_only: bool = false
var tether_shock: bool = false
var linked: Array = []  # Array[Node]
var life_t: float = LINK_DURATION


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	if InventorySystem and InventorySystem.has_method("has_unique"):
		tether_shock = bool(InventorySystem.call("has_unique", "hexen_tether_shock"))


func _ready() -> void:
	z_index = 30
	if visual_only:
		var t := get_tree().create_timer(LINK_DURATION)
		t.timeout.connect(queue_free)
		return
	# Gather all hex-marked enemies.
	var tree := get_tree()
	if tree:
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			if e.get("dead") == true:
				continue
			if bool(e.get_meta("hex_marked", false)):
				linked.append(e)
				e.set_meta("tether_node", self)
				# Tethering deepens the curse (visible stack).
				if e.has_method("add_curse_stack"):
					e.call("add_curse_stack")
	if linked.size() < 2:
		# Need at least 2 marked enemies. Detonate the single mark for value.
		if linked.size() == 1 and linked[0].has_meta("hex_mark_node"):
			var node = linked[0].get_meta("hex_mark_node")
			if node and is_instance_valid(node) and node.has_method("detonate"):
				node.call("detonate")
		queue_free()
		return
	if VfxManager:
		VfxManager.screen_flash(Color(0.95, 0.18, 0.28, 0.18), 0.25)


func _process(delta: float) -> void:
	if visual_only:
		return
	life_t -= delta
	if life_t <= 0.0:
		_finish()
		return
	# Cull invalid links.
	for i in range(linked.size() - 1, -1, -1):
		var n = linked[i]
		if not is_instance_valid(n) or (n.get("dead") == true):
			linked.remove_at(i)
	if linked.size() < 2:
		_finish()


# Called from enemy.take_damage when a tethered enemy is hit. Mirrors a
# fraction of the damage to other linked enemies.
func mirror_damage(source: Node, amount: int) -> void:
	for n in linked:
		if not is_instance_valid(n) or n == source:
			continue
		if n.has_method("take_damage"):
			var mirror: int = max(1, int(round(float(amount) * MIRROR_FRAC)))
			n.call(
				"take_damage",
				mirror,
				(source as Node2D).global_position if source is Node2D else global_position
			)
			# Tether Shock — stun if the original hit was huge.
			if tether_shock and n.get("max_hp") != null and int(n.get("max_hp")) > 0:
				var frac: float = float(amount) / float(n.get("max_hp"))
				if frac >= SHOCK_THRESHOLD_PCT and n.has_method("apply_slow"):
					n.call("apply_slow", 0.6, 0.05)


func _finish() -> void:
	for n in linked:
		if is_instance_valid(n):
			n.set_meta("tether_node", null)
	queue_free()
