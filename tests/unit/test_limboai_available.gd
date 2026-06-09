extends GutTest

# Phase-2 gate: confirms the LimboAI GDExtension actually registers its classes in
# this (headless) runtime before we build the minion behaviour tree on them.


func test_btplayer_registered() -> void:
	assert_true(ClassDB.class_exists("BTPlayer"), "LimboAI BTPlayer must be registered")


func test_core_bt_classes_registered() -> void:
	for c in ["BTTask", "BTAction", "BTCondition", "BTSequence", "BTSelector"]:
		assert_true(ClassDB.class_exists(c), "LimboAI class %s must be registered" % c)
