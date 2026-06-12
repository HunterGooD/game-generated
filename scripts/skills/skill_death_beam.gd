extends Node2D

# Death Beam — talent transform of Chain Lightning: an instant focused beam that
# damages every enemy along a straight line toward the cursor. The cl_jumps
# modifier extends the beam's length (wired in as length_bonus).

const BASE_LENGTH: float = 900.0
const HALF_WIDTH: float = 40.0
const FADE_TIME: float = 0.3

var damage: int = 20
var direction: Vector2 = Vector2.RIGHT
var beam_length: float = BASE_LENGTH
var _visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	damage = ctx.damage
	direction = ctx.direction
	_visual_only = ctx.is_visual_only
	beam_length = BASE_LENGTH + float(ctx.get_mod("length_bonus", 0.0))


func _ready() -> void:
	# Abyssal Lens unique — a second beam fires straight backwards.
	var twin: bool = InventorySystem != null and InventorySystem.has_unique("beam_twin")
	_draw_beam(direction)
	if twin:
		_draw_beam(-direction)
	if VfxManager:
		VfxManager.screen_shake(6.0, 0.18)
	# Damage only on the caster's machine (visual-only copies just show the beam).
	if not _visual_only:
		_damage_line(direction)
		if twin:
			_damage_line(-direction)
	var t := get_tree().create_timer(FADE_TIME + 0.1)
	t.timeout.connect(queue_free)


func _damage_line(dir: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to_e: Vector2 = (e as Node2D).global_position - global_position
		var along: float = to_e.dot(dir)
		if along < 0.0 or along > beam_length:
			continue
		# dir is normalized, so |cross| is the perpendicular distance.
		if abs(to_e.cross(dir)) > HALF_WIDTH:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)


func _draw_beam(dir: Vector2) -> void:
	var core := Line2D.new()
	core.add_point(Vector2.ZERO)
	core.add_point(dir * beam_length)
	core.width = 14.0
	core.default_color = Color(0.75, 0.35, 1.0, 0.95)
	core.z_index = 180
	add_child(core)
	var glow := Line2D.new()
	glow.add_point(Vector2.ZERO)
	glow.add_point(dir * beam_length)
	glow.width = 34.0
	glow.default_color = Color(0.45, 0.15, 0.7, 0.4)
	glow.z_index = 179
	add_child(glow)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(core, "modulate:a", 0.0, FADE_TIME)
	tw.tween_property(glow, "modulate:a", 0.0, FADE_TIME)
