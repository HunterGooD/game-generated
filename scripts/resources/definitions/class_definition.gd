class_name ClassDefinition
extends RefCounted

# Typed view of one entry in GameManager.CLASSES. CLASSES stays the authoring
# source; GameManager builds one definition per id (cached) and class_def()
# returns it. This is the single place that decodes a class entry, so the
# scattered per-class colour/onhit/basic-unique dicts that used to live in
# ui/*.gd, fx/slash_fx.gd, data/skill_trees.gd and entities/player.gd now fold
# into CLASSES and read through here.
#
# Two colour roles are kept distinct (collapsing them would regress visuals):
#   theme_color — the strong class hue (lobby badge, remote-player tint).
#   ui_color    — the lighter pastel label tint (hero select, meta tree).
#
# Unknown id -> unknown() placeholder (display == id, empty dicts) so callers
# never get null; guard with GameManager.has_class()/CLASSES.has(id) for a
# genuine miss.

var id: String = ""
var display: String = ""
var primary: String = ""
var primary_label: String = ""
var description: String = ""
var portrait: String = ""
var sprite_idle: String = ""
var sprite_walk: String = ""
var sprite_attack: String = ""
var basic_attack: String = ""
var skill_ids: Array = []
var dash_kind: String = ""
var base: Dictionary = {}
var per_level: Dictionary = {}
# Colours.
var theme_color: Color = Color(1, 1, 1, 1)
var ui_color: Color = Color(1, 1, 1, 1)
# Folded-in per-class look/behaviour.
var resource_liquid: Dictionary = {}  # {color: Color, darkness: float} — HUD mana globe.
var slash_style: Dictionary = {}      # {core, glow, style, span?} — basic-swing slash palette.
var on_hit_element: String = ""       # status element granted by on-hit tree nodes.
var basic_unique: String = ""         # basic-attack-replacing unique id ("" = none).


static func from_dict(class_id: String, d: Dictionary) -> ClassDefinition:
	var c := ClassDefinition.new()
	c.id = class_id
	c.display = String(d.get("display", class_id))
	c.primary = String(d.get("primary", ""))
	c.primary_label = String(d.get("primary_label", ""))
	c.description = String(d.get("description", ""))
	c.portrait = String(d.get("portrait", ""))
	c.sprite_idle = String(d.get("sprite_idle", ""))
	c.sprite_walk = String(d.get("sprite_walk", ""))
	c.sprite_attack = String(d.get("sprite_attack", ""))
	c.basic_attack = String(d.get("basic_attack", ""))
	c.skill_ids = (d.get("skill_ids", []) as Array).duplicate()
	c.dash_kind = String(d.get("dash_kind", ""))
	c.base = (d.get("base", {}) as Dictionary).duplicate()
	c.per_level = (d.get("per_level", {}) as Dictionary).duplicate()
	c.theme_color = d.get("color", Color(1, 1, 1, 1))
	c.ui_color = d.get("ui_color", c.theme_color)
	c.resource_liquid = (d.get("resource_liquid", {}) as Dictionary).duplicate()
	c.slash_style = (d.get("slash_style", {}) as Dictionary).duplicate()
	c.on_hit_element = String(d.get("on_hit_element", ""))
	c.basic_unique = String(d.get("basic_unique", ""))
	return c


static func unknown(class_id: String) -> ClassDefinition:
	var c := ClassDefinition.new()
	c.id = class_id
	c.display = class_id
	return c
