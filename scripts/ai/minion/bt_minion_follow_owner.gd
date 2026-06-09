extends BTAction
class_name BTMinionFollowOwner

## LimboAI fallback task: follow the owning caster (or idle) when there is no enemy
## to engage. Delegates to the minion's bt_follow_owner(delta).


func _tick(delta: float) -> Status:
	var minion := get_agent()
	if minion == null or not minion.has_method("bt_follow_owner"):
		return FAILURE
	minion.call("bt_follow_owner", delta)
	return RUNNING
