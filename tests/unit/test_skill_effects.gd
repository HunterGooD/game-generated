extends GutTest

# SkillEffect library: every effect type resolves from catalog data, and the core
# behaviours apply correctly (with the visual-only / radius / count guards). These
# are decoupled — effects act on a host Node2D + a SkillContext + mock agents — so
# they are easy to test, which is the architecture signal we want.

const STUB_REC := "res://tests/unit/stubs/stub_recorder.tscn"


class MockCaster:
	extends Node2D
	var buffs: Array = []
	func apply_buff(a, b, c) -> void:
		buffs.append([a, b, c])


class MockEnemy:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	var elem: Array = []
	var slows: Array = []
	func take_damage(d, _s) -> void:
		hits.append(d)
	func mark_element(s) -> void:
		elem.append(s)
	func apply_slow(a, b) -> void:
		slows.append([a, b])


class MockAlly:
	extends Node2D
	var shields: Array = []
	func add_shield(a, b) -> void:
		shields.append([a, b])


class MockMinion:
	extends Node2D
	var hp: int = 40
	var max_hp: int = 100


var _container: Node2D = null
var _prev_scene: Node = null


# Effects that spawn (summon / projectile / aura / telegraph) add their nodes to
# get_tree().current_scene, which is null under the GUT runner. Stand up a container
# scene so those code paths run (mirrors current_scene = game_world in real play).
func before_each() -> void:
	_prev_scene = get_tree().current_scene
	_container = Node2D.new()
	get_tree().root.add_child(_container)
	get_tree().current_scene = _container


func after_each() -> void:
	get_tree().current_scene = _prev_scene
	if is_instance_valid(_container):
		_container.free()


func _ctx(dmg: int, visual := false) -> SkillContext:
	var c := SkillContext.new()
	c.damage = dmg
	c.is_visual_only = visual
	c.direction = Vector2.RIGHT
	return c


func _host(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var h := Node2D.new()
	add_child_autofree(h)
	h.global_position = pos
	return h


# ── from_data resolves all 13 types ───────────────────────────────────────────
func test_from_data_resolves_all_types() -> void:
	var types := {
		"caster_call": SkillEffectCasterCall,
		"caster_set": SkillEffectCasterSet,
		"group_call": SkillEffectGroupCall,
		"area_damage": SkillEffectAreaDamage,
		"summon": SkillEffectSummon,
		"group_heal": SkillEffectGroupHeal,
		"group_shield": SkillEffectGroupShield,
		"transform": SkillEffectTransform,
		"dash": SkillEffectDash,
		"projectile": SkillEffectProjectile,
		"aura": SkillEffectAura,
		"telegraph": SkillEffectTelegraph,
		"vfx": SkillEffectVfx,
	}
	for t in types:
		var e := SkillEffect.from_data({"type": t})
		assert_not_null(e, "type '%s' should resolve" % t)
		assert_true(is_instance_of(e, types[t]), "type '%s' wrong class" % t)
	assert_null(SkillEffect.from_data({"type": "nonsense"}), "unknown type -> null")


# ── caster_call ───────────────────────────────────────────────────────────────
func test_caster_call_invokes_method() -> void:
	var c := MockCaster.new()
	add_child_autofree(c)
	var ctx := _ctx(0)
	ctx.caster = c
	var e := SkillEffectCasterCall.from_data({"method": "apply_buff", "args": [18.0, 1.4, 1.2]})
	e.execute(ctx, _host())
	assert_eq(c.buffs, [[18.0, 1.4, 1.2]])


# ── area_damage ───────────────────────────────────────────────────────────────
func test_area_damage_hits_in_radius_marks_and_slows() -> void:
	var e := MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = Vector2(100, 0)
	add_child_autofree(e)
	var eff := SkillEffectAreaDamage.from_data(
		{"radius": 140.0, "mark_element": "storm", "slow_duration": 1.5, "slow_mult": 0.6}
	)
	eff.execute(_ctx(50), _host())
	assert_eq(e.hits, [50])
	assert_eq(e.elem, ["storm"])
	assert_eq(e.slows, [[1.5, 0.6]])


func test_area_damage_excludes_far_and_visual_only() -> void:
	var near := MockEnemy.new()
	near.add_to_group("enemy")
	near.global_position = Vector2(50, 0)
	add_child_autofree(near)
	var far := MockEnemy.new()
	far.add_to_group("enemy")
	far.global_position = Vector2(400, 0)
	add_child_autofree(far)
	SkillEffectAreaDamage.from_data({"radius": 140.0}).execute(_ctx(50, true), _host())
	assert_eq(near.hits, [], "visual-only does no damage")
	SkillEffectAreaDamage.from_data({"radius": 140.0}).execute(_ctx(50), _host())
	assert_eq(near.hits, [50])
	assert_eq(far.hits, [], "out of radius untouched")


# ── group_heal / group_shield ─────────────────────────────────────────────────
func test_group_heal_heals_fraction_of_max() -> void:
	var m := MockMinion.new()
	m.add_to_group("necro_minion")
	m.global_position = Vector2(50, 0)
	add_child_autofree(m)
	SkillEffectGroupHeal.from_data({"group": "necro_minion", "radius": 200.0, "heal_frac": 0.25}).execute(
		_ctx(0), _host()
	)
	assert_eq(m.hp, 65, "40 + 25% of 100")


func test_group_shield_uses_caster_max_hp() -> void:
	var a := MockAlly.new()
	a.add_to_group("player")
	a.global_position = Vector2(30, 0)
	add_child_autofree(a)
	var max_hp: float = float(GameManager.player_max_hp)
	SkillEffectGroupShield.from_data(
		{"groups": ["player"], "radius": 260.0, "shield_frac": 0.18}
	).execute(_ctx(0), _host())
	assert_eq(a.shields.size(), 1)
	assert_almost_eq(float(a.shields[0][0]), max_hp * 0.18, 0.01)


# ── summon (single-player branch via stub scene) ──────────────────────────────
func test_summon_single_player_spawns_and_configures() -> void:
	var ctx := _ctx(77)
	ctx.caster = self
	var eff := SkillEffectSummon.from_data({"kind": "skeleton", "count": 3, "scene_path": STUB_REC})
	eff.execute(ctx, _host())
	var stubs := get_tree().get_nodes_in_group("stub_rec")
	assert_eq(stubs.size(), 3)
	for s in stubs:
		assert_eq(s.cfg, ["skeleton", 77])
		assert_eq(s.owner_caster, self)
		s.free()


# ── dash (line damage via null-caster branch) ─────────────────────────────────
func test_dash_line_damage() -> void:
	var on_line := MockEnemy.new()
	on_line.add_to_group("enemy")
	on_line.global_position = Vector2(160, 0)
	add_child_autofree(on_line)
	var off_line := MockEnemy.new()
	off_line.add_to_group("enemy")
	off_line.global_position = Vector2(160, 200)
	add_child_autofree(off_line)
	SkillEffectDash.from_data(
		{"max_distance": 320.0, "width": 64.0, "path_damage": true, "mark_element": "storm"}
	).execute(_ctx(50), _host())  # null caster -> dest = origin + dir*max
	assert_eq(on_line.hits, [50])
	assert_eq(on_line.elem, ["storm"])
	assert_eq(off_line.hits, [], "outside dash width untouched")


# ── projectile (count + modifier, radial) ─────────────────────────────────────
func test_projectile_count_with_modifier() -> void:
	var ctx := _ctx(33)
	ctx.caster = self
	ctx.mods = {"count_bonus": 2}
	SkillEffectProjectile.from_data(
		{"scene_path": STUB_REC, "count": 8, "count_modifier": "count_bonus"}
	).execute(ctx, _host())
	var stubs := get_tree().get_nodes_in_group("stub_rec")
	assert_eq(stubs.size(), 10, "8 + 2 count_bonus")
	for s in stubs:
		assert_eq(int(s.ctx_rec[1]), 33)
		assert_eq(s.ctx_rec[2], self)
		s.free()


# ── aura zone (ticks damage over frames) ──────────────────────────────────────
func test_aura_zone_ticks_damage() -> void:
	var e := MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = Vector2(50, 0)
	add_child_autofree(e)
	SkillEffectAura.from_data(
		{"radius": 200.0, "lifetime": 2.0, "tick_interval": 0.5, "tick_damage_mult": 1.0}
	).execute(_ctx(50), _host())
	await wait_process_frames(3)
	assert_true(e.hits.size() >= 1, "aura tick dealt damage")
	assert_eq(int(e.hits[0]), 50)


# ── telegraph (delayed burst) ─────────────────────────────────────────────────
func test_telegraph_delayed_burst() -> void:
	var e := MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = Vector2(60, 0)
	add_child_autofree(e)
	SkillEffectTelegraph.from_data({"delay": 0.2, "radius": 150.0, "mark_element": "frost"}).execute(
		_ctx(40), _host()
	)
	assert_eq(e.hits, [], "no damage before delay")
	await wait_seconds(0.35)
	assert_eq(e.hits, [40], "burst after delay")
	assert_eq(e.elem, ["frost"])


# ── script-carrier skills (no .tscn) build Node2D + set_script via the catalog ──
func test_script_carrier_instantiates_from_catalog() -> void:
	var def: SkillDefinition = SkillCatalog.get_def("chain_lightning")
	assert_not_null(def, "chain_lightning resolves in the catalog")
	assert_eq(def.scene_path, "", "script-carrier skill has no scene_path")
	assert_ne(def.script_path, "", "script-carrier skill carries a script_path")
	var node = def.instantiate_node()
	assert_not_null(node, "instantiate_node() builds a node from the script")
	assert_true(node is Node2D, "script-carrier root is a Node2D")
	assert_not_null(node.get_script(), "script is attached")
	node.free()


func test_scene_based_skill_keeps_its_scene() -> void:
	# Authored scenes (children placed in editor) + the composed runner keep scene_path.
	var def: SkillDefinition = SkillCatalog.get_def("meteor")
	assert_not_null(def, "meteor resolves in the catalog")
	assert_ne(def.scene_path, "", "authored skill keeps its scene_path")
	assert_not_null(def.instantiate_node(), "instantiate_node() builds from the scene")
