//! Dungeon affixes — run-modifiers rolled per layer.
//!
//! Design (agreed):
//!   * 3 negative + 3 positive in the visible pool; the enum can grow freely.
//!   * Negatives are COMMON and shown on the run-map up front (informed risk).
//!   * Positives are RARE and HIDDEN until the party enters (a pleasant gamble).
//!   * Descending one layer adds exactly ONE extra negative (never positive),
//!     while loot ×1.5 and enemies +1 level (applied engine-side).

use crate::rng::Rng;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Polarity {
    Positive,
    Negative,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AffixId {
    // ── Negative (common, visible) ───────────────────────────────
    /// "Удушающий мрак": a smoke cloud chases the party; standing in it stacks DoT.
    SuffocatingGloom,
    /// "Нестабильные сферы": orbs spawn and explode for heavy AoE if not killed in time.
    VolatileSpheres,
    /// "Гнев небес": telegraphed lightning strikes player positions, then goes on cooldown.
    HeavensWrath,
    // ── Positive (rare, hidden until entered) ────────────────────
    /// "Золотая жила": enemies drop ×3 gold; rare golden enemy drops a mini-chest.
    GoldVein,
    /// "Эхо силы": shrine bursts grant a stacking buff that lasts the layer AND
    /// carries through a descent — rewards greed.
    EchoOfPower,
    /// "Благосклонность Фортуны": the boss chest spins a 4th reel and shifts rarity up.
    FortunesFavor,
}

impl AffixId {
    pub const NEGATIVE: [AffixId; 3] = [
        AffixId::SuffocatingGloom,
        AffixId::VolatileSpheres,
        AffixId::HeavensWrath,
    ];
    pub const POSITIVE: [AffixId; 3] = [
        AffixId::GoldVein,
        AffixId::EchoOfPower,
        AffixId::FortunesFavor,
    ];

    pub fn polarity(self) -> Polarity {
        match self {
            AffixId::SuffocatingGloom | AffixId::VolatileSpheres | AffixId::HeavensWrath => {
                Polarity::Negative
            }
            AffixId::GoldVein | AffixId::EchoOfPower | AffixId::FortunesFavor => Polarity::Positive,
        }
    }

    /// Stable string id consumed by GDScript (`DungeonAffixes.apply`).
    pub fn as_str(self) -> &'static str {
        match self {
            AffixId::SuffocatingGloom => "suffocating_gloom",
            AffixId::VolatileSpheres => "volatile_spheres",
            AffixId::HeavensWrath => "heavens_wrath",
            AffixId::GoldVein => "gold_vein",
            AffixId::EchoOfPower => "echo_of_power",
            AffixId::FortunesFavor => "fortunes_favor",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Affix {
    pub id: AffixId,
    pub polarity: Polarity,
    /// Negatives are visible on the map; positives stay hidden until entry.
    pub hidden_on_map: bool,
    /// 0.5..1.5-ish strength multiplier so two rolls of the same affix differ.
    pub magnitude: f32,
}

impl Affix {
    fn make(id: AffixId, rng: &mut Rng) -> Self {
        let polarity = id.polarity();
        Affix {
            id,
            polarity,
            hidden_on_map: polarity == Polarity::Positive,
            magnitude: 0.8 + rng.unit() * 0.6, // 0.8..1.4
        }
    }
}

/// Per-affix independent roll chances (before difficulty scaling).
const NEG_CHANCE: f32 = 0.22;
const POS_CHANCE: f32 = 0.08;

/// Roll the affix set for a freshly entered dungeon (depth 0 of a node).
/// Higher difficulty nudges negative chance up; positives stay rare.
pub fn roll_base(rng: &mut Rng, difficulty: u8) -> Vec<Affix> {
    let mut out = Vec::new();
    let neg_p = NEG_CHANCE + 0.05 * difficulty as f32;
    for id in AffixId::NEGATIVE {
        if rng.chance(neg_p) {
            out.push(Affix::make(id, rng));
        }
    }
    for id in AffixId::POSITIVE {
        if rng.chance(POS_CHANCE) {
            out.push(Affix::make(id, rng));
        }
    }
    out
}

/// When descending, inherit the parent layer's affixes and add exactly one
/// NEW negative (never positive), if any negative is still free. Positives are
/// never added on descent — going deeper is pure risk-up / reward-up.
pub fn add_descent_negative(rng: &mut Rng, inherited: &[Affix]) -> Vec<Affix> {
    let mut out = inherited.to_vec();
    let free: Vec<AffixId> = AffixId::NEGATIVE
        .into_iter()
        .filter(|id| !out.iter().any(|a| a.id == *id))
        .collect();
    if !free.is_empty() {
        let pick = free[rng.below(free.len() as u32) as usize];
        out.push(Affix::make(pick, rng));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn polarity_and_hidden_consistent() {
        let mut rng = Rng::new(1);
        for id in AffixId::POSITIVE {
            let a = Affix::make(id, &mut rng);
            assert_eq!(a.polarity, Polarity::Positive);
            assert!(a.hidden_on_map);
        }
        for id in AffixId::NEGATIVE {
            let a = Affix::make(id, &mut rng);
            assert_eq!(a.polarity, Polarity::Negative);
            assert!(!a.hidden_on_map);
        }
    }

    #[test]
    fn descent_adds_one_negative_no_dupes() {
        let mut rng = Rng::new(42);
        let mut set = roll_base(&mut rng, 1);
        for _ in 0..3 {
            let before = set.len();
            set = add_descent_negative(&mut rng, &set);
            // Either added exactly one (a negative) or the pool was full.
            assert!(set.len() == before || set.len() == before + 1);
            // No duplicate ids ever.
            for i in 0..set.len() {
                for j in (i + 1)..set.len() {
                    assert_ne!(set[i].id, set[j].id, "duplicate affix");
                }
            }
            // Never more than 3 negatives total.
            let negs = set.iter().filter(|a| a.polarity == Polarity::Negative).count();
            assert!(negs <= 3);
        }
    }
}
