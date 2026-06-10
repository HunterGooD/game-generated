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
    /// A buff pillar (the main loop content): grants a temporary effect and can spill a
    /// few enemies nearby while active — bonus XP/gold without a guaranteed chest.
    EventPillar,
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
            RoomKind::EventPillar => "event_pillar",
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
    b.grow_loops(&mut rng);
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
            RoomKind::EventPillar => (1, 0), // spawns its own enemies while active
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

    // Spine: Entry → (Corridor|Junction)* → Boss. The path MEANDERS — it always advances
    // in +x but wanders in y (and occasionally turns harder) so it reads as generated and
    // the boss/exit is never just "straight ahead".
    fn build_spine(&mut self, rng: &mut Rng) {
        // Longer dungeons now that side paths loop back instead of dead-ending.
        let len = (7 + self.depth as i32 + self.difficulty as i32).clamp(7, 16);
        self.entry = self.add_room(RoomKind::Entry, (0, 0), true, 0);
        self.spine.push(self.entry);

        let mut prev = self.entry;
        let mut x = 0i32;
        let mut y = 0i32;
        for _ in 1..len {
            x += 1;
            // Wander vertically: mostly small steps, sometimes a sharper turn. Bounded so
            // the dungeon stays roughly tube-shaped rather than spiralling away.
            let dy = match rng.below(8) {
                0 => -2,
                1 => 2,
                2 | 3 => -1,
                4 | 5 => 1,
                _ => 0,
            };
            y = (y + dy).clamp(-5, 5);
            // Fewer junctions → fewer side paths → less reward/event density.
            let kind = if rng.chance(0.38) {
                RoomKind::Junction
            } else {
                RoomKind::Corridor
            };
            let id = self.add_room(kind, (x, y), true, 0);
            self.connect(prev, id, EdgeKind::Corridor);
            self.spine.push(id);
            prev = id;
        }
        x += 1;
        self.boss = self.add_room(RoomKind::Boss, (x, y), true, 0);
        self.connect(prev, self.boss, EdgeKind::Corridor);
        self.spine.push(self.boss);
    }

    // Integer perpendicular offset to the chord A→B, `mag` cells to one `side` (±1).
    fn perp_offset(ax: i32, ay: i32, bx: i32, by: i32, mag: f32, side: i32) -> (i32, i32) {
        let dx = (bx - ax) as f32;
        let dy = (by - ay) as f32;
        let len = (dx * dx + dy * dy).sqrt().max(1.0);
        // perpendicular of (dx,dy) is (-dy,dx)
        let px = -dy / len;
        let py = dx / len;
        (
            (px * mag * side as f32).round() as i32,
            (py * mag * side as f32).round() as i32,
        )
    }

    // Grow side paths off the spine junctions. The vast majority LOOP back to a later
    // spine node (so the party never backtracks a cleared corridor); a few are short
    // dead-ends reserved for the high-value rooms (Vault) that are worth the round trip.
    fn grow_loops(&mut self, rng: &mut Rng) {
        // Spine indices of the junction rooms, in order.
        let jidx: Vec<usize> = (0..self.spine.len())
            .filter(|&i| self.rooms[self.spine[i] as usize].kind == RoomKind::Junction)
            .collect();
        // Last interior spine index (just before the boss) — a valid reconnect target.
        let last_interior = self.spine.len().saturating_sub(2);

        for (n, &si) in jidx.iter().enumerate() {
            let dir: i32 = if n % 2 == 0 { 1 } else { -1 };
            // Reconnect target: the next junction at least 2 ahead, else a spine node 2 on.
            let mut target: Option<usize> = jidx.iter().copied().find(|&k| k >= si + 2);
            if target.is_none() && si + 2 <= last_interior {
                target = Some(si + 2);
            }
            match target {
                // Loop is the default; a Vault-bearing dead-end is the rare alternative.
                Some(ti) if rng.chance(0.80) => self.build_loop(rng, si, ti, dir),
                _ => self.build_dead_branch(rng, si, dir),
            }
        }
    }

    // A parallel arc from spine node `si` that rejoins the spine at node `ti`, forming a
    // loop. Loop rooms carry the bulk of the content (event pillars, pylons, elites).
    fn build_loop(&mut self, rng: &mut Rng, si: usize, ti: usize, dir: i32) {
        let a = self.spine[si];
        let b = self.spine[ti];
        let ac = self.rooms[a as usize].cell;
        let bc = self.rooms[b as usize].cell;
        let span = (bc.0 - ac.0).abs().max(1);
        let n = span.clamp(2, 4);
        // Bulge the loop out perpendicular to the A→B chord (diagonal-aware).
        let (ox, oy) = Self::perp_offset(ac.0, ac.1, bc.0, bc.1, 2.5, dir);
        let mut prev = a;
        for k in 1..=n {
            let t = k as f32 / (n + 1) as f32;
            let mx = ac.0 + ((bc.0 - ac.0) as f32 * t).round() as i32;
            let my = ac.1 + ((bc.1 - ac.1) as f32 * t).round() as i32;
            let kind = self.pick_loop_room(rng);
            let id = self.add_room(kind, (mx + ox, my + oy), false, k as u8);
            self.connect(prev, id, EdgeKind::Door);
            prev = id;
        }
        self.connect(prev, b, EdgeKind::Door); // close the loop back into the spine
    }

    // A short dead-end (1–2 rooms) ending in a worth-the-backtrack reward room. Offset
    // perpendicular to the local spine direction so it juts off at an angle, not just ±y.
    fn build_dead_branch(&mut self, rng: &mut Rng, si: usize, dir: i32) {
        let a = self.spine[si];
        let acell = self.rooms[a as usize].cell;
        // Local spine heading from the previous to the next spine node.
        let pc = if si > 0 { self.rooms[self.spine[si - 1] as usize].cell } else { acell };
        let nc = if si + 1 < self.spine.len() {
            self.rooms[self.spine[si + 1] as usize].cell
        } else {
            acell
        };
        let (ox, oy) = Self::perp_offset(pc.0, pc.1, nc.0, nc.1, 1.0, dir);
        let rooms = rng.range(1, 2);
        let mut prev = a;
        for step in 1..=rooms {
            let cell = (acell.0 + ox * step, acell.1 + oy * step);
            let kind = if step == rooms {
                self.pick_dead_end(rng)
            } else {
                RoomKind::Corridor
            };
            let id = self.add_room(kind, cell, false, step as u8);
            self.connect(prev, id, EdgeKind::Door);
            prev = id;
        }
    }

    // Loop content. Many rooms are now EMPTY (plain Corridor) so the dungeon isn't wall-to-
    // wall rewards; fights are the staple, pillars/chests are the spice. Chest is rarest.
    fn pick_loop_room(&self, rng: &mut Rng) -> RoomKind {
        let d = self.difficulty as f32;
        let weights = [
            24.0,           // Corridor (empty pass-through — keeps density down)
            18.0,           // EventPillar
            22.0,           // Pylon
            7.0 + 3.0 * d,  // ElitePylon
            6.0,            // Pocket
            4.0,            // Merchant (runner guards it with a wave)
            3.0,            // DeadEnd (a treasure chest — rarest)
        ];
        let kinds = [
            RoomKind::Corridor,
            RoomKind::EventPillar,
            RoomKind::Pylon,
            RoomKind::ElitePylon,
            RoomKind::Pocket,
            RoomKind::Merchant,
            RoomKind::DeadEnd,
        ];
        kinds[rng.weighted(&weights)]
    }

    // Dead-end reward (backtrack-worthy): mostly Vaults, some treasure / pockets.
    fn pick_dead_end(&self, rng: &mut Rng) -> RoomKind {
        let d = self.difficulty as f32;
        let weights = [
            9.0 + 3.0 * d, // Vault (the backtrack-worthy prize)
            4.0,           // DeadEnd (treasure chest — rarer now)
            5.0,           // Pocket (a guarded fight)
        ];
        let kinds = [RoomKind::Vault, RoomKind::DeadEnd, RoomKind::Pocket];
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
