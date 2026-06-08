class_name SkillEffectAura
extends SkillEffect

# Spawns a persistent lingering zone (skill_aura_zone.tscn) at the cast origin and
# configures it. Covers held ground effects: damaging fields, slow/aura zones, and
# telegraph-then-zone strikes (storm pillar). The zone self-manages its lifetime and
# ticking; this effect just instantiates and configures it. Visual_only is forwarded
# so the zone shows visuals but applies no gameplay on the remote copy.

const ZONE_SCENE := preload("res://scenes/skills/skill_aura_zone.tscn")

@export var radius: float = 150.0
@export var lifetime: float = 4.0
@export var tick_interval: float = 0.5
@export var telegraph_delay: float = 0.0
@export var tick_damage_mult: float = 0.0  # per-tick damage = ctx.damage * this (0 = none)
@export var mark_element: String = ""
@export var enemy_slow_dur: float = 0.0
@export var enemy_slow_mult: float = 1.0
@export var ally_aura_dr: float = 0.0
@export var strike_explosion_scale: float = 0.0
@export var strike_explosion_color: Color = Color(1, 1, 1, 1)
@export var strike_shake: float = 0.0
@export var ring_color: Color = Color(1, 1, 1, 0.4)
@export var ring_texture_path: String = ""


func execute(ctx: SkillContext, host: Node2D) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var zone: Node2D = ZONE_SCENE.instantiate()
	zone.global_position = host.global_position
	zone.call(
		"configure",
		{
			"radius": radius,
			"lifetime": lifetime,
			"tick_interval": tick_interval,
			"telegraph_delay": telegraph_delay,
			"damage": int(round(float(ctx.damage) * tick_damage_mult)),
			"mark_element": mark_element,
			"enemy_slow_dur": enemy_slow_dur,
			"enemy_slow_mult": enemy_slow_mult,
			"ally_aura_dr": ally_aura_dr,
			"visual_only": ctx.is_visual_only,
			"strike_explosion_scale": strike_explosion_scale,
			"strike_explosion_color": strike_explosion_color,
			"strike_shake": strike_shake,
			"ring_color": ring_color,
			"ring_texture_path": ring_texture_path,
		}
	)
	tree.current_scene.add_child(zone)


static func from_data(d: Dictionary) -> SkillEffectAura:
	var e := SkillEffectAura.new()
	e.radius = float(d.get("radius", 150.0))
	e.lifetime = float(d.get("lifetime", 4.0))
	e.tick_interval = float(d.get("tick_interval", 0.5))
	e.telegraph_delay = float(d.get("telegraph_delay", 0.0))
	e.tick_damage_mult = float(d.get("tick_damage_mult", 0.0))
	e.mark_element = String(d.get("mark_element", ""))
	e.enemy_slow_dur = float(d.get("enemy_slow_dur", 0.0))
	e.enemy_slow_mult = float(d.get("enemy_slow_mult", 1.0))
	e.ally_aura_dr = float(d.get("ally_aura_dr", 0.0))
	e.strike_explosion_scale = float(d.get("strike_explosion_scale", 0.0))
	e.strike_explosion_color = d.get("strike_explosion_color", Color(1, 1, 1, 1))
	e.strike_shake = float(d.get("strike_shake", 0.0))
	e.ring_color = d.get("ring_color", Color(1, 1, 1, 0.4))
	e.ring_texture_path = String(d.get("ring_texture_path", ""))
	return e
