//! Deterministic, dependency-free PRNG (splitmix64).
//!
//! Co-op REQUIRES bit-identical generation across machines: the host broadcasts
//! only `(seed, difficulty, depth)` and every peer rebuilds the same dungeon —
//! exactly as `RunMap` already does on the GDScript side. `rand::StdRng`/`thread_rng`
//! are NOT stable across crate versions or platforms, so we hand-roll splitmix64.
//! It is tiny, fast, and produces the same stream forever, on every target.

pub struct Rng {
    state: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Self {
        // Avoid a zero state degenerating the stream.
        Self {
            state: seed ^ 0x2545_F491_4F6C_DD1D,
        }
    }

    /// Derive an independent stream from a base seed and a salt (e.g. depth).
    /// Same inputs → same stream, so each dungeon layer is reproducible.
    pub fn derive(seed: u64, salt: u64) -> Self {
        Self::new(
            seed.wrapping_mul(0x9E37_79B9_7F4A_7C15)
                ^ salt.wrapping_mul(0xD1B5_4A32_D192_ED03),
        )
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in `0..n` (n must be > 0).
    #[inline]
    pub fn below(&mut self, n: u32) -> u32 {
        debug_assert!(n > 0, "Rng::below(0)");
        (self.next_u64() % n as u64) as u32
    }

    /// Inclusive integer range `[lo, hi]`.
    #[inline]
    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        if hi <= lo {
            return lo;
        }
        lo + self.below((hi - lo + 1) as u32) as i32
    }

    /// Float in `[0, 1)` with 24 bits of resolution.
    #[inline]
    pub fn unit(&mut self) -> f32 {
        ((self.next_u64() >> 40) as f32) / ((1u32 << 24) as f32)
    }

    /// True with probability `p` (clamped to [0,1]).
    #[inline]
    pub fn chance(&mut self, p: f32) -> bool {
        self.unit() < p.clamp(0.0, 1.0)
    }

    /// Weighted pick: returns the index of the chosen weight. Empty/zero → 0.
    pub fn weighted(&mut self, weights: &[f32]) -> usize {
        let total: f32 = weights.iter().map(|w| w.max(0.0)).sum();
        if total <= 0.0 {
            return 0;
        }
        let mut roll = self.unit() * total;
        for (i, w) in weights.iter().enumerate() {
            let w = w.max(0.0);
            if roll < w {
                return i;
            }
            roll -= w;
        }
        weights.len() - 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_stream() {
        let mut a = Rng::new(12345);
        let mut b = Rng::new(12345);
        for _ in 0..1000 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn derive_is_reproducible_and_distinct() {
        let s0a: Vec<u64> = (0..8).map(|_| Rng::derive(99, 0).next_u64()).collect();
        let s0b: Vec<u64> = (0..8).map(|_| Rng::derive(99, 0).next_u64()).collect();
        assert_eq!(s0a, s0b, "derive must be reproducible");
        let s1 = Rng::derive(99, 1).next_u64();
        let s0 = Rng::derive(99, 0).next_u64();
        assert_ne!(s0, s1, "different salt → different stream");
    }

    #[test]
    fn below_in_range() {
        let mut r = Rng::new(7);
        for _ in 0..10_000 {
            assert!(r.below(5) < 5);
        }
    }
}
