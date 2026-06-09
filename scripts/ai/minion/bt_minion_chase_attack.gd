extends BTAction
class_name BTMinionChaseAttack

## LimboAI task: chase the blackboard "target" until in range, then attack (the
## minion's bt_attack is cooldown-gated). Returns RUNNING while engaging so the
## dynamic selector keeps re-evaluating each tick.


func _tick(_delta: float) -> Status:
	var minion := get_agent()
	var t = get_blackboard().get_var("target", null)
	if minion == null or t == null or not is_instance_valid(t):
		return FAILURE
	if minion.call("bt_in_attack_range", t.global_position):
		minion.call("bt_attack", t)
	else:
		minion.call("bt_move_toward", t.global_position)
	return RUNNING
