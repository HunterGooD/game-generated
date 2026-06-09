extends BTAction
class_name BTEnemyChaseMelee

## Melee enemy: chase the resolved target to melee range, then attack on cooldown.
## Mirrors the legacy melee branch (chase if dist > attack_range-10, else hold +
## attack) so behaviour is identical — parity proven in tests/unit/test_enemy_ai.


func _tick(_delta: float) -> Status:
	var e := get_agent()
	if e == null or e.call("bt_target") == null:
		return FAILURE
	if e.call("bt_in_melee_range"):
		e.call("bt_hold")
		if e.call("bt_can_attack"):
			e.call("bt_melee_attack")
	else:
		e.call("bt_move_toward_target", 1.0)
	return RUNNING
