extends BTAction
class_name BTEnemySpiderApproach

## Spider hit-and-run, branch 3 (fallback): close in on the target between bites.


func _tick(_delta: float) -> Status:
	var e := get_agent()
	if e == null or e.call("bt_target") == null:
		return FAILURE
	e.call("bt_move_toward_target", 1.0)
	return RUNNING
