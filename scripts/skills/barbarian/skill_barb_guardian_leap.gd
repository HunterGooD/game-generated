extends Node2D

# Guardian Leap — Warchief transform of Leap Slam (slot 1). A protective dive: deals
# impact damage and, on landing, shields the Barbarian and every ally in the
# landing radius.

const LEAP_TIME: float = 0.55
const BLAST_RADIUS: float = 180.0
const MAX_LEAP_DISTANCE: float = 400.0
const SHIELD_FRAC: float = 0.15

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var target_pos: Vector2 = Vector2.ZERO
var visual_only: bool = false
var _caster: Node = null


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	_caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	if _caster:
		var to_mouse: Vector2 = _caster.get_global_mouse_position() - _caster.global_position
		var dist: float = min(to_mouse.length(), MAX_LEAP_DISTANCE)
		target_pos = _caster.global_position + direction * dist
	elif visual_only:
		target_pos = global_position + direction * 200.0


func _ready() -> void:
	if target_pos == Vector2.ZERO:
		target_pos = global_position + direction * 200.0
	var tel := Sprite2D.new()
	var path := "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		tel.texture = load(path) as Texture2D
	tel.modulate = Color(0.5, 0.8, 1.0, 0.7)
	tel.scale = Vector2(1.5, 1.5)
	tel.global_position = target_pos
	tel.z_index = 50
	get_tree().current_scene.add_child(tel)
	if not visual_only and _caster and is_instance_valid(_caster):
		var t := (_caster as Node2D).create_tween()
		t.tween_property(_caster, "global_position", target_pos, LEAP_TIME).set_trans(Tween.TRANS_QUAD)
	var timer := get_tree().create_timer(LEAP_TIME)
	timer.timeout.connect(_on_slam.bind(tel))


func _on_slam(tel: Sprite2D) -> void:
	if is_instance_valid(tel):
		tel.queue_free()
	if VfxManager:
		VfxManager.spawn_explosion(target_pos, 1.5, Color(0.5, 0.8, 1.0, 1))
		VfxManager.screen_shake(10.0, 0.32)
		VfxManager.hit_stop(0.05)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_leap.mp3", -6.0)
	if not visual_only:
		var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
		var shield: float = max_hp * SHIELD_FRAC
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if target_pos.distance_to((e as Node2D).global_position) <= BLAST_RADIUS and e.has_method("take_damage"):
					e.call("take_damage", damage, target_pos)
			for grp in ["player", "remote_player"]:
				for a in tree.get_nodes_in_group(grp):
					if not is_instance_valid(a) or not (a is Node2D):
						continue
					if target_pos.distance_to((a as Node2D).global_position) <= BLAST_RADIUS and a.has_method("add_shield"):
						a.call("add_shield", shield, -1.0)
	queue_free()
