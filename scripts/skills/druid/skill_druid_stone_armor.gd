extends Node2D

# Stone Armor — six rotating stone shards orbit the caster. Each shard absorbs
# one incoming hit before shattering. Lifetime 12 s or until all shards spent.
# Unique "stone_armor_grinder": shards also deal contact damage while spinning.

const LIFETIME: float = 12.0
const ORBIT_RADIUS: float = 70.0
const ROTATION_SPEED: float = 2.4
const NUM_SHARDS: int = 6
const GRINDER_TICK: float = 0.4
const GRINDER_DAMAGE_MULT: float = 0.6

var damage: int = 18
var visual_only: bool = false
var grinder_active: bool = false
var grinder_timer: float = 0.0
var rotation_t: float = 0.0
var shards: Array = []  # Array[Sprite2D]
var caster: Node2D = null
var charges_remaining: int = 1
var alive: bool = true


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	caster = ctx.caster
	# Charges = 1 base + 1 per stone_armor_charges stack.
	var charge_stacks: int = 0
	if caster:
		var ss = caster.get_node_or_null("SkillSystem")
		if ss and ss.has_method("get_modifier"):
			charge_stacks = int(ss.call("get_modifier", 2, "stone_armor_charges"))
	charges_remaining = 1 + charge_stacks
	# Grinder — the skill-block variant (ctx.transform) or the unique — converts
	# the armor into damaging spinning blades.
	grinder_active = ctx.transform == "stone_armor_grinder"
	if not grinder_active and caster and InventorySystem and InventorySystem.has_method("has_unique"):
		grinder_active = bool(InventorySystem.call("has_unique", "stone_armor_grinder"))


func _ready() -> void:
	z_index = 30
	process_mode = Node.PROCESS_MODE_INHERIT
	# Build shards.
	var tex: Texture2D = null
	var path: String = "res://assets/sprites/effects/stone_armor_chunk.png"
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	for i in NUM_SHARDS:
		var s := Sprite2D.new()
		s.texture = tex
		s.scale = Vector2(0.35, 0.35)
		s.modulate = Color(0.85, 0.78, 0.55, 1)
		s.z_index = 31
		add_child(s)
		shards.append(s)
	_place_shards(0.0)
	# Tell the player to start absorbing hits (non-visual-only).
	if not visual_only and caster:
		caster.set("stone_armor_charges", charges_remaining)
		# Name ourselves so player.take_damage can find us.
		name = "StoneArmor"
		# Reparent under caster so we follow.
		var prev := get_parent()
		if prev and prev != caster:
			prev.remove_child(self)
			caster.add_child(self)
			position = Vector2.ZERO
	# Auto-cleanup.
	var t := get_tree().create_timer(LIFETIME)
	t.timeout.connect(_finish)


func _process(delta: float) -> void:
	if not alive:
		return
	rotation_t += delta * ROTATION_SPEED
	_place_shards(rotation_t)
	# Grinder unique — tick contact damage on nearby enemies.
	if grinder_active and not visual_only:
		grinder_timer -= delta
		if grinder_timer <= 0.0:
			grinder_timer = GRINDER_TICK
			_grinder_damage()


func _place_shards(t: float) -> void:
	var visible_count: int = max(charges_remaining, 0)
	# If charges < 6, show fewer shards but keep ring intact.
	if visible_count <= 0:
		# Show 1 ghost shard while dying so the visual still pops.
		visible_count = 0
	for i in shards.size():
		var s: Sprite2D = shards[i]
		if not is_instance_valid(s):
			continue
		var on: bool = i < visible_count or (visible_count == 0 and i < 1)
		s.visible = on
		if on:
			var ang: float = t + (TAU / float(NUM_SHARDS)) * float(i)
			s.position = Vector2(cos(ang), sin(ang)) * ORBIT_RADIUS
			s.rotation = ang


func _grinder_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var dmg: int = int(round(float(damage) * GRINDER_DAMAGE_MULT))
	var center: Vector2 = global_position
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if center.distance_to((e as Node2D).global_position) <= ORBIT_RADIUS + 26.0:
			if e.has_method("take_damage"):
				e.take_damage(dmg, center)


# Called by player.take_damage when a hit is absorbed.
func on_charge_consumed() -> void:
	charges_remaining = max(0, charges_remaining - 1)
	# Visually crack a shard.
	for i in shards.size():
		var s: Sprite2D = shards[i]
		if s and s.visible:
			var tw := s.create_tween().set_parallel(true)
			tw.tween_property(s, "modulate:a", 0.0, 0.25)
			tw.tween_property(s, "scale", s.scale * 0.4, 0.25)
			break
	if charges_remaining <= 0:
		_finish()


func _finish() -> void:
	if not alive:
		return
	alive = false
	if caster and caster.has_method("set"):
		caster.set("stone_armor_charges", 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
