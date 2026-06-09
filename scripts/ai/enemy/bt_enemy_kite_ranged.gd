extends BTAction
class_name BTEnemyKiteRanged

## Ranged enemy: kite to keep the target near ranged_kite_distance (retreat if too
## close, approach if too far, hold in the band) and fire a ranged attack whenever in
## attack range and off cooldown. Mirrors the legacy is_ranged branch — parity.


func _tick(_delta: float) -> Status:
	var e := get_agent()
	if e == null or e.call("bt_target") == null:
		return FAILURE
	var d: float = e.call("bt_dist")
	var kite: float = e.call("bt_kite_distance")
	if d < kite - 30.0:
		e.call("bt_retreat", 1.0)
	elif d > kite + 30.0:
		e.call("bt_move_toward_target", 1.0)
	else:
		e.call("bt_hold")
	if e.call("bt_in_attack_range") and e.call("bt_can_attack"):
		e.call("bt_ranged_attack")
	return RUNNING
