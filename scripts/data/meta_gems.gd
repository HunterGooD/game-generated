class_name MetaGems
extends RefCounted

# Meta gems — the persistent stones socketed into the meta-mirror tree's socket nodes
# (see MetaTrees "socket" type + MetaProgress sockets state). Gems are GLOBAL (shared
# across classes, like the shard wallet) and only their bonuses are per-class, through
# whichever class's socket they sit in.
#
# Sources: the UBER-BOSS drops them (count scales with difficulty tier + loop), and the
# hub Fortune Teller gambles them for mirror shards (the meta currency that mini-bosses
# and bosses drop). Stateless catalog — owned counts live in MetaProgress (meta.save).
#
# Gem fields:
#   name   — Russian display name (project is RU-only for now).
#   rarity — "common" / "rare" / "epic" / "legendary" (drives roll weight + tint).
#   stats  — flat additive bonuses, same keys MetaProgress.meta_bonus feeds into
#            GameManager._apply_stat_dict.
#   pct    — percent bonuses (fractions), folded through MetaProgress.meta_percent
#            (supported keys: damage / max_hp / move_speed — see reset_run).

const RARITY_ORDER: Array = ["common", "rare", "epic", "legendary"]
const RARITY_DISPLAY: Dictionary = {
	"common": "Простой",
	"rare": "Редкий",
	"epic": "Эпический",
	"legendary": "Легендарный",
}
const RARITY_COLORS: Dictionary = {
	"common": Color(0.82, 0.82, 0.86),
	"rare": Color(0.45, 0.72, 1.0),
	"epic": Color(0.78, 0.42, 1.0),
	"legendary": Color(1.0, 0.65, 0.18),
}
# Base roll weights. `luck` (loot_rarity_bonus-style) multiplies each rarity's weight by
# (1 + luck × rank), so higher difficulty shifts rolls up WITHOUT ever zeroing commons.
const RARITY_WEIGHTS: Dictionary = {"common": 100.0, "rare": 42.0, "epic": 13.0, "legendary": 3.0}

const GEMS: Dictionary = {
	# ── common: one small flat stat ───────────────────────────────────────────
	"garnet_strength": {"name": "Гранат силы", "rarity": "common", "stats": {"strength": 4}},
	"beryl_dexterity": {"name": "Берилл ловкости", "rarity": "common", "stats": {"dexterity": 4}},
	"lapis_intellect": {"name": "Лазурит разума", "rarity": "common", "stats": {"intelligence": 4}},
	"shard_life": {"name": "Осколок жизни", "rarity": "common", "stats": {"max_hp": 25}},
	"shard_mana": {"name": "Осколок маны", "rarity": "common", "stats": {"max_mana": 25}},
	# ── rare: a meaningful flat line ──────────────────────────────────────────
	"ruby_fury": {"name": "Рубин ярости", "rarity": "rare", "stats": {"damage": 6}},
	"emerald_haste": {"name": "Изумруд стремительности", "rarity": "rare", "stats": {"move_speed": 14.0}},
	"topaz_precision": {"name": "Топаз меткости", "rarity": "rare", "stats": {"crit_chance": 0.03}},
	"amethyst_blood": {"name": "Аметист крови", "rarity": "rare", "stats": {"max_hp": 40, "strength": 3}},
	# ── epic: percent scaling / crit payoff ───────────────────────────────────
	"opal_carnage": {"name": "Опал бойни", "rarity": "epic", "stats": {"crit_damage": 0.25}},
	"storm_heart": {"name": "Сердце бури", "rarity": "epic", "pct": {"damage": 0.04}},
	"eye_eternity": {"name": "Око вечности", "rarity": "epic", "pct": {"max_hp": 0.05}},
	"wind_song": {"name": "Песнь ветра", "rarity": "epic", "pct": {"move_speed": 0.05}},
	# ── legendary: build-defining hybrids ─────────────────────────────────────
	"mirror_star": {"name": "Звезда Зеркала", "rarity": "legendary", "pct": {"damage": 0.05, "max_hp": 0.05}},
	"titan_crown":
	{
		"name": "Корона титана",
		"rarity": "legendary",
		"stats": {"strength": 8, "dexterity": 8, "intelligence": 8, "max_hp": 40},
	},
	"phoenix_tear":
	{"name": "Слеза феникса", "rarity": "legendary", "stats": {"max_mana": 40}, "pct": {"max_hp": 0.06}},
}

# Stat label map for tooltips (RU; true = render the value as a percent).
const _STAT_LABELS: Dictionary = {
	"max_hp": ["Макс. здоровье", false],
	"max_mana": ["Макс. мана", false],
	"damage": ["Урон", false],
	"move_speed": ["Скорость бега", false],
	"crit_chance": ["Шанс крита", true],
	"crit_damage": ["Крит. урон", true],
	"strength": ["Сила", false],
	"dexterity": ["Ловкость", false],
	"intelligence": ["Интеллект", false],
}


static func has_gem(id: String) -> bool:
	return GEMS.has(id)


static func get_gem(id: String) -> Dictionary:
	return GEMS.get(id, {})


static func display_name(id: String) -> String:
	return String(get_gem(id).get("name", id))


static func rarity_of(id: String) -> String:
	return String(get_gem(id).get("rarity", "common"))


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, Color(0.8, 0.8, 0.85))


static func rarity_display(rarity: String) -> String:
	return String(RARITY_DISPLAY.get(rarity, rarity))


static func ids_of_rarity(rarity: String) -> Array:
	var out: Array = []
	for id in GEMS:
		if String((GEMS[id] as Dictionary).get("rarity", "")) == rarity:
			out.append(String(id))
	return out


# Roll one random gem id. `luck` shifts the rarity weights upward (0 = gamble baseline;
# uber drops pass the difficulty tier's loot_rarity_bonus + loop luck).
static func roll(luck: float = 0.0) -> String:
	var total: float = 0.0
	var weights: Dictionary = {}
	for i in RARITY_ORDER.size():
		var r: String = String(RARITY_ORDER[i])
		var w: float = float(RARITY_WEIGHTS.get(r, 0.0)) * (1.0 + maxf(0.0, luck) * float(i))
		weights[r] = w
		total += w
	var pick: float = randf() * total
	var rarity: String = String(RARITY_ORDER[0])
	for r in RARITY_ORDER:
		pick -= float(weights[r])
		if pick <= 0.0:
			rarity = String(r)
			break
	var pool: Array = ids_of_rarity(rarity)
	if pool.is_empty():
		return "garnet_strength"
	return String(pool[randi() % pool.size()])


# Multiline RU tooltip: name, rarity, every bonus line.
static func describe(id: String) -> String:
	var g: Dictionary = get_gem(id)
	if g.is_empty():
		return id
	var lines: Array = []
	lines.append(String(g.get("name", id)))
	lines.append("Камень зеркала — " + rarity_display(String(g.get("rarity", "common"))))
	var stats: Dictionary = g.get("stats", {})
	for k in stats:
		lines.append("  " + _stat_line(String(k), stats[k]))
	var pct: Dictionary = g.get("pct", {})
	for k in pct:
		var meta: Array = _STAT_LABELS.get(k, [String(k).capitalize(), false])
		lines.append("  +%.0f%% %s" % [float(pct[k]) * 100.0, String(meta[0])])
	lines.append("Вставляется в гнездо мета-древа (◇).")
	return "\n".join(lines)


static func _stat_line(key: String, value) -> String:
	var meta: Array = _STAT_LABELS.get(key, [key.capitalize(), false])
	var label: String = String(meta[0])
	if bool(meta[1]):
		return "+%d%% %s" % [int(round(float(value) * 100.0)), label]
	return "+%s %s" % [str(value), label]
