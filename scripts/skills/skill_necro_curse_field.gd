extends Node2D

# Curse Field — places a circular hex on the ground at the target. Any enemy
# inside takes +50% damage from all sources for as long as they stand in it.
# Lasts 8 seconds (talent transform of Raise Knight). The "Curse Field" unique
# (curse_field_harvest): enemies dying inside extend the field +1s (cap +5s)
# and heal your minions 10% of their max HP.

const LIFETIME: float = 8.0
const RADIUS: float = 200.0
const DMG_AMP: float = 0.50
const HARVEST_EXTEND: float = 1.0
const HARVEST_EXTEND_CAP: float = 5.0
const HARVEST_HEAL_FRACTION: float = 0.10

var visual_only: bool = false
var sprite: Sprite2D = null
var marked: Dictionary = {}  # enemy_instance_id -> true (for cleanup)
var life_left: float = LIFETIME
var _extended: float = 0.0
var _fading: bool = false


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5  # under enemies but above floor
	sprite = Sprite2D.new()
	var path := "res://assets/sprites/effects/curse_field_zone.png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.modulate = Color(0.85, 0.4, 1.0, 0.85)
	# Scale to roughly RADIUS*2 px diameter.
	if sprite.texture:
		var src_w: float = float(sprite.texture.get_size().x)
		if src_w > 1.0:
			var sc: float = (RADIUS * 2.0) / src_w
			sprite.scale = Vector2(sc, sc)
	add_child(sprite)
	# Slow rotation for visual flair.
	var rot := sprite.create_tween().set_loops()
	rot.tween_property(sprite, "rotation", sprite.rotation + TAU, 6.0)


func _physics_process(delta: float) -> void:
	# Manual lifetime countdown (a one-shot timer couldn't be extended by the
	# harvest unique). Fade out over the final 0.6s, then clean up.
	life_left -= delta
	if life_left <= 0.6 and not _fading:
		_fading = true
		if sprite:
			var fade := sprite.create_tween()
			fade.tween_property(sprite, "modulate:a", 0.0, 0.6)
	if life_left <= 0.0:
		_finish()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	var harvest: bool = (
		InventorySystem != null and InventorySystem.has_unique("curse_field_harvest")
	)
	# Mark every enemy currently inside the radius with a damage-amp meta.
	# Damage callers read this through enemy.take_damage scaling below.
	var still_inside: Dictionary = {}
	var alive_ids: Dictionary = {}
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		alive_ids[e.get_instance_id()] = true
		if bool(e.get("dead")):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d <= RADIUS:
			(e as Node2D).set_meta("curse_amp", DMG_AMP)
			still_inside[e.get_instance_id()] = true
			marked[e.get_instance_id()] = true
	# Anyone we marked who is no longer alive died INSIDE (or right after
	# leaving — close enough): harvest them.
	if harvest:
		for id in marked.keys():
			if still_inside.has(id) or alive_ids.has(id):
				continue
			_harvest_soul()
	# Clear the amp on enemies that left the zone.
	for id in marked.keys():
		if still_inside.has(id):
			continue
		# Look up by instance — Godot has no direct lookup, so iterate the
		# enemy group once and clear if matches. Cheap enough at typical wave
		# sizes; rare event.
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.get_instance_id() == id:
				(e as Node2D).set_meta("curse_amp", 0.0)
				break
	# Forget cleared ones.
	for id in marked.keys():
		if not still_inside.has(id):
			marked.erase(id)


func _harvest_soul() -> void:
	if _extended < HARVEST_EXTEND_CAP:
		var add: float = minf(HARVEST_EXTEND, HARVEST_EXTEND_CAP - _extended)
		_extended += add
		life_left += add
		_fading = false
		if sprite:
			sprite.modulate.a = 0.85
	# Heal the player's minions.
	var tree := get_tree()
	if tree == null:
		return
	for ally in tree.get_nodes_in_group("pet_ally"):
		if not is_instance_valid(ally) or bool(ally.get("dead")):
			continue
		var max_hp: int = int(ally.get("max_hp")) if ally.get("max_hp") != null else 0
		var hp: int = int(ally.get("hp")) if ally.get("hp") != null else 0
		if max_hp > 0:
			ally.set("hp", mini(max_hp, hp + int(round(float(max_hp) * HARVEST_HEAL_FRACTION))))
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.85, 0.4, 1.0, 1), 6)


func _finish() -> void:
	set_physics_process(false)
	if visual_only:
		queue_free()
		return
	# Strip the curse meta from everyone we marked.
	var tree := get_tree()
	if tree != null:
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				(e as Node2D).set_meta("curse_amp", 0.0)
	queue_free()
