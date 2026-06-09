extends BTAction
class_name BTEnemySpiderBite

## Spider hit-and-run, branch 2: when in melee range and off cooldown, bite once and
## immediately open the retreat window (so the next ticks scuttle away). SUCCESS on a
## bite; FAILURE otherwise so the selector falls through to Approach.


func _tick(_delta: float) -> Status:
	var e := get_agent()
	if e == null or e.call("bt_target") == null:
		return FAILURE
	if e.call("bt_in_melee_range") and e.call("bt_can_attack"):
		e.call("bt_melee_attack")
		e.call("bt_spider_start_retreat")
		return SUCCESS
	return FAILURE
