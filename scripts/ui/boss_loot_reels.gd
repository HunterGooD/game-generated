extends CanvasLayer

## Boss-chest reward: 3 (or 4) vertical slot-machine reels REVEAL the candidates,
## then the player PICKS one (Hades-boon style). The spin is pure theatre — the
## agency is in the choice, so it never feels rigged. Reserved for boss chests;
## ordinary dead-end chests keep the single horizontal `loot_roulette`.
##
## Built programmatically (no .tscn) so it drops in without scene wiring. Mirrors
## the conventions in loot_roulette.gd: LootRoller strips, ItemInstance icons,
## rarity frame colours, co-op never pauses the tree.

const STRIP_COUNT: int = 40
const FINAL_INDEX: int = 34  # which cell each reel lands on (the candidate)
const CELL_W: float = 196.0
const CELL_H: float = 188.0
const BASE_DURATION: float = 3.4
const STAGGER: float = 0.55  # each reel stops this much later → cascading reveal
const FRAME_COLORS: Dictionary = {
	"common": Color(0.65, 0.65, 0.70, 1),
	"rare": Color(0.4, 0.7, 1.0, 1),
	"legendary": Color(1.0, 0.65, 0.18, 1),
	"unique": Color(1.0, 0.35, 0.25, 1),
}

# One reel = a clipped column with an inner strip that scrolls vertically.
class Reel:
	extends RefCounted
	var inner: Control
	var clip: Control
	var button: Button
	var candidate: ItemInstance
	var tween: Tween
	var landed: bool = false

var reels: Array = []
var candidates: Array = []  # Array[ItemInstance] — one award per reel
var picked: bool = false
var settled_count: int = 0
var heading: Label
var prompt: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


## candidates: Array[ItemInstance] (length 3, or 4 with Fortune's Favor).
func start(award_candidates: Array, wave: int, class_id: String) -> void:
	candidates = award_candidates.duplicate()
	# Fortune's Favor (dungeon positive affix) adds a 4th reel of better-odds loot.
	if GameManager and GameManager.dungeon_extra_reel and candidates.size() < 4:
		var extra := LootRoller.roll_item(wave, class_id, GameManager.run_difficulty)
		if extra:
			candidates.append(extra)
	if candidates.is_empty():
		queue_free()
		return
	# Co-op keeps simulating while one player browses (see loot_roulette).
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = true
	_build_ui(wave, class_id)
	_spin()


func _build_ui(wave: int, class_id: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	heading = Label.new()
	heading.text = "BOSS REWARD — CHOOSE ONE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	heading.offset_top = 60.0
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6, 1))
	heading.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	heading.add_theme_constant_override("outline_size", 4)
	add_child(heading)

	var n: int = candidates.size()
	var total_w: float = n * CELL_W + (n - 1) * 24.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var start_x: float = (vp.x - total_w) * 0.5
	var col_y: float = (vp.y - CELL_H) * 0.5
	var visible_cells: int = 3
	var clip_h: float = CELL_H * visible_cells

	for i in n:
		var reel := Reel.new()
		reel.candidate = candidates[i]
		var x: float = start_x + i * (CELL_W + 24.0)

		# Clipped viewport column.
		var clip := Control.new()
		clip.position = Vector2(x, col_y - CELL_H)
		clip.size = Vector2(CELL_W, clip_h)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(clip)
		reel.clip = clip

		var inner := Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(inner)
		reel.inner = inner

		# Fill the strip; the real award sits at FINAL_INDEX.
		var strip: Array = LootRoller.roll_preview_strip(STRIP_COUNT, wave, class_id)
		strip[FINAL_INDEX] = reel.candidate
		for c in STRIP_COUNT:
			var cell := _build_cell(strip[c])
			cell.position = Vector2(0.0, float(c) * CELL_H)
			inner.add_child(cell)

		# Invisible button over the column — enabled only after the reel lands.
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2(x, col_y)
		btn.size = Vector2(CELL_W, CELL_H)
		btn.disabled = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_pick.bind(i))
		add_child(btn)
		reel.button = btn

		reels.append(reel)

	# Center marker line across the middle row.
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.85, 0.4, 0.5)
	marker.position = Vector2(start_x - 12.0, col_y - 2.0)
	marker.size = Vector2(total_w + 24.0, CELL_H + 4.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)

	prompt = Label.new()
	prompt.text = "..."
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -90.0
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1))
	add_child(prompt)


func _build_cell(item: ItemInstance) -> Control:
	var root := PanelContainer.new()
	var frame_col: Color = FRAME_COLORS.get(String(item.rarity), Color(1, 1, 1, 1))
	root.modulate = Color(
		frame_col.r * 0.6 + 0.4, frame_col.g * 0.6 + 0.4, frame_col.b * 0.6 + 0.4, 1
	)
	root.custom_minimum_size = Vector2(CELL_W - 8.0, CELL_H - 8.0)
	root.size = Vector2(CELL_W - 8.0, CELL_H - 8.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vb)
	var icon := TextureRect.new()
	icon.texture = item.get_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(130, 130)
	vb.add_child(icon)
	var lbl := Label.new()
	lbl.text = item.get_title()
	lbl.add_theme_color_override("font_color", frame_col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(lbl)
	return root


func _spin() -> void:
	var land_y: float = float(FINAL_INDEX) * CELL_H
	for i in reels.size():
		var reel: Reel = reels[i]
		reel.inner.position.y = -land_y * 0.0  # start at top (cell 0 centered)
		_set_reel_scroll(0.0, reel)
		var dur: float = BASE_DURATION + STAGGER * float(i)
		reel.tween = create_tween()
		(
			reel.tween
			. tween_method(_set_reel_scroll.bind(reel), 0.0, land_y, dur)
			. set_trans(Tween.TRANS_QUART)
			. set_ease(Tween.EASE_OUT)
		)
		reel.tween.tween_callback(_on_reel_done.bind(reel))


# scroll measured in pixels from the top; middle cell of the clip shows scroll/CELL_H.
func _set_reel_scroll(y: float, reel: Reel) -> void:
	var center_y: float = reel.clip.size.y * 0.5
	reel.inner.position.y = center_y - y - CELL_H * 0.5
	# Tick on each cell crossing.
	var idx: int = int(y / CELL_H)
	if idx != int(reel.get_meta("tick", 0)):
		reel.set_meta("tick", idx)
		if AudioManager:
			AudioManager.play_sfx_path(
				"res://assets/audio/sfx/ui/ui_loot_roulette_tick.mp3", -18.0
			)


func _on_reel_done(reel: Reel) -> void:
	reel.landed = true
	# Snap exactly so the visible cell == candidate.
	var center_y: float = reel.clip.size.y * 0.5
	reel.inner.position.y = center_y - float(FINAL_INDEX) * CELL_H - CELL_H * 0.5
	reel.button.disabled = false
	var col: Color = FRAME_COLORS.get(String(reel.candidate.rarity), Color(1, 1, 1, 0.2))
	if VfxManager:
		VfxManager.screen_flash(Color(col.r, col.g, col.b, 0.18), 0.25)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3", -10.0)
	settled_count += 1
	if settled_count >= reels.size() and prompt:
		prompt.text = "Click a reward to take it"


func _on_pick(index: int) -> void:
	if picked or index < 0 or index >= reels.size():
		return
	var reel: Reel = reels[index]
	if not reel.landed:
		return
	picked = true
	var award: ItemInstance = reel.candidate
	# Dim the reels not taken.
	for i in reels.size():
		if i != index:
			(reels[i] as Reel).clip.modulate = Color(0.4, 0.4, 0.4, 0.6)
		(reels[i] as Reel).button.disabled = true
	if InventorySystem and award:
		InventorySystem.add_item(award)
	if VfxManager and award:
		VfxManager.screen_flash(FRAME_COLORS.get(String(award.rarity), Color(1, 1, 1, 0.3)), 0.4)
	var path: String = "res://assets/audio/sfx/ui/ui_loot_reveal_common.mp3"
	match String(award.rarity):
		"rare":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_rare.mp3"
		"legendary":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_legendary.mp3"
		"unique":
			path = "res://assets/audio/sfx/ui/ui_loot_reveal_unique.mp3"
	if AudioManager:
		AudioManager.play_sfx_path(path, -4.0)
	# Brief beat to read the choice, then close.
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_callback(_close)


func _close() -> void:
	if not (NetManager and NetManager.is_multiplayer):
		get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Click / Enter / Space during the spin skips straight to all-landed.
	if settled_count < reels.size():
		var skip: bool = false
		if event is InputEventMouseButton and event.pressed:
			skip = true
		elif event is InputEventKey and event.pressed:
			if (
				event.keycode == KEY_ENTER
				or event.keycode == KEY_KP_ENTER
				or event.keycode == KEY_SPACE
			):
				skip = true
		if skip:
			_skip_to_reveal()
			get_viewport().set_input_as_handled()


func _skip_to_reveal() -> void:
	for reel in reels:
		var r: Reel = reel
		if r.landed:
			continue
		if r.tween and r.tween.is_valid():
			r.tween.kill()
		r.tween = null
		_set_reel_scroll(float(FINAL_INDEX) * CELL_H, r)
		_on_reel_done(r)
