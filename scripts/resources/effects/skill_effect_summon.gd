class_name SkillEffectSummon
extends SkillEffect

# Spawns minions/pets at the cast origin (host position — caster for at_caster,
# aim point for at_target). Routes through the existing host-authoritative summon
# flow: in multiplayer the host calls NetSync.host_spawn_summon and a client calls
# request_summon (host then replicates); in single-player it instantiates the scene
# directly. Skipped on the visual-only remote copy and when there is no caster —
# identical to the old bespoke `if not visual_only and caster` guard.

@export var kind: String = ""        # net summon kind: "skeleton" / "knight" / "spirit"
@export var subtype: String = ""     # e.g. "wolf"; "" for plain minions
@export var scene_path: String = ""  # single-player instantiate target
@export var count: int = 1
@export var spread: float = 48.0
@export var extra: int = 0           # 7th arg of host_spawn_summon/request_summon


func execute(ctx: SkillContext, host: Node2D) -> void:
	if ctx.is_visual_only or ctx.caster == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var origin: Vector2 = host.global_position
	var dmg: int = ctx.damage

	if NetManager and NetManager.is_multiplayer:
		var ns := tree.current_scene.get_node_or_null("NetSync")
		if ns == null:
			return
		if NetManager.is_host:
			ns.call(
				"host_spawn_summon",
				kind, subtype, NetManager.local_player_id, origin, count, dmg, extra
			)
		else:
			ns.call("request_summon", kind, subtype, origin, count, dmg, extra)
		return

	# Single-player: spawn the scene directly, ringed around the origin.
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var cfg: String = subtype if subtype != "" else kind
	for i in count:
		var m: Node2D = packed.instantiate()
		tree.current_scene.add_child(m)
		var ang: float = (TAU / float(maxi(1, count))) * float(i) + randf() * 0.3
		m.global_position = origin + Vector2(cos(ang), sin(ang)) * spread
		if m.has_method("configure"):
			m.call("configure", cfg, dmg)
		m.set("owner_caster", ctx.caster)


static func from_data(d: Dictionary) -> SkillEffectSummon:
	var e := SkillEffectSummon.new()
	e.kind = String(d.get("kind", ""))
	e.subtype = String(d.get("subtype", ""))
	e.scene_path = String(d.get("scene_path", ""))
	e.count = int(d.get("count", 1))
	e.spread = float(d.get("spread", 48.0))
	e.extra = int(d.get("extra", 0))
	return e
