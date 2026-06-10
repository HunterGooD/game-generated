class_name DungeonAffixes
extends RefCounted

## Single source of truth for the 6 dungeon affixes the Rust generator (echoes-dungeon)
## can roll. The string ids here MUST match affix.rs → AffixId::as_str(). Negatives are
## shown on the run map up front (informed risk); positives stay HIDDEN until the party
## enters (a pleasant gamble). Stateless — every method is static, mirroring Difficulty.
##
## `polarity`:  +1 positive, -1 negative.
## `hidden`:    true → not revealed on the run-map node, only on entry.

const DEFS := {
	# ── Negative (common, shown on the map) ──────────────────────────────
	"suffocating_gloom":
	{
		"name": "Suffocating Gloom",
		"polarity": -1,
		"hidden": false,
		"color": Color(0.45, 0.32, 0.55),
		"desc": "A smoke cloud drifts after the party. Standing in it stacks damage — keep moving.",
	},
	"volatile_spheres":
	{
		"name": "Volatile Spheres",
		"polarity": -1,
		"hidden": false,
		"color": Color(1.0, 0.55, 0.2),
		"desc": "Unstable orbs appear and detonate. Get clear before they blow.",
	},
	"heavens_wrath":
	{
		"name": "Heaven's Wrath",
		"polarity": -1,
		"hidden": false,
		"color": Color(0.55, 0.8, 1.0),
		"desc": "Lightning hammers the party's positions, then relents. Sidestep the marks.",
	},
	# ── Positive (rare, hidden until entered) ────────────────────────────
	"gold_vein":
	{
		"name": "Gold Vein",
		"polarity": 1,
		"hidden": true,
		"color": Color(1.0, 0.84, 0.3),
		"desc": "Enemies gush gold; a rare golden foe drops a cache.",
	},
	"echo_of_power":
	{
		"name": "Echo of Power",
		"polarity": 1,
		"hidden": true,
		"color": Color(0.45, 0.7, 1.0),
		"desc": "Shrine bursts grant a stacking buff that lasts the layer and carries on descent.",
	},
	"fortunes_favor":
	{
		"name": "Fortune's Favor",
		"polarity": 1,
		"hidden": true,
		"color": Color(0.5, 0.95, 0.55),
		"desc": "The boss chest spins a fourth reel and favours higher rarities.",
	},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func description(id: String) -> String:
	return String(get_def(id).get("desc", ""))


static func color(id: String) -> Color:
	return get_def(id).get("color", Color.WHITE)


static func is_positive(id: String) -> bool:
	return int(get_def(id).get("polarity", -1)) > 0


static func is_negative(id: String) -> bool:
	return int(get_def(id).get("polarity", -1)) < 0


static func is_hidden(id: String) -> bool:
	return bool(get_def(id).get("hidden", false))


# Per-dungeon-node seed: each map node gets a distinct but deterministic dungeon
# (host + peers agree because run_seed is shared). Used by both the run-map UI and
# the in-dungeon DungeonAffixController so they show/spawn the SAME affixes.
static func node_seed(run_seed: int, node_id: int) -> int:
	return run_seed ^ node_id


# Build a node's layer to `depth`, chaining the native generator's descend() so each
# level inherits the parent's affixes + one more negative (the press-your-luck rule).
# Returns a DungeonLayerRef, or null if the Rust extension isn't built/loaded.
static func generate_node_layer(seed_value: int, difficulty: int, depth: int = 0):
	if not ClassDB.class_exists("DungeonGenerator"):
		return null
	var gen = ClassDB.instantiate("DungeonGenerator")
	if gen == null:
		return null
	var layer = gen.call("generate", seed_value, difficulty, 0)
	for _i in depth:
		if layer == null:
			break
		layer = gen.call("descend", layer)
	return layer


# Ask the native generator for a node's affix dicts. Empty if the extension is absent.
static func generate_node_affixes(seed_value: int, difficulty: int, depth: int = 0) -> Array:
	var layer = generate_node_layer(seed_value, difficulty, depth)
	if layer == null:
		return []
	return layer.call("affixes")


# Hover text for a map node: only NEGATIVES are revealed (positives are a hidden
# surprise on entry). Returns "" when there is nothing worth warning about.
static func tooltip_for_affixes(affixes: Array) -> String:
	var negs: Array = ids_from(affixes, "negative")
	if negs.is_empty():
		return ""
	var lines: Array = ["⚠ Dungeon affixes:"]
	for id in negs:
		lines.append("• %s — %s" % [display_name(id), description(id)])
	return "\n".join(lines)


# Pull the affix-id strings out of the bridge's affix dictionaries
# ({id, polarity, hidden, magnitude}), optionally filtered by polarity.
static func ids_from(affixes: Array, only: String = "all") -> Array:
	var out: Array = []
	for a in affixes:
		var id: String = String((a as Dictionary).get("id", ""))
		if id == "":
			continue
		match only:
			"negative":
				if is_negative(id):
					out.append(id)
			"positive":
				if is_positive(id):
					out.append(id)
			_:
				out.append(id)
	return out
