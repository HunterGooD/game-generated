extends LimboState
class_name BossPhaseState

## A boss phase as a LimboAI HSM state. _enter applies the phase's modifiers (reusing
## boss._enter_phase) and plays the transition for non-initial phases; _update runs the
## shared combat step (chase + the phase's attack cycle). This is the extension point —
## a phase with unique behaviour (teleport, summon wave, bullet-hell) gets its own
## LimboState subclass plugged in for that phase index, without touching the others.

var phase_idx: int = 0


func _enter() -> void:
	var b = get_agent()
	if b == null:
		return
	b.current_phase_idx = phase_idx
	b._enter_phase(phase_idx)
	b.boss_phase_changed.emit(phase_idx)
	# Phase 0 is the start (set up in configure) — only later phases roar/knockback.
	if phase_idx > 0:
		b._play_phase_transition()


func _update(delta: float) -> void:
	var b = get_agent()
	if b != null:
		b.boss_combat_step(delta)
