extends Node2D

# Melee swing — short-lived cone attack in front of the player.

const LIFETIME: float = 0.22
const ARC_DEGREES: float = 130.0
const RADIUS: float = 110.0

@export var hurt_area: HitBoxComponent
@export var sprite: Sprite2D

var damage: int = 18
var direction: Vector2 = Vector2.RIGHT
var hit_set: Dictionary = {}
var is_crit: bool = false

# Procedural-slash theme (class id or skill element) + optional core-hue override
# for basic-attack uniques. Resolved from the caster's class when left blank.
var slash_theme: String = ""
var slash_core = null


func setup(dir: Vector2, dmg: int, theme: String = "", core_override = null) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	if GameManager:
		var res: Array = GameManager.compute_attack_damage(dmg)
		damage = int(res[0])
		is_crit = bool(res[1])
	else:
		damage = dmg
	rotation = direction.angle()
	if theme != "":
		slash_theme = theme
	if core_override != null:
		slash_core = core_override
	if hurt_area:
		hurt_area.payload = _build_damage_payload()


## Co-op: a replicated visual copy gets its caster's class after spawn so peers
## see the right slash colour. Re-applies the material if the sprite is up.
func set_slash_theme(theme: String) -> void:
	slash_theme = theme
	if sprite and is_inside_tree():
		_apply_slash_material()


func _resolve_theme() -> String:
	if slash_theme != "":
		return slash_theme
	# Replicated remote copy with no caster class yet → neutral (not the local
	# viewer's class). The basic-attack path supplies the real class via "cls".
	if has_meta("visual_only"):
		return "white"
	if GameManager:
		return String(GameManager.player_class)
	return ""


func _apply_slash_material() -> ShaderMaterial:
	if sprite == null:
		return null
	return SlashFx.apply_to(sprite, _resolve_theme(), slash_core)


func _ready() -> void:
	if hurt_area:
		hurt_area.collision_layer = 0
		hurt_area.collision_mask = 16
		hurt_area.area_entered.connect(_on_area_entered)
		hurt_area.hit.connect(_on_hit_hurtbox)
	# Procedural slash: build the themed material and sweep it via `progress`.
	# The shader handles the fade-out, so no modulate:a tween is needed.
	if sprite:
		var mat := _apply_slash_material()
		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(sprite, "scale", sprite.scale * 1.15, LIFETIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		if mat:
			(
				tw
				. tween_property(mat, "shader_parameter/progress", 1.0, LIFETIME)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
	# Auto-destroy.
	var t := get_tree().create_timer(LIFETIME + 0.05)
	t.timeout.connect(_finish)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	if not area.is_in_group("enemy_hit"):
		return
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if hit_set.has(id):
		return
	hit_set[id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
	_play_hit_feedback(enemy)


func _on_hit_hurtbox(area: Area2D) -> void:
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if hit_set.has(id):
		return
	hit_set[id] = true
	_play_hit_feedback(enemy)


func _play_hit_feedback(enemy: Node) -> void:
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_melee_hit.mp3", -8.0)
	if VfxManager:
		var col: Color = Color(1.0, 0.4, 0.2, 1) if is_crit else Color(1, 0.85, 0.5, 1)
		VfxManager.spawn_hit_sparks(enemy.global_position, col, 7)
		if is_crit:
			VfxManager.screen_shake(2.5, 0.12)


func _build_damage_payload() -> DamageInstance:
	return DamageInstance.new(
		float(damage),
		_resolve_local_player(),
		self,
		[&"player", &"melee"],
		[],
		is_crit
	)


func _resolve_local_player() -> Node:
	# Guard with is_inside_tree() first: calling get_tree() on a node that
	# hasn't been added to the SceneTree yet (e.g. during setup() before
	# add_child) emits "Parameter data.tree is null" before returning null.
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null


func _finish() -> void:
	if hurt_area:
		hurt_area.set_deferred("monitoring", false)
		hurt_area.set_deferred("monitorable", false)
	queue_free()
