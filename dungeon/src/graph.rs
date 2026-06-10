//! Deterministic dungeon-layer graph generation.
//!
//! A dungeon is a stack of up to 5 LAYERS (depth 0..=4). Each layer is a
//! "кишка" (spine) entry → boss, with branches hanging off junctions that end
//! in dead-ends, pylons, elites, shrines, vaults, etc. The boss room always
//! holds an Exit portal and — by chance that grows with difficulty — a Descent
//! portal to the next, deeper layer.
//!
//! Generation is a pure function of `(seed, difficulty, depth)`, so co-op peers
//! rebuild identical layers from those three numbers alone.

use crate::affix::{self, Affix};
use crate::rng::Rng;

pub const MAX_DEPTH: u8 = 4; // 5 layers total (0..=4)

pub type RoomId = u32;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum RoomKind {
    Entry,
    Corridor,
    Junction,
    DeadEnd,
    Pylon,
    ElitePylon,
    Shrine,
    Puzzle,
    Vault,
    Merchant,
    Pocket,
    Boss,
    Descent,
    Exit,
}

impl RoomKind {
    pub fn as_str(self) -> &'static str {
        match self {
            RoomKind::Entry => "entry",
            RoomKind::Corridor => "corridor",
            RoomKind::Junction => "junction",
            RoomKind::DeadEnd => "dead_end",
            RoomKind::Pylon => "pylon",
            RoomKind::ElitePylon => "elite_pylon",
            RoomKind::Shrine => "shrine",
            RoomKind::Puzzle => "puzzle",
            RoomKind::Vault => "vault",
            RoomKind::Merchant => "merchant",
            RoomKind::Pocket => "pocket",
            RoomKind::Boss => "boss",
            RoomKind::Descent => "descent",
            RoomKind::Exit => "exit",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum EdgeKind {
    Corridor,
    Door,
    /// A locked door whose key drops from the elite in room `key_from`.
    LockedDoor(RoomId),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Biome {
    Ruins,
    Crypt,
    Frost,
    Garden,
    Infernal,
}

impl Biome {
    pub fn as_str(self) -> &'static str {
        match self {
            Biome::Ruins => "ruins",
            Biome::Crypt => "crypt",
            Biome::Frost => "frost",
            Biome::Garden => "garden",
            Biome::Infernal => "infernal",
        }
    }
    fn from_index(i: u32) -> Biome {
        match i % 5 {
            0 => Biome::Ruins,
            1 => Biome::Crypt,
            2 => Biome::Frost,
            3 => Biome::Garden,
            _ => Biome::Infernal,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Room {
    pub id: RoomId,
    pub kind: RoomKind,
    pub cell: (i32, i32),
    pub on_spine: bool,
    pub branch_len: u8,
    pub reward_tier: u8,  // 0..3 — fatter loot deeper in branches / higher tiers
    pub enemy_budget: u16, // raw spawn "points"; engine multiplies by difficulty/depth
}

#[derive(Clone, Copy, Debug)]
pub struct Edge {
    pub a: RoomId,
    pub b: RoomId,
    pub kind: EdgeKind,
}

pub struct DungeonLayer {
    pub seed: u64,
    pub depth: u8,
    pub difficulty: u8,
    pub biome: Biome,
    pub affixes: Vec<Affix>,
    pub rooms: Vec<Room>,
    pub edges: Vec<Edge>,
    pub spine: Vec<RoomId>,
    pub entry: RoomId,
    pub boss: RoomId,
    pub has_descent: bool,
}

impl DungeonLayer {
    pub fn room(&self, id: RoomId) -> &Room {
        &self.rooms[id as usize]
    }

    /// BFS reachability check used by tests and as a generation guarantee.
    pub fn boss_reachable_from_entry(&self) -> bool {
        let mut adj: Vec<Vec<RoomId>> = vec![Vec::new(); self.rooms.len()];
        for e in &self.edges {
            // Treat all edges as traversable for connectivity (locked doors are
            // openable once the key drops — we only require structural reach).
            adj[e.a as usize].push(e.b);
            adj[e.b as usize].push(e.a);
        }
        let mut seen = vec![false; self.rooms.len()];
        let mut stack = vec![self.entry];
        seen[self.entry as usize] = true;
        while let Some(n) = stack.pop() {
            if n == self.boss {
                return true;
            }
            for &m in &adj[n as usize] {
                if !seen[m as usize] {
                    seen[m as usize] = true;
                    stack.push(m);
                }
            }
        }
        false
    }
}

/// Public entry point. `depth` is clamped to 0..=MAX_DEPTH.
///
/// `inherited` carries the parent layer's affixes when descending (depth > 0);
/// pass `None` for a top-level dungeon. This is how a Descent adds one negative
/// per level while keeping the rolled-on-entry positives intact.
pub fn generate(
    seed: u64,
    difficulty: u8,
    depth: u8,
    inherited: Option<&[Affix]>,
) -> DungeonLayer {
    let depth = depth.min(MAX_DEPTH);
    let mut rng = Rng::derive(seed, depth as u64);

    let biome = Biome::from_index(rng.below(5));
    let affixes = match inherited {
        Some(prev) => affix::add_descent_negative(&mut rng, prev),
        None => affix::roll_base(&mut rng, difficulty),
    };

    let mut b = Builder::new(seed, difficulty, depth, biome, affixes);
    b.build_spine(&mut rng);
    b.grow_branches(&mut rng);
    b.resolve_vaults(&mut rng);
    b.finish_boss_room(&mut rng);
    b.into_layer()
}

// ── builder ─────────────────────────────────────────────────────────────────

struct Builder {
    seed: u64,
    difficulty: u8,
    depth: u8,
    biome: Biome,
    affixes: Vec<Affix>,
    rooms: Vec<Room>,
    edges: Vec<Edge>,
    spine: Vec<RoomId>,
    entry: RoomId,
    boss: RoomId,
    has_descent: bool,
}

impl Builder {
    fn new(seed: u64, difficulty: u8, depth: u8, biome: Biome, affixes: Vec<Affix>) -> Self {
        Builder {
            seed,
            difficulty,
            depth,
            biome,
            affixes,
            rooms: Vec::new(),
            edges: Vec::new(),
            spine: Vec::new(),
            entry: 0,
            boss: 0,
            has_descent: false,
        }
    }

    fn add_room(&mut self, kind: RoomKind, cell: (i32, i32), on_spine: bool, branch_len: u8) -> RoomId {
        let id = self.rooms.len() as RoomId;
        let (reward_tier, enemy_budget) = self.room_payload(kind, branch_len);
        self.rooms.push(Room {
            id,
            kind,
            cell,
            on_spine,
            branch_len,
            reward_tier,
            enemy_budget,
        });
        id
    }

    fn connect(&mut self, a: RoomId, b: RoomId, kind: EdgeKind) {
        self.edges.push(Edge { a, b, kind });
    }

    /// Reward/spawn budget per room kind. Deeper branches pay more; difficulty
    /// and depth scaling are applied engine-side from these raw values.
    fn room_payload(&self, kind: RoomKind, branch_len: u8) -> (u8, u16) {
        let bl = branch_len as u16;
        match kind {
            RoomKind::Pylon => (1 + (branch_len.min(2)), 20 + 8 * bl),
            RoomKind::ElitePylon => (2 + (branch_len.min(1)), 35 + 10 * bl),
            RoomKind::DeadEnd => (1 + (branch_len.min(2)), 0),
            RoomKind::Vault => (3, 0),
            RoomKind::Puzzle => (2, 0),
            RoomKind::Shrine => (0, 0),
            RoomKind::Merchant => (0, 0),
            RoomKind::Pocket => (2, 25 + 6 * bl),
            RoomKind::Boss => (3, 60),
            _ => (0, 0),
        }
    }

    // Spine: Entry → (Corridor|Junction)* → Boss laid along +x.
    fn build_spine(&mut self, rng: &mut Rng) {
        let len = (4 + self.depth as i32 + self.difficulty as i32).clamp(4, 12);
        self.entry = self.add_room(RoomKind::Entry, (0, 0), true, 0);
        self.spine.push(self.entry);

        let mut prev = self.entry;
        // Interior spine rooms (between entry and boss).
        for i in 1..len {
            // ~45% of interior rooms are junctions (branch anchors), rest corridors.
            let kind = if rng.chance(0.45) {
                RoomKind::Junction
            } else {
                RoomKind::Corridor
            };
            let id = self.add_room(kind, (i, 0), true, 0);
            self.connect(prev, id, EdgeKind::Corridor);
            self.spine.push(id);
            prev = id;
        }
        // Boss caps the spine.
        self.boss = self.add_room(RoomKind::Boss, (len, 0), true, 0);
        self.connect(prev, self.boss, EdgeKind::Corridor);
        self.spine.push(self.boss);
    }

    // Hang a branch off every Junction. Branch ends in a weighted-pick room.
    fn grow_branches(&mut self, rng: &mut Rng) {
        let junctions: Vec<RoomId> = self
            .spine
            .iter()
            .copied()
            .filter(|&id| self.rooms[id as usize].kind == RoomKind::Junction)
            .collect();

        for (n, jid) in junctions.into_iter().enumerate() {
            let jcell = self.rooms[jid as usize].cell;
            // Alternate branch direction so the layout fans out both sides.
            let dir: i32 = if n % 2 == 0 { 1 } else { -1 };
            let branch_rooms = rng.range(1, 4);
            let mut prev = jid;
            for step in 1..=branch_rooms {
                let cell = (jcell.0, jcell.1 + dir * step);
                let is_last = step == branch_rooms;
                let kind = if is_last {
                    self.pick_branch_end(rng)
                } else {
                    RoomKind::Corridor
                };
                let id = self.add_room(kind, cell, false, step as u8);
                self.connect(prev, id, EdgeKind::Door);
                prev = id;
            }
        }
    }

    // Weighted terminal-room pick. Rare types (Vault, Pocket) scale with difficulty.
    fn pick_branch_end(&self, rng: &mut Rng) -> RoomKind {
        let d = self.difficulty as f32;
        // order must match `kinds` below
        let weights = [
            34.0,            // DeadEnd
            26.0,            // Pylon
            10.0 + 4.0 * d,  // ElitePylon
            10.0,            // Shrine
            8.0,             // Puzzle
            4.0 + 3.0 * d,   // Vault
            8.0,             // Merchant
            3.0 + 1.5 * d,   // Pocket
        ];
        let kinds = [
            RoomKind::DeadEnd,
            RoomKind::Pylon,
            RoomKind::ElitePylon,
            RoomKind::Shrine,
            RoomKind::Puzzle,
            RoomKind::Vault,
            RoomKind::Merchant,
            RoomKind::Pocket,
        ];
        kinds[rng.weighted(&weights)]
    }

    // Every Vault needs a key from an ElitePylon in a DIFFERENT branch. If none
    // exists, downgrade the Vault to a DeadEnd so it's never unopenable.
    fn resolve_vaults(&mut self, rng: &mut Rng) {
        let vaults: Vec<RoomId> = self
            .rooms
            .iter()
            .filter(|r| r.kind == RoomKind::Vault)
            .map(|r| r.id)
            .collect();
        if vaults.is_empty() {
            return;
        }
        let elites: Vec<RoomId> = self
            .rooms
            .iter()
            .filter(|r| r.kind == RoomKind::ElitePylon)
            .map(|r| r.id)
            .collect();

        for vid in vaults {
            if elites.is_empty() {
                self.rooms[vid as usize].kind = RoomKind::DeadEnd;
                continue;
            }
            let key_from = elites[rng.below(elites.len() as u32) as usize];
            // Re-key the vault's incoming door to require that elite.
            for e in self.edges.iter_mut() {
                if e.b == vid {
                    e.kind = EdgeKind::LockedDoor(key_from);
                }
            }
        }
    }

    // Boss room always gets an Exit; add a Descent by chance (depth-capped).
    fn finish_boss_room(&mut self, rng: &mut Rng) {
        let bcell = self.rooms[self.boss as usize].cell;
        // Exit and Descent are placed on opposite sides so they never overlap.
        let exit = self.add_room(RoomKind::Exit, (bcell.0 + 1, 0), false, 0);
        self.connect(self.boss, exit, EdgeKind::Door);

        if self.depth < MAX_DEPTH {
            let chance = self.descent_chance();
            if rng.chance(chance) {
                let descent = self.add_room(RoomKind::Descent, (bcell.0 + 1, -1), false, 0);
                self.connect(self.boss, descent, EdgeKind::Door);
                self.has_descent = true;
            }
        }
    }

    // Deeper descents get likelier with difficulty; always below 1.0.
    fn descent_chance(&self) -> f32 {
        (0.20 + 0.12 * self.difficulty as f32).min(0.85)
    }

    fn into_layer(self) -> DungeonLayer {
        DungeonLayer {
            seed: self.seed,
            depth: self.depth,
            difficulty: self.difficulty,
            biome: self.biome,
            affixes: self.affixes,
            rooms: self.rooms,
            edges: self.edges,
            spine: self.spine,
            entry: self.entry,
            boss: self.boss,
            has_descent: self.has_descent,
        }
    }
}
