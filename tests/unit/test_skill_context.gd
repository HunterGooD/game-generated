extends GutTest

# SkillContext: typed bundle that replaced the loose (dir, dmg, mods) skill contract.
# These are pure-resource tests — no scene tree, no autoloads — a good sign the
# context is well decoupled.


class _StubCtx:
	extends Node2D
	var got_damage: int = -1
	func setup_context(ctx) -> void:
		got_damage = ctx.damage


class _StubLegacy:
	extends Node2D
	var got: Array = []
	func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
		got = [dir, dmg, mods]


func test_from_mods_promotes_typed_fields() -> void:
	var ctx := SkillContext.from_mods(
		Vector2(2, 0), 30, {"caster": self, "visual_only": true, "transform": "ice_wall", "x": 1}
	)
	assert_eq(ctx.direction, Vector2.RIGHT, "direction normalized")
	assert_eq(ctx.damage, 30)
	assert_eq(ctx.caster, self)
	assert_true(ctx.is_visual_only)
	assert_eq(ctx.transform, "ice_wall")
	assert_eq(ctx.net_mode, SkillContext.NetMode.VISUAL_REMOTE)
	assert_eq(int(ctx.get_mod("x", 0)), 1, "per-skill key stays in mods")


func test_to_mods_roundtrip() -> void:
	var ctx := SkillContext.from_mods(Vector2.RIGHT, 10, {"caster": self, "k": 5})
	var m := ctx.to_mods()
	assert_eq(m.get("caster"), self)
	assert_eq(m.get("visual_only"), false)
	assert_eq(int(m.get("k")), 5)


func test_apply_prefers_setup_context() -> void:
	var n := _StubCtx.new()
	add_child_autofree(n)
	assert_true(SkillContext.apply(n, SkillContext.from_mods(Vector2.RIGHT, 7, {})))
	assert_eq(n.got_damage, 7)


func test_apply_falls_back_to_legacy() -> void:
	var n := _StubLegacy.new()
	add_child_autofree(n)
	assert_true(SkillContext.apply(n, SkillContext.from_mods(Vector2.RIGHT, 9, {"caster": self})))
	assert_eq(int(n.got[1]), 9)
	assert_eq((n.got[2] as Dictionary).get("caster"), self, "to_mods restores caster for legacy")
