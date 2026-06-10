extends Area2D

# Continue Portal — spawns after every 3rd non-boss wave alongside the merchant.
# Player walks up, presses E, and the next wave begins. Without this, waves
# don't auto-advance during the merchant break.

signal activated

const PORTAL_TEX: String = "res://assets/sprites/effects/portal_continue.png"

@export var sprite: Sprite2D
@export var prompt: Label
@export var glow: PointLight2D

var player_in_range: bool = false
var fired: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player hurtbox
	monitoring = true
	z_index = 65
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt:
		prompt.visible = false
	if sprite:
		if ResourceLoader.exists(PORTAL_TEX):
			sprite.texture = load(PORTAL_TEX) as Texture2D
		sprite.scale = Vector2(0.85, 0.85)
		# Slow infinite rotation + pulse.
		var rot := sprite.create_tween().set_loops()
		rot.tween_property(sprite, "rotation", sprite.rotation + TAU, 4.0)
		var pulse := sprite.create_tween().set_loops()
		pulse.tween_property(sprite, "modulate", Color(1.3, 0.85, 1.6, 1), 0.9).set_trans(
			Tween.TRANS_SINE
		)
		pulse.tween_property(sprite, "modulate", Color(0.85, 0.5, 1.2, 1), 0.9).set_trans(
			Tween.TRANS_SINE
		)
	if glow:
		var pg := glow.create_tween().set_loops()
		pg.tween_property(glow, "energy", 1.6, 0.9).set_trans(Tween.TRANS_SINE)
		pg.tween_property(glow, "energy", 0.9, 0.9).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and not body.is_in_group("remote_player"):
		player_in_range = true
		if prompt:
			prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body and body.is_in_group("player") and not body.is_in_group("remote_player"):
		player_in_range = false
		if prompt:
			prompt.visible = false


func _process(_delta: float) -> void:
	if fired:
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		_activate()


func _activate() -> void:
	if fired:
		return
	fired = true
	set_deferred("monitoring", false)
	if prompt:
		prompt.visible = false
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/enemy/enemy_boss_appear.mp3", -10.0)
	if VfxManager:
		VfxManager.screen_flash(Color(0.7, 0.4, 1.0, 0.35), 0.4)
	# Burst-zoom the portal and fade.
	if sprite:
		var tw := sprite.create_tween().set_parallel(true)
		tw.tween_property(sprite, "scale", sprite.scale * 2.2, 0.55)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.55)
	activated.emit()
	# The handler may swap/reload the scene (e.g. dungeon descent), which removes us from
	# the tree — only set up our own fade-cleanup timer if we're still in it.
	if is_inside_tree():
		var t := get_tree().create_timer(0.65)
		t.timeout.connect(queue_free)
