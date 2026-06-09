extends Node2D
# Test double spawned by summon/projectile effects — records how it was set up.
var cfg: Array = []
var owner_caster = null
var ctx_rec: Array = []
func configure(kind, dmg) -> void:
	cfg = [kind, dmg]
	add_to_group("stub_rec")
func setup_context(ctx) -> void:
	ctx_rec = [ctx.direction, ctx.damage, ctx.caster]
	add_to_group("stub_rec")
