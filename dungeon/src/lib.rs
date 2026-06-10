//! echoes-dungeon — deterministic multi-layer dungeon graph generator.
//!
//! The pure core (`rng`, `affix`, `graph`) has no dependencies and is fully
//! unit-tested with `cargo test`. The `bridge` module is the gdext glue that
//! exposes the core to Godot; it is compiled only with `--features bridge`.

pub mod affix;
pub mod graph;
pub mod rng;

#[cfg(feature = "bridge")]
mod bridge;
