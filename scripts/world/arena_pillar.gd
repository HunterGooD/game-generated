class_name ArenaPillar
extends Node2D

## A wave-condition pillar. Before each arena wave the player picks ONE of three pillars;
## the chosen pillar sets that wave's rules (the spawner applies them) and the wave begins.
##   • green  — a small, harmless buff. Easiest; least local currency.
##   • red    — empowers the enemies AND lowers the hidden kill-threshold so events fire more
##              often. Harder; more currency.
##   • purple — RARE. Brutal conditions (constant events, ~50% of foes become mini-bosses)
##              but the biggest local-currency payoff.
## Built in code (no .tscn node_paths). Emits `chosen(kind)` when activated.

const INTERACT_RANGE: float = 96.0
const GLOW_SHADER: Shader = preload("res://assets/shaders/pillar_glow.gdshader")

const KIND_COLOR := {
	"green": Color(0.32, 0.88, 0.42),
	"red": Color(0.95, 0.28, 0.24),
	"purple": Color(0.72, 0.36, 0.98),
	"mutator": Color(1.0, 0.66, 0.18),
}
const KIND_TEXT := {
	"green": "GREEN — boon",
	"red": "RED — empower foes",
	"purple": "★ PURPLE — brutal, huge reward ★",
	"mutator": "◆ MUTATOR — risk for double reward ◆",
}

signal chosen(kind: String, effect: String)

var kind: String = "green"
var effect: String = ""  # specific sub-effect id (the spawner applies it)
var _desc: String = ""  # human label for this pillar's effect
var _label: Label = null
var _in_range: bool = false
var _used: bool = false


func configure(k: String, eff: String = "", desc: String = "") -> void:
	kind = k
	effect = eff
	_desc = desc


func _text() -> String:
	return _desc if _desc != "" else String(KIND_TEXT.get(kind, kind))


func _ready() -> void:
	add_to_group("arena_pillar")
	_build()


func _glow_material(tint: Color, alpha: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	var c := tint
	c.a = alpha
	mat.set_shader_parameter("tint", c)
	mat.set_shader_parameter("pulse_speed", 4.5 if kind == "purple" else 3.0)
	return mat


func _build() -> void:
	var tint: Color = KIND_COLOR.get(kind, Color(0.7, 0.7, 0.8))
	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 1)
	glow.size = Vector2(100, 156)
	glow.position = Vector2(-50, -134)
	glow.z_index = -1
	glow.material = _glow_material(tint, 0.30)
	add_child(glow)
	var body := ColorRect.new()
	body.color = Color(1, 1, 1, 1)
	body.size = Vector2(50, 112)
	body.position = Vector2(-25, -112)
	body.material = _glow_material(tint, 1.0)
	add_child(body)
	_label = Label.new()
	_label.text = _text()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-150, -150)
	_label.custom_minimum_size = Vector2(300, 0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _process(_delta: float) -> void:
	if _used:
		return
	var p := _local_player()
	var in_range: bool = (
		p != null and global_position.distance_to(p.global_position) <= INTERACT_RANGE
	)
	if in_range != _in_range:
		_in_range = in_range
		_label.text = (_text() + "   [E]") if in_range else _text()
	if in_range and Input.is_action_just_pressed("interact"):
		_activate()


func _activate() -> void:
	if _used:
		return
	_used = true
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.2 if kind == "purple" else 1.0, KIND_COLOR.get(kind, Color.WHITE))
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_button_click.mp3", -4.0)
	chosen.emit(kind, effect)


func _local_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D and not p.is_in_group("remote_player"):
			return p as Node2D
	return null
