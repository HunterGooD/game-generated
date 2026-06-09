extends BTAction
class_name BTEnemySpiderRetreat

## Spider hit-and-run, branch 1: while the post-bite retreat window is open, scuttle
## away fast (RUNNING). FAILURE when not retreating, so the selector falls through to
## the bite / approach branches.


func _tick(_delta: float) -> Status:
	var e := get_agent()
	if e == null or not e.call("bt_spider_is_retreating"):
		return FAILURE
	e.call("bt_retreat", 1.6)  # SPIDER_RETREAT_SPEED_MULT — fast backpedal
	return RUNNING
