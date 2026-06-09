extends GutTest

# Elite affixes (V6): the EnemyAffixes data + the enemy's application of stat mults,
# the aura, and the explosive / shielded behaviour hooks.

const ENEMY_SCENE := "res://scenes/entities/enemy.tscn"


class _MockPlayer:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	func take_damage(d, _s = null) -> void:
		hits.append(d)


func _enemy(cfg: Dictionary) -> CharacterBody2D:
	var e: CharacterBody2D = (load(ENEMY_SCENE) as PackedScene).instantiate()
	add_child_autofree(e)
	e.configure(cfg)
	e.global_position = Vector2.ZERO
	return e


# ── data ──────────────────────────────────────────────────────────────────────
func test_roll_count_in_range() -> void:
	for i in 50:
		assert_between(EnemyAffixes.roll_count(), 1, 3)


func test_roll_returns_distinct_valid_ids() -> void:
	var ids := EnemyAffixes.roll(3)
	assert_eq(ids.size(), 3)
	assert_eq(ids.size(), _unique(ids).size(), "no duplicate affixes")
	for id in ids:
		assert_true(EnemyAffixes.AFFIXES.has(id), "valid affix id: %s" % id)


func test_aura_color_blends() -> void:
	var solo := EnemyAffixes.aura_color(["brutal"])
	assert_eq(solo, EnemyAffixes.AFFIXES["brutal"]["color"])
	var blend := EnemyAffixes.aura_color(["brutal", "vital"])
	var expect_r := (EnemyAffixes.AFFIXES["brutal"]["color"].r + EnemyAffixes.AFFIXES["vital"]["color"].r) / 2.0
	assert_almost_eq(blend.r, expect_r, 0.001, "two-affix aura is the average")


func _unique(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


# ── stat affixes ──────────────────────────────────────────────────────────────
func test_vital_multiplies_hp() -> void:
	var e := _enemy({"max_hp": 100, "affixes": ["vital"]})
	assert_eq(e.max_hp, 240, "vital ×2.4")
	assert_true(e.is_elite())


func test_swift_speeds_movement_and_attacks() -> void:
	var e := _enemy({"move_speed": 100.0, "attack_cooldown": 1.5, "affixes": ["swift"]})
	assert_almost_eq(e.move_speed, 140.0, 0.1, "swift ×1.4 move")
	assert_almost_eq(e.attack_cooldown, 1.0, 0.01, "swift attacks 1.5× faster (cooldown /1.5)")


func test_brutal_multiplies_damage() -> void:
	var e := _enemy({"attack_damage": 10, "affixes": ["brutal"]})
	assert_eq(e.attack_damage, 17, "brutal ×1.7")


func test_combo_stacks_all_affixes() -> void:
	var e := _enemy({"max_hp": 100, "attack_damage": 10, "affixes": ["vital", "brutal"]})
	assert_eq(e.max_hp, 240)
	assert_eq(e.attack_damage, 17)
	assert_eq(e.affixes.size(), 2)


func test_non_elite_has_no_affixes_or_aura() -> void:
	var e := _enemy({"max_hp": 100})
	assert_false(e.is_elite())
	assert_null(e._aura, "no aura sprite for a vanilla enemy")


func test_elite_gets_aura_sprite() -> void:
	var e := _enemy(
		{
			"max_hp": 100,
			"sprite_idle": "res://assets/sprites/characters/spider_hatchling_idle.png",
			"affixes": ["brutal"],
		}
	)
	assert_not_null(e._aura, "elite has an aura sprite")
	assert_true(e._aura is Sprite2D)
	assert_gt(e._aura.scale.x, 1.0, "aura is enlarged so it peeks beyond the main sprite")
	assert_true(e._aura.material is ShaderMaterial, "aura uses the elite-aura shader")
	assert_eq(
		e._aura.material.get_shader_parameter("tint"),
		EnemyAffixes.aura_color(["brutal"]),
		"aura tint = affix colour",
	)
	assert_not_null(e._aura.texture, "aura silhouette has the sprite texture")


# ── behaviour hooks ───────────────────────────────────────────────────────────
func test_explosive_damages_nearby_on_death() -> void:
	var e := _enemy({"attack_damage": 20, "affixes": ["explosive"]})
	assert_true(e._explosive)
	var near := _MockPlayer.new()
	near.add_to_group("player")
	near.global_position = Vector2(80, 0)  # within ELITE_EXPLODE_RADIUS (130)
	add_child_autofree(near)
	var far := _MockPlayer.new()
	far.add_to_group("player")
	far.global_position = Vector2(400, 0)
	add_child_autofree(far)
	e._affix_explode()
	assert_eq(near.hits.size(), 1, "nearby player took the blast")
	assert_eq(far.hits, [], "far player untouched")


func test_shielded_absorbs_one_hit_then_recharges() -> void:
	var e := _enemy({"max_hp": 200, "affixes": ["shielded"]})
	assert_true(e._shielded and e._shield_ready)
	var before: int = e.hp
	e.take_damage(40)  # absorbed by the shield
	assert_eq(e.hp, before, "shield absorbed the hit (no HP lost)")
	assert_false(e._shield_ready, "shield consumed → on cooldown")
