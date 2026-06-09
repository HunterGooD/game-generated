extends GutTest

# EnemyPool — recycling of enemy nodes instead of instance/free on every spawn/death.
# Covers: acquire hands out a configured enemy in the right groups; release parks it and
# pulls it from the "enemy" group; the same node is reused; a reused enemy carries NO
# stale state (affixes/aura/HP/status/dead/networking); the death exit returns to pool;
# and the double-release guard holds.

var _parent: Node2D


func before_each() -> void:
	EnemyPool.clear()
	_parent = Node2D.new()
	add_child_autofree(_parent)


func after_each() -> void:
	EnemyPool.clear()


# ── acquire ─────────────────────────────────────────────────────────────────────
func test_acquire_returns_configured_enemy_in_group() -> void:
	var e := EnemyPool.acquire(_parent, Vector2(50, 50))
	assert_not_null(e)
	e.configure({"max_hp": 100})
	assert_true(e.is_in_group("enemy"), "active enemy is in the enemy group")
	assert_eq(e.get_parent(), _parent, "parented under the requested node")
	assert_eq(e.global_position, Vector2(50, 50))
	assert_false(e.dead)
	assert_eq(e.get("_pool"), EnemyPool, "knows its pool so death returns it here")
	assert_eq(e.process_mode, Node.PROCESS_MODE_INHERIT, "active enemy processes")


# ── release ─────────────────────────────────────────────────────────────────────
func test_release_parks_and_leaves_group() -> void:
	var e := EnemyPool.acquire(_parent)
	var before := EnemyPool.idle_count()
	EnemyPool.release(e)
	assert_eq(EnemyPool.idle_count(), before + 1, "parked in the pool")
	assert_false(e.is_in_group("enemy"), "idle enemy leaves the enemy group")
	assert_ne(e.get_parent(), _parent, "reparented out of the world")
	assert_eq(e.process_mode, Node.PROCESS_MODE_DISABLED, "idle enemy stops processing")
	assert_false(e.visible, "idle enemy is hidden")


func test_acquire_reuses_a_released_node() -> void:
	var e1 := EnemyPool.acquire(_parent)
	EnemyPool.release(e1)
	var e2 := EnemyPool.acquire(_parent)
	assert_eq(e1, e2, "pool handed back the same instance instead of instancing a new one")
	assert_eq(EnemyPool.idle_count(), 0, "pool drained on reuse")
	assert_true(e2.is_in_group("enemy"), "reused enemy is back in the group")


# ── the cleanliness contract ──────────────────────────────────────────────────────
func test_reused_enemy_carries_no_stale_state() -> void:
	var elite := EnemyPool.acquire(_parent)
	elite.configure(
		{
			"max_hp": 100,
			"attack_damage": 20,
			"sprite_idle": "res://assets/sprites/characters/spider_hatchling_idle.png",
			"affixes": ["vital", "explosive", "shielded"],
		}
	)
	assert_true(elite.is_elite())
	assert_not_null(elite._aura, "elite had an aura")
	# Pile on per-life state that MUST not survive recycling.
	elite.burn_t = 5.0
	elite.burn_dps = 3.0
	elite.chill_stacks = 2
	elite.poison_stacks = 4
	elite.bleed_t = 2.0
	elite.slow_t = 2.0
	elite.slow_mult = 0.5
	elite.vuln_t = 1.0
	elite.taunt_target = _parent
	elite.attack_cd = 1.0
	elite.network_id = 77
	elite.is_puppet = true
	elite.velocity = Vector2(200, 0)

	EnemyPool.release(elite)
	var fresh := EnemyPool.acquire(_parent)
	assert_eq(fresh, elite, "same node recycled")
	fresh.configure({"max_hp": 50})  # re-used as a plain (non-elite) enemy

	assert_false(fresh.is_elite(), "no stale affixes")
	assert_eq(fresh.affixes, [], "affix list cleared")
	assert_false(fresh._explosive, "explosive flag cleared")
	assert_false(fresh._shielded, "shielded flag cleared")
	assert_null(fresh._aura, "aura silhouette torn down")
	assert_eq(fresh.burn_t, 0.0, "burn cleared")
	assert_eq(fresh.chill_stacks, 0, "chill cleared")
	assert_eq(fresh.poison_stacks, 0, "poison cleared")
	assert_eq(fresh.bleed_t, 0.0, "bleed cleared")
	assert_eq(fresh.slow_mult, 1.0, "slow cleared")
	assert_eq(fresh.vuln_t, 0.0, "vuln cleared")
	assert_null(fresh.taunt_target, "taunt cleared")
	assert_eq(fresh.attack_cd, 0.0, "attack cooldown cleared")
	assert_false(fresh.is_puppet, "puppet flag cleared")
	assert_eq(fresh.network_id, -1, "network id cleared")
	assert_eq(fresh.velocity, Vector2.ZERO, "velocity cleared")
	assert_false(fresh.dead, "alive again")
	assert_eq(fresh.max_hp, 50, "reconfigured stats applied")
	assert_eq(fresh.hp, fresh.max_hp, "full health on reuse")
	assert_true(fresh.visible, "visible again")


# ── death exit wiring + double-release guard ─────────────────────────────────────
func test_death_exit_returns_to_pool() -> void:
	var e := EnemyPool.acquire(_parent)
	var before := EnemyPool.idle_count()
	e._release_or_free()  # what the dissolve tween / safety timer call on death
	assert_eq(EnemyPool.idle_count(), before + 1, "pool-managed death returns to the pool")


func test_double_release_is_ignored() -> void:
	var e := EnemyPool.acquire(_parent)
	var before := EnemyPool.idle_count()
	e._release_or_free()  # dissolve tween
	e._release_or_free()  # late safety timer on the same corpse
	assert_eq(EnemyPool.idle_count(), before + 1, "the corpse is pooled exactly once")


func test_deferred_prewarm_populates_the_pool() -> void:
	# The spawner calls prewarm via call_deferred from _ready (a synchronous add_child there
	# fails with "parent busy setting up children"). Deferring runs it once the tree settles.
	EnemyPool.call_deferred("prewarm", 4, _parent)
	await wait_process_frames(3)
	assert_gte(EnemyPool.idle_count(), 4, "deferred prewarm filled the pool without error")


func test_idle_nodes_are_not_in_enemy_group() -> void:
	# A parked enemy must be invisible to enemy queries (kill_all, targeting, wave counts).
	var e := EnemyPool.acquire(_parent)
	assert_true(e in get_tree().get_nodes_in_group("enemy"), "live enemy is enumerated")
	EnemyPool.release(e)
	assert_false(e in get_tree().get_nodes_in_group("enemy"), "idle pooled enemy is not")
