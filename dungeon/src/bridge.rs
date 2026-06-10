//! gdext bridge — exposes the dungeon generator to Godot.
//!
//! Two `RefCounted` classes mirror the GDScript idiom already used by `RunMap`:
//! the generator returns a read-only layer wrapper whose accessors hand back
//! `Array<VarDictionary>` so the GDScript side reads it just like `run_map.gd`.
//!
//! Compiled only with `--features bridge` (pulls in the `godot` crate).

use godot::prelude::*;

use crate::affix::{Affix, Polarity};
use crate::graph::{self, DungeonLayer, EdgeKind};

struct DungeonExtension;

#[gdextension]
unsafe impl ExtensionLibrary for DungeonExtension {}

/// Stateless façade. `DungeonGenerator.new().generate(...)` from GDScript.
#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct DungeonGenerator;

#[godot_api]
impl DungeonGenerator {
    /// Generate a top-level dungeon layer (depth 0).
    /// Deterministic in `(seed, difficulty)`.
    #[func]
    fn generate(seed: i64, difficulty: i64, depth: i64) -> Gd<DungeonLayerRef> {
        let layer = graph::generate(seed as u64, difficulty.clamp(0, 255) as u8, depth.clamp(0, 255) as u8, None);
        Gd::from_object(DungeonLayerRef { layer })
    }

    /// Generate the next, deeper layer that inherits `parent`'s affixes and adds
    /// one more negative. Use this when the party takes a Descent portal.
    #[func]
    fn descend(parent: Gd<DungeonLayerRef>) -> Gd<DungeonLayerRef> {
        let p = parent.bind();
        let layer = graph::generate(
            p.layer.seed,
            p.layer.difficulty,
            p.layer.depth + 1,
            Some(&p.layer.affixes),
        );
        drop(p);
        Gd::from_object(DungeonLayerRef { layer })
    }
}

/// Read-only wrapper around a generated layer.
#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct DungeonLayerRef {
    layer: DungeonLayer,
}

#[godot_api]
impl DungeonLayerRef {
    #[func]
    fn depth(&self) -> i64 {
        self.layer.depth as i64
    }

    #[func]
    fn biome(&self) -> GString {
        self.layer.biome.as_str().into()
    }

    #[func]
    fn has_descent(&self) -> bool {
        self.layer.has_descent
    }

    #[func]
    fn entry_id(&self) -> i64 {
        self.layer.entry as i64
    }

    #[func]
    fn boss_id(&self) -> i64 {
        self.layer.boss as i64
    }

    #[func]
    fn spine(&self) -> PackedInt32Array {
        self.layer.spine.iter().map(|&id| id as i32).collect()
    }

    /// `{ id, polarity:+1/-1, hidden:bool, magnitude:float }`
    #[func]
    fn affixes(&self) -> Array<VarDictionary> {
        let mut out = Array::new();
        for a in &self.layer.affixes {
            out.push(&affix_dict(a));
        }
        out
    }

    /// `{ id, kind, cell:Vector2i, on_spine, branch_len, reward_tier, enemy_budget }`
    #[func]
    fn rooms(&self) -> Array<VarDictionary> {
        let mut out = Array::new();
        for r in &self.layer.rooms {
            let mut d = VarDictionary::new();
            d.set("id", r.id as i64);
            d.set("kind", r.kind.as_str());
            d.set("cell", Vector2i::new(r.cell.0, r.cell.1));
            d.set("on_spine", r.on_spine);
            d.set("branch_len", r.branch_len as i64);
            d.set("reward_tier", r.reward_tier as i64);
            d.set("enemy_budget", r.enemy_budget as i64);
            out.push(&d);
        }
        out
    }

    /// `{ a, b, kind, key_from:int(-1 if none) }`
    #[func]
    fn edges(&self) -> Array<VarDictionary> {
        let mut out = Array::new();
        for e in &self.layer.edges {
            let mut d = VarDictionary::new();
            d.set("a", e.a as i64);
            d.set("b", e.b as i64);
            let (kind, key_from): (&str, i64) = match e.kind {
                EdgeKind::Corridor => ("corridor", -1),
                EdgeKind::Door => ("door", -1),
                EdgeKind::LockedDoor(k) => ("locked_door", k as i64),
            };
            d.set("kind", kind);
            d.set("key_from", key_from);
            out.push(&d);
        }
        out
    }
}

fn affix_dict(a: &Affix) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("id", a.id.as_str());
    d.set("polarity", if a.polarity == Polarity::Positive { 1 } else { -1 });
    d.set("hidden", a.hidden_on_map);
    d.set("magnitude", a.magnitude);
    d
}
