extends BTAction
class_name BTMinionAcquireTarget

## LimboAI task: writes the nearest enemy to blackboard "target"; FAILURE when none.
## Delegates to the minion's bt_acquire_target() so the BT and the legacy AI share
## one acquisition rule (parity; future Commander's Mark hooks there).


func _tick(_delta: float) -> Status:
	var minion := get_agent()
	if minion == null or not minion.has_method("bt_acquire_target"):
		return FAILURE
	var t = minion.call("bt_acquire_target")
	if t == null:
		return FAILURE
	get_blackboard().set_var("target", t)
	return SUCCESS
