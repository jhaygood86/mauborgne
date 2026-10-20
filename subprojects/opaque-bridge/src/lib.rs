// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! OPAQUE (RFC 9807) bridge for Mauborgne Cloud Backup.
//!
//! One crate, one ciphersuite, two consumers: the Cloudflare Worker (server
//! functions, compiled to WASM) and the apps (client functions, native C ABI).
//! Sharing the code guarantees both sides agree on every parameter.
//!
//! Every function is stateless: intermediate protocol state is serialized and
//! handed back to the caller, so neither a Worker isolate nor a UI needs to keep
//! objects alive between round trips.

mod suite;

#[cfg(feature = "client")]
pub mod client;
#[cfg(feature = "server")]
pub mod server;

#[cfg(all(feature = "client", not(target_arch = "wasm32")))]
mod ffi;
#[cfg(all(feature = "server", target_arch = "wasm32"))]
mod wasm;
#[cfg(all(feature = "client", target_arch = "wasm32"))]
mod wasm_client;

pub use suite::{BridgeError, SERVER_IDENTIFIER};
