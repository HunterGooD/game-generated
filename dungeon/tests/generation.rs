//! Integration tests for the pure dungeon core (no Godot needed).

use echoes_dungeon::affix::Polarity;
use echoes_dungeon::graph::{self, EdgeKind, RoomKind, MAX_DEPTH};

fn layer(seed: u64, diff: u8, depth: u8) -> graph::DungeonLayer {
    graph::generate(seed, diff, depth, None)
}

#[test]
fn deterministic_same_inputs_same_layer() {
    for seed in [1u64, 2, 99, 123456789] {
        let a = layer(seed, 2, 0);
        let b = layer(seed, 2, 0);
        assert_eq!(a.rooms.len(), b.rooms.len());
        assert_eq!(a.edges.len(), b.edges.len());
        for (ra, rb) in a.rooms.iter().zip(b.rooms.iter()) {
            assert_eq!(ra.kind, rb.kind);
            assert_eq!(ra.cell, rb.cell);
            assert_eq!(ra.enemy_budget, rb.enemy_budget);
        }
        assert_eq!(a.affixes.len(), b.affixes.len());
        assert_eq!(a.has_descent, b.has_descent);
    }
}

#[test]
fn boss_always_reachable_from_entry() {
    for seed in 0..400u64 {
        for diff in 0..4u8 {
            for depth in 0..=MAX_DEPTH {
                let l = layer(seed, diff, depth);
                assert!(
                    l.boss_reachable_from_entry(),
                    "boss unreachable seed={seed} diff={diff} depth={depth}"
                );
            }
        }
    }
}

#[test]
fn entry_and_boss_exist_and_are_distinct() {
    for seed in 0..200u64 {
        let l = layer(seed, 1, 0);
        assert_eq!(l.room(l.entry).kind, RoomKind::Entry);
        assert_eq!(l.room(l.boss).kind, RoomKind::Boss);
        assert_ne!(l.entry, l.boss);
        // Boss room always has exactly one Exit neighbour.
        let exits = l
            .rooms
            .iter()
            .filter(|r| r.kind == RoomKind::Exit)
            .count();
        assert_eq!(exits, 1, "seed={seed} expected exactly one exit");
    }
}

#[test]
fn vaults_are_always_openable() {
    // Every remaining Vault must have a LockedDoor keyed to an existing ElitePylon.
    for seed in 0..600u64 {
        let l = layer(seed, 3, 2);
        for r in l.rooms.iter().filter(|r| r.kind == RoomKind::Vault) {
            let keyed = l.edges.iter().any(|e| {
                e.b == r.id
                    && matches!(e.kind, EdgeKind::LockedDoor(k)
                        if l.room(k).kind == RoomKind::ElitePylon)
            });
            assert!(keyed, "vault {} has no valid key (seed={seed})", r.id);
        }
    }
}

#[test]
fn descent_never_past_max_depth() {
    for seed in 0..300u64 {
        let l = layer(seed, 3, MAX_DEPTH);
        assert!(!l.has_descent, "depth-{MAX_DEPTH} must not offer a descent");
        let descents = l
            .rooms
            .iter()
            .filter(|r| r.kind == RoomKind::Descent)
            .count();
        assert_eq!(descents, 0);
    }
}

#[test]
fn descent_inherits_affixes_and_adds_one_negative() {
    // Find a base layer that actually offers a descent, then descend.
    for seed in 0..2000u64 {
        let base = layer(seed, 3, 0);
        if !base.has_descent {
            continue;
        }
        let deeper = graph::generate(base.seed, base.difficulty, 1, Some(&base.affixes));
        // Every base affix is still present.
        for a in &base.affixes {
            assert!(
                deeper.affixes.iter().any(|x| x.id == a.id),
                "descent dropped an inherited affix"
            );
        }
        // At most one new affix, and if added it is negative.
        assert!(deeper.affixes.len() <= base.affixes.len() + 1);
        if deeper.affixes.len() == base.affixes.len() + 1 {
            let base_ids: Vec<_> = base.affixes.iter().map(|a| a.id).collect();
            let added = deeper
                .affixes
                .iter()
                .find(|a| !base_ids.contains(&a.id))
                .expect("a new affix");
            assert_eq!(added.polarity, Polarity::Negative);
        }
        return; // one good case is enough
    }
    panic!("no descent-bearing layer found to test");
}

#[test]
fn loops_reconnect_into_cycles() {
    // Side paths loop back into the spine, so most layers contain at least one cycle.
    // A connected graph with a cycle has |E| >= |V| (a tree is exactly |V|-1); leaf rooms
    // (exit/descent/dead-ends) add equal V and E, so this still detects the loops.
    let total: u64 = 200;
    let mut with_cycle = 0;
    for seed in 0..total {
        let l = layer(seed, 2, 0);
        if l.edges.len() >= l.rooms.len() {
            with_cycle += 1;
        }
    }
    assert!(
        with_cycle > (total / 2) as usize,
        "expected most layers to loop, got {with_cycle}/{total}"
    );
}

#[test]
fn event_pillars_appear() {
    // The new EventPillar is now common loop content.
    let mut total_pillars = 0;
    for seed in 0..200u64 {
        total_pillars += layer(seed, 2, 0)
            .rooms
            .iter()
            .filter(|r| r.kind == RoomKind::EventPillar)
            .count();
    }
    assert!(total_pillars > 0, "event pillars should be generated");
}

#[test]
fn positives_hidden_negatives_visible() {
    for seed in 0..500u64 {
        let l = layer(seed, 2, 0);
        for a in &l.affixes {
            match a.polarity {
                Polarity::Positive => assert!(a.hidden_on_map),
                Polarity::Negative => assert!(!a.hidden_on_map),
            }
        }
    }
}
