extends Node2D

const DURATION: float = 3.0
const RADIUS: float = 80.0

var _caster: Node = null
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	_caster = ctx.caster
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var tex: Texture2D = null
	var path := "res://assets/sprites/effects/smoke_puff_purple.png"
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	for i in 10:
		var s := Sprite2D.new()
		if tex:
			s.texture = tex
		s.modulate = Color(0.7, 0.7, 0.75, 0.9)
		var sc0: float = randf_range(0.7, 1.2)
		s.scale = Vector2(sc0, sc0)
		s.position = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		s.rotation = randf() * TAU
		s.z_index = 90
		add_child(s)
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "scale", Vector2(sc0 * 2.2, sc0 * 2.2), DURATION)
		tw.tween_property(s, "modulate:a", 0.0, DURATION)

	if not visual_only:
		var p := _resolve_caster()
		if p and p.has_method("apply_stealth"):
			p.call("apply_stealth", DURATION)
		# Assassin: vanishing into smoke opens the Backstab Window (per spec).
		if (
			p
			and p.has_method("start_backstab")
			and GameManager
			and String(GameManager.player_spec_path) == "assassin"
		):
			p.call("start_backstab", 2.0)

	var t := get_tree().create_timer(DURATION + 0.2)
	t.timeout.connect(queue_free)


func _resolve_caster() -> Node:
	if _caster != null and is_instance_valid(_caster):
		return _caster
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if not p.is_in_group("remote_player"):
			return p
	return null
