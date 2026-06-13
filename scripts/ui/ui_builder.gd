class_name UIBuilder
extends RefCounted

# Small factory helpers for repeated UI construction idioms.
#
# Many overlay panels (pause menu, rest/shrine choices, spec-path, merchant,
# lobby, …) open by spawning a full-rect dim ColorRect behind a centred panel —
# the same five lines copy-pasted across ~19 files. dim_overlay() collapses that
# into one call. The returned node is NOT yet parented; the caller adds it where
# it wants in the tree (z-order is decided by add order).

# A full-rect dim background. `block_mouse` STOP (default) swallows clicks so the
# world behind the panel isn't interactable; pass false for purely decorative
# tints that should let input through.
static func dim_overlay(color: Color, block_mouse: bool = true) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_STOP if block_mouse else Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect
