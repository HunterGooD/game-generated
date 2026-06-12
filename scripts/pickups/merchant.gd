extends Area2D

# The Wandering Echo — appears in the arena between waves on every 3rd
# non-boss wave. Walk up, press E, the shop modal opens.

const MERCHANT_PANEL_SCENE: PackedScene = preload("res://scenes/ui/merchant_panel.tscn")
const TRADE_RANGE: float = 80.0

@export var sprite: Sprite2D
@export var prompt: Label
@export var glow: PointLight2D

var player_in_range: bool = false
var player_node: Node2D = null
var shop_open: bool = false
var leaving: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	z_index = 60
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt:
		prompt.visible = false
	if sprite:
		var path: String = "res://assets/sprites/characters/merchant_idle.png"
		if ResourceLoader.exists(path):
			sprite.texture = load(path) as Texture2D
		# Feet shadow (after the texture is set, so it lands at the base).
		BlobShadow.attach_at_feet(self, sprite, 44.0, 16.0)
		# Bobbing.
		var bob := sprite.create_tween().set_loops()
		bob.tween_property(sprite, "position:y", -8.0, 1.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(sprite, "position:y", 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	if glow:
		var pulse := glow.create_tween().set_loops()
		pulse.tween_property(glow, "energy", 1.6, 1.2).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(glow, "energy", 0.9, 1.2).set_trans(Tween.TRANS_SINE)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_merchant_greeting.mp3", -10.0)


func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and not body.is_in_group("remote_player"):
		player_node = body as Node2D
		player_in_range = true
		if prompt:
			prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body == player_node:
		player_in_range = false
		if prompt and not shop_open:
			prompt.visible = false


func _process(_delta: float) -> void:
	if leaving:
		return
	if player_in_range and not shop_open and Input.is_action_just_pressed("interact"):
		_open_shop()


func _open_shop() -> void:
	if shop_open:
		return
	shop_open = true
	if prompt:
		prompt.visible = false
	var panel: CanvasLayer = MERCHANT_PANEL_SCENE.instantiate()
	get_tree().current_scene.add_child(panel)
	if panel.has_signal("closed"):
		panel.connect("closed", _on_shop_closed)


func _on_shop_closed() -> void:
	shop_open = false


func leave() -> void:
	# Called by spawner when the next wave starts.
	if leaving:
		return
	leaving = true
	set_deferred("monitoring", false)
	if prompt:
		prompt.visible = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
