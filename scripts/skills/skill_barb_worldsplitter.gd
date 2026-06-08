extends Node2D

# Worldsplitter — Titanbreaker (Barbarian) ascension R. The Barbarian splits the
# earth in a long line from the cast point. Enemies along the fissure take heavy
# damage and are knocked up; 2s later the crack detonates a second time. Counts as
# control (feeds Seismic Momentum).

const LENGTH: float = 560.0
const WIDTH: float = 90.0
const KNOCKUP: float = 260.0
const SECOND_BLAST_DELAY: float = 2.0

var damage: int = 40
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null
var _origin: Vector2 = Vector2.ZERO


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 30
	_origin = (caster as Node2D).global_position if caster is Node2D else global_position
	_draw_fissure()
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_earthquake.mp3", -5.0)
	_blast(true)
	var t := get_tree().create_timer(SECOND_BLAST_DELAY)
	t.timeout.connect(_blast.bind(false))
	var dt := get_tree().create_timer(SECOND_BLAST_DELAY + 0.6)
	dt.timeout.connect(queue_free)


func _draw_fissure() -> void:
	var line := Line2D.new()
	line.width = WIDTH
	line.default_color = Color(0.6, 0.3, 0.15, 0.6)
	line.add_point(to_local(_origin))
	line.add_point(to_local(_origin + direction * LENGTH))
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, SECOND_BLAST_DELAY + 0.5)


func _blast(first: bool) -> void:
	if VfxManager:
		VfxManager.spawn_explosion(_origin + direction * LENGTH * 0.5, 1.8, Color(0.8, 0.45, 0.2, 1))
		VfxManager.screen_shake(10.0, 0.35)
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	var perp: Vector2 = Vector2(-direction.y, direction.x)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var local: Vector2 = (e as Node2D).global_position - _origin
		var along: float = local.dot(direction)
		var across: float = abs(local.dot(perp))
		if along < 0.0 or along > LENGTH or across > WIDTH * 0.5:
			continue
		# Center-line targets get knocked up.
		var dmg: int = damage if first else int(round(float(damage) * 0.7))
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, _origin)
		if first and e.has_method("set") and across < WIDTH * 0.35:
			(e as Node2D).set("velocity", -perp * KNOCKUP)
		if caster and caster.has_method("notify_control_applied"):
			caster.call("notify_control_applied")
