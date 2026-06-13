class_name CombatEntity
extends CharacterBody2D

# Shared base for the host-simulated combat actors (Enemy, Boss). Both bound the
# exact same component set the exact same way and resolved NetSync identically;
# that boilerplate lives here once. Subclasses keep their own behaviour (_die,
# the HP-change reaction, AI, affixes) by overriding the virtuals below.
#
# The component refs are @export NodePaths assigned per-scene (enemy.tscn /
# boss.tscn list them in the root node's node_paths). Declaring them in this base
# keeps the property names identical, so the scenes bind them unchanged.

@export var sprite: Sprite2D
@export var hurtbox: HurtBoxComponent
@export var stats_component: StatsComponent
@export var health_component: HealthComponent
@export var status_effect_receiver: StatusEffectReceiverComponent

# Per-instance stats resource the StatsComponent reads from.
var _runtime_base_stats: ActorStatsResource = ActorStatsResource.new()


# Wire the component graph: stats -> health -> status receiver -> hurtbox, and
# subscribe to the health component's hp_change / dead signals. Identical for
# every combat entity; safe to call again (connections are guarded).
func _setup_components() -> void:
	if stats_component:
		stats_component.base_stats = _runtime_base_stats
	if health_component:
		health_component.main_stats = stats_component
		if not health_component.hp_change.is_connected(_on_health_component_changed):
			health_component.hp_change.connect(_on_health_component_changed)
		if not health_component.dead.is_connected(_on_health_component_dead):
			health_component.dead.connect(_on_health_component_dead)
	if status_effect_receiver:
		status_effect_receiver.main_stats = stats_component
		status_effect_receiver.health_component = health_component
	if hurtbox:
		hurtbox.health_component = health_component
		hurtbox.status_effect_receiver = status_effect_receiver
		hurtbox.damage_receiver = self


# The active run's NetSync node (multiplayer replication hub), or null in solo.
func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("NetSync")


# Health component reported death — route to the subclass death sequence.
func _on_health_component_dead(_damage_payload: DamageInstance) -> void:
	_die()


# Virtuals — overridden by Enemy / Boss.
func _on_health_component_changed(_current_hp: float, _current_max_hp: float) -> void:
	pass


func _die() -> void:
	pass
