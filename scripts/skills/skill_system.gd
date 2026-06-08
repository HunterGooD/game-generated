class_name SkillSystem
extends Node

# Class-aware skill system (one per player). Holds per-player runtime state —
# cooldowns, applied modifiers, slot transforms, druid form, the resolved
# skill_ids — and the public API the HUD / level-up / character sheet / skill
# scripts call. The catalog data lives in SkillCatalog (typed SkillDefinition
# resources); the spawn/positioning/broadcast logic lives in SkillCaster. This
# node only resolves a slot to a definition, gates cooldown/mana, computes
# damage, builds the modifier dict, and delegates the spawn.

signal cooldown_started(slot: int, duration: float)
signal cooldown_finished(slot: int)
signal skill_failed(slot: int, reason: String)
signal modifier_applied(slot: int, modifier_id: String)
signal transform_applied(slot: int, transform_id: String)
signal skill_ids_changed

var skill_ids: Array = SkillCatalog.DEFAULT_SKILL_IDS.duplicate()
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var modifiers: Array = [{}, {}, {}, {}]
var transforms: Array = ["", "", "", ""]
var active_transforms: Array = []

# Druid-only: current shape ("human", "wolf", "bear", "eagle", "dire_wolf").
var druid_form: String = "human"

# Ascension ability (V1 Spec Paths) — a class-path skill cast on R with its own
# cooldown + mana cost (like an ultimate). "" until a path is chosen at level 7.
var ascension_skill_id: String = ""
var ascension_cd: float = 0.0


func _ready() -> void:
	_refresh_skill_ids()
	if GameManager:
		GameManager.class_selected.connect(_on_class_selected)
	# Repaint slot icons when gear changes — an equipped slot-swap unique
	# (e.g. Bone Spear) replaces a slot's skill, so its HUD icon must update.
	if InventorySystem and InventorySystem.has_signal("equipment_changed"):
		if not InventorySystem.equipment_changed.is_connected(_on_equipment_changed):
			InventorySystem.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed() -> void:
	skill_ids_changed.emit()


func _on_class_selected(_class_id: String) -> void:
	_refresh_skill_ids()
	# Reset cooldowns and modifiers on class change.
	for i in 4:
		cooldowns[i] = 0.0
		modifiers[i] = {}
		transforms[i] = ""
	active_transforms.clear()
	ascension_skill_id = ""
	ascension_cd = 0.0


func _refresh_skill_ids() -> void:
	if GameManager == null:
		return
	var data: Dictionary = GameManager.get_class_data()
	var ids: Array = data.get("skill_ids", SkillCatalog.DEFAULT_SKILL_IDS)
	if ids.size() < 4:
		ids = SkillCatalog.DEFAULT_SKILL_IDS
	skill_ids = ids.duplicate()
	# Druid: respect the current form for slots 0 & 1, and add Eagle Form as
	# the 5th "ultimate" slot bound to Q.
	if String(GameManager.player_class) == "druid":
		# Grow arrays to length 5 so slot 4 is addressable.
		if skill_ids.size() < 5:
			skill_ids.append("druid_eagle_form")
		else:
			skill_ids[4] = "druid_eagle_form"
		while cooldowns.size() < 5:
			cooldowns.append(0.0)
		while modifiers.size() < 5:
			modifiers.append({})
		while transforms.size() < 5:
			transforms.append("")
		_apply_druid_form_to_skill_ids()
	else:
		# Trim back to 4 for non-druid classes.
		if skill_ids.size() > 4:
			skill_ids.resize(4)
		if cooldowns.size() > 4:
			cooldowns.resize(4)
		if modifiers.size() > 4:
			modifiers.resize(4)
		if transforms.size() > 4:
			transforms.resize(4)
	skill_ids_changed.emit()


func _apply_druid_form_to_skill_ids() -> void:
	var pair: Array = SkillCatalog.DRUID_FORM_SLOTS.get(
		druid_form, SkillCatalog.DRUID_FORM_SLOTS["human"]
	)
	if skill_ids.size() < 5:
		skill_ids = [
			"druid_wolf_form",
			"druid_bear_form",
			"druid_stone_armor",
			"druid_summon_spirit",
			"druid_eagle_form"
		]
	skill_ids[0] = pair[0]
	skill_ids[1] = pair[1]
	# Slot 4 always shows Eagle Form. The script itself toggles between cast
	# (when human) and revert (when in any beast form) — see skill_druid_eagle_form.gd.
	skill_ids[4] = "druid_eagle_form"


# Called by the player when shapeshift starts/ends.
func set_druid_form(new_form: String) -> void:
	if not SkillCatalog.DRUID_FORM_SLOTS.has(new_form):
		new_form = "human"
	if new_form == druid_form:
		return
	druid_form = new_form
	# Reset cooldowns on the two slots that just swapped so the new form's
	# attacks are immediately usable.
	cooldowns[0] = 0.0
	cooldowns[1] = 0.0
	_apply_druid_form_to_skill_ids()
	skill_ids_changed.emit()


func get_druid_form() -> String:
	return druid_form


# Extra cooldown decay applied by external buffs (Temporal Dome cd-regen). Also
# nudges the ascension cooldown so the R recharges faster inside the dome too.
func reduce_all_cooldowns(amount: float) -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0.0:
			var prev: float = cooldowns[i]
			cooldowns[i] = max(0.0, cooldowns[i] - amount)
			if prev > 0.0 and cooldowns[i] == 0.0:
				cooldown_finished.emit(i)
	if ascension_cd > 0.0:
		ascension_cd = max(0.0, ascension_cd - amount)


func _process(delta: float) -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0.0:
			var prev: float = cooldowns[i]
			cooldowns[i] = max(0.0, cooldowns[i] - delta)
			if prev > 0.0 and cooldowns[i] == 0.0:
				cooldown_finished.emit(i)
	if ascension_cd > 0.0:
		ascension_cd = max(0.0, ascension_cd - delta)


# Ascension ability (R). Set when a spec path is chosen (player._on_spec_path_chosen).
func set_ascension(skill_id: String) -> void:
	ascension_skill_id = skill_id
	ascension_cd = 0.0
	skill_ids_changed.emit()


func get_ascension_skill_id() -> String:
	return ascension_skill_id


func get_ascension_icon() -> Texture2D:
	var d: SkillDefinition = SkillCatalog.get_def(ascension_skill_id)
	return d.get_icon() if d else null


func get_ascension_name() -> String:
	var d: SkillDefinition = SkillCatalog.get_def(ascension_skill_id)
	return d.display_name if d else ""


func get_ascension_cooldown_remaining() -> float:
	return ascension_cd


func get_ascension_cooldown_total() -> float:
	var d: SkillDefinition = SkillCatalog.get_def(ascension_skill_id)
	return d.cooldown if d else 1.0


# Cast the chosen ascension ability. Separate cooldown from the 4 skill slots;
# spends the ability's mana cost. Slot index -1 is used for failure signals.
func cast_ascension(caster: Node2D, mouse_world: Vector2) -> bool:
	if ascension_skill_id == "" or ascension_cd > 0.0:
		if ascension_cd > 0.0:
			skill_failed.emit(-1, "cooldown")
		return false
	var def: SkillDefinition = SkillCatalog.get_def(ascension_skill_id)
	if def == null:
		return false
	var cost: float = def.mana_cost
	if cost > 0.0 and (GameManager == null or not GameManager.spend_mana(cost)):
		skill_failed.emit(-1, "mana")
		return false
	ascension_cd = def.cooldown
	if AudioManager:
		AudioManager.play_sfx_path(def.sfx_path, -6.0)
	var base_damage: int = GameManager.player_damage if GameManager else 14
	var buff_mult: float = _player_buff_dmg(caster)
	var scaled_damage: int = int(round(float(base_damage) * def.damage_mult * buff_mult))
	var mods: Dictionary = {"transform": "", "caster": caster}
	for key in def.mod_wiring:
		# Ascension abilities don't use slot-modifiers, but honor const-only wiring.
		var entry: Dictionary = def.mod_wiring[key]
		mods[key] = entry.get("const", 0)
	return SkillCaster.spawn(def, caster, mouse_world, scaled_damage, mods)


func get_slot_def(slot: int) -> SkillDefinition:
	if slot < 0 or slot >= skill_ids.size():
		return null
	return SkillCatalog.get_def(String(skill_ids[slot]))


func get_cooldown_remaining(slot: int) -> float:
	if slot < 0 or slot >= cooldowns.size():
		return 0.0
	return cooldowns[slot]


func get_cooldown_total(slot: int) -> float:
	var d: SkillDefinition = get_slot_def(slot)
	return d.cooldown if d else 1.0


func get_skill_icon(slot: int) -> Texture2D:
	# Honor unique transforms — show the bone-spear / curse-field / hurricane
	# / dire-wolf icon when the corresponding unique is equipped.
	var d: SkillDefinition = get_slot_def(slot)
	var transform_id: String = get_transform(slot)
	if transform_id != "" and SkillCatalog.TRANSFORM_OVERRIDES.has(transform_id):
		d = SkillCatalog.get_def(String(SkillCatalog.TRANSFORM_OVERRIDES[transform_id]))
	if d == null:
		return null
	return d.get_icon()


func get_skill_name(slot: int) -> String:
	var d: SkillDefinition = get_slot_def(slot)
	var transform_id: String = get_transform(slot)
	if transform_id != "" and SkillCatalog.TRANSFORM_OVERRIDES.has(transform_id):
		d = SkillCatalog.get_def(String(SkillCatalog.TRANSFORM_OVERRIDES[transform_id]))
	return d.display_name if d else "?"


func add_modifier(slot: int, modifier_id: String) -> void:
	if slot < 0 or slot >= modifiers.size():
		return
	var m: Dictionary = modifiers[slot]
	m[modifier_id] = int(m.get(modifier_id, 0)) + 1
	modifiers[slot] = m
	modifier_applied.emit(slot, modifier_id)


func apply_transform(slot: int, transform_id: String) -> void:
	if slot < 0 or slot >= transforms.size():
		return
	transforms[slot] = transform_id
	if not active_transforms.has(transform_id):
		active_transforms.append(transform_id)
	transform_applied.emit(slot, transform_id)
	# Tell the HUD to repaint slot icon (so e.g. Bone Spear's icon replaces
	# Raise Skeleton's the moment the unique is equipped).
	skill_ids_changed.emit()


func get_modifier(slot: int, modifier_id: String) -> int:
	if slot < 0 or slot >= modifiers.size():
		return 0
	return int(modifiers[slot].get(modifier_id, 0))


func get_transform(slot: int) -> String:
	if slot < 0 or slot >= transforms.size():
		return ""
	# Level-up-applied transform wins; otherwise honor a slot-swap transform
	# granted by an EQUIPPED unique item.
	var t: String = transforms[slot]
	if t == "":
		t = _equipped_item_transform_for_slot(slot)
	if t == "":
		return ""
	# Form-aware guard: a slot-swap transform with a known base skill only applies
	# while the slot actually holds that base skill. Without this, a druid in a
	# beast form (slots 0/1 reused for in-form skills) would have those skills
	# hijacked by the human-form transform sitting on the same slot index.
	if (
		SkillCatalog.TRANSFORM_BASE_SKILL.has(t)
		and String(skill_ids[slot]) != String(SkillCatalog.TRANSFORM_BASE_SKILL[t])
	):
		return ""
	return t


# Returns the slot-swap transform id granted by an equipped unique item for this
# slot, or "" if none. (Item uniques only set the has_unique flag; this is what
# turns that flag into an actual slot swap.)
func _equipped_item_transform_for_slot(slot: int) -> String:
	if InventorySystem == null or not InventorySystem.has_method("has_unique"):
		return ""
	for tid in SkillCatalog.ITEM_TRANSFORM_SLOT:
		if (
			int(SkillCatalog.ITEM_TRANSFORM_SLOT[tid]) == slot
			and InventorySystem.call("has_unique", String(tid))
		):
			return String(tid)
	return ""


func try_cast(slot: int, caster: Node2D, mouse_world: Vector2) -> bool:
	if slot < 0 or slot >= skill_ids.size():
		return false
	if cooldowns[slot] > 0.0:
		skill_failed.emit(slot, "cooldown")
		return false
	# Slot transform → alternate skill (uniques replace the base slot).
	var skill_id_local: String = String(skill_ids[slot])
	var transform_id: String = get_transform(slot)
	if transform_id != "" and SkillCatalog.TRANSFORM_OVERRIDES.has(transform_id):
		skill_id_local = String(SkillCatalog.TRANSFORM_OVERRIDES[transform_id])
	var def: SkillDefinition = SkillCatalog.get_def(skill_id_local)
	if def == null:
		return false
	# Chronomancer Borrowed Second: at the cap the next skill is free (no mana,
	# half cooldown). consume_* returns 0.5 once when ready, else 1.0.
	var cd_mult: float = 1.0
	if caster and caster.has_method("consume_borrowed_second"):
		cd_mult = float(caster.call("consume_borrowed_second"))
	var free_cast: bool = cd_mult < 1.0
	var cost: float = def.mana_cost
	if not free_cast and cost > 0.0 and (GameManager == null or not GameManager.spend_mana(cost)):
		skill_failed.emit(slot, "mana")
		return false

	cooldowns[slot] = def.cooldown * cd_mult
	cooldown_started.emit(slot, cooldowns[slot])

	if AudioManager:
		AudioManager.play_sfx_path(def.sfx_path, -6.0)

	# Compute damage with stat scaling + modifier damage bonus + player buff.
	var base_damage: int = GameManager.player_damage if GameManager else 14
	var dmg_mult: float = def.damage_mult
	# Generic +damage modifiers: ANY modifier id ending in "_damage" grants +30%
	# per stack on its slot. Class-agnostic by convention — the mage's
	# "fw_damage"/"ib_damage"/"cl_damage"/"mt_damage" and every other class'
	# "<prefix>_<skill>_damage" all flow through here with no per-skill wiring.
	var stack_bonus: float = 0.0
	if slot >= 0 and slot < modifiers.size():
		for mod_id in modifiers[slot]:
			if String(mod_id).ends_with("_damage"):
				stack_bonus += 0.3 * float(modifiers[slot][mod_id])
	# Buff multiplier (from Battle Cry etc.).
	var buff_mult: float = _player_buff_dmg(caster)
	var scaled_damage: int = int(
		round(float(base_damage) * dmg_mult * (1.0 + stack_bonus) * buff_mult)
	)

	# Build per-skill modifier dict and delegate the spawn.
	var mods: Dictionary = _build_mods(slot, def, caster)
	var ok: bool = SkillCaster.spawn(def, caster, mouse_world, scaled_damage, mods)
	# Notify the caster's ascension passives (Battlemage stacks, Elementalist orbs).
	if ok and caster and caster.has_method("on_skill_cast"):
		caster.call("on_skill_cast", skill_id_local, def.behavior)
	return ok


# Data-driven version of the old _build_mods_for switch. Each def.mod_wiring entry
# resolves to  const + mul * get_modifier(slot, modifier)  (or a bool via as_bool),
# preserving int-ness when both const and mul are ints so consumers see identical
# values. `transform` and `caster` are always provided.
func _build_mods(slot: int, def: SkillDefinition, caster: Node) -> Dictionary:
	var mods: Dictionary = {
		"transform": get_transform(slot),
		"caster": caster,
	}
	for key in def.mod_wiring:
		var entry: Dictionary = def.mod_wiring[key]
		if bool(entry.get("as_bool", false)):
			mods[key] = get_modifier(slot, String(entry.get("modifier", ""))) > 0
			continue
		var c: Variant = entry.get("const", 0)
		var mul: Variant = entry.get("mul", 1)
		var count: int = 0
		if entry.has("modifier"):
			count = get_modifier(slot, String(entry["modifier"]))
		if typeof(c) == TYPE_INT and typeof(mul) == TYPE_INT:
			mods[key] = int(c) + int(mul) * count
		else:
			mods[key] = float(c) + float(mul) * float(count)
	return mods


func _player_buff_dmg(caster: Node) -> float:
	if caster and caster.has_method("get_buff_damage_mult"):
		return float(caster.call("get_buff_damage_mult"))
	return 1.0
