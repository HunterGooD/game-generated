class_name MetaGemDefinition
extends RefCounted

# Typed view of one meta-mirror-tree gem (MetaGems.GEMS). Same approach as
# GemDefinition for socket gems: GEMS stays the authoring dict, MetaGems builds
# one definition per id (cached) and get_gem() returns it. `stats` are flat
# bonuses; `pct` are percent-scaling bonuses. Unknown ids return an unknown()
# placeholder (name == id) so call sites never get null.

var id: String = ""
var name: String = ""
var rarity: String = "common"
var stats: Dictionary = {}
var pct: Dictionary = {}


static func from_dict(gem_id: String, d: Dictionary) -> MetaGemDefinition:
	var g := MetaGemDefinition.new()
	g.id = gem_id
	g.name = String(d.get("name", gem_id))
	g.rarity = String(d.get("rarity", "common"))
	g.stats = (d.get("stats", {}) as Dictionary).duplicate()
	g.pct = (d.get("pct", {}) as Dictionary).duplicate()
	return g


static func unknown(gem_id: String) -> MetaGemDefinition:
	var g := MetaGemDefinition.new()
	g.id = gem_id
	g.name = gem_id
	return g
