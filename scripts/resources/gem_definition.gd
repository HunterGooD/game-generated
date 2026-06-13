class_name GemDefinition
extends RefCounted

# Typed view of one socket-gem catalog entry. SocketGems.GEMS stays the authoring
# source (a literal dict); SocketGems builds one GemDefinition per id once and
# hands them out via get_gem(), so call sites read typed fields (g.name, g.stats)
# instead of stringly-typed g.get("name", ...).
#
# For an unknown id, SocketGems.get_gem() returns an `unknown(id)` instance whose
# defaults match the old dict-default behaviour (name == id, common rarity, empty
# faces/stats/effect), so no call site needs a null check.

var id: String = ""
var name: String = ""
var rarity: String = "common"
var faces: Array = []
var stats: Dictionary = {}
var effect: String = ""


static func from_dict(gem_id: String, d: Dictionary) -> GemDefinition:
	var g := GemDefinition.new()
	g.id = gem_id
	g.name = String(d.get("name", gem_id))
	g.rarity = String(d.get("rarity", "common"))
	g.faces = (d.get("faces", []) as Array).duplicate()
	g.stats = (d.get("stats", {}) as Dictionary).duplicate()
	g.effect = String(d.get("effect", ""))
	return g


# Placeholder for an id not in the catalog — mirrors the empty-dict defaults the
# old get_gem(id).get(field, default) calls produced.
static func unknown(gem_id: String) -> GemDefinition:
	var g := GemDefinition.new()
	g.id = gem_id
	g.name = gem_id
	return g
