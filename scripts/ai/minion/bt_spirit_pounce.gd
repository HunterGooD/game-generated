extends BTAction
class_name BTSpiritPounce

## LimboAI task for the ghost wolf: leap onto the blackboard "target" when it sits in
## the mid-range pounce band and the leap is off cooldown. RUNNING while airborne (and
## while a fresh leap is launched) so the selector holds here; FAILURE otherwise, so
## the selector falls through to the normal chase/attack task.


func _tick(_delta: float) -> Status:
	var pet := get_agent()
	if pet == null or not pet.has_method("bt_is_leaping"):
		return FAILURE
	if pet.call("bt_is_leaping"):
		return RUNNING
	var t = get_blackboard().get_var("target", null)
	if t != null and is_instance_valid(t) and pet.call("bt_can_leap", t.global_position):
		pet.call("bt_start_leap", t)
		return RUNNING
	return FAILURE
