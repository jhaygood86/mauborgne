// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

#![cfg_attr(not(feature = "client"), allow(dead_code, unused_imports))]

use opaque_ke::argon2::{Algorithm, Argon2, Params, Version};
use opaque_ke::{CipherSuite, Identifiers};

/// The server identifier bound into every credential envelope.
pub const SERVER_IDENTIFIER: &[u8] = b"mauborgne-cloud";

/// ristretto255 OPRF and key exchange, 3DH, Argon2id key stretching.
pub struct Suite;

impl CipherSuite for Suite {
    type OprfCs = opaque_ke::Ristretto255;
    type KeyExchange = opaque_ke::TripleDh<opaque_ke::Ristretto255, sha2::Sha512>;
    type Ksf = Argon2<'static>;
}

/// Argon2id parameters. Fixed in code: the stretched password feeds the envelope
/// key, so a client built with different values could not open another client's
/// registration. 64 MiB, 3 passes, 1 lane.
pub(crate) const ARGON_MEMORY_KIB: u32 = 64 * 1024;
pub(crate) const ARGON_PASSES: u32 = 3;
pub(crate) const ARGON_LANES: u32 = 1;

#[cfg(feature = "client")]
pub(crate) fn ksf() -> Argon2<'static> {
    Argon2::new(
        Algorithm::Argon2id,
        Version::V0x13,
        Params::new(ARGON_MEMORY_KIB, ARGON_PASSES, ARGON_LANES, None).expect("valid argon2 params"),
    )
}

pub(crate) fn identifiers(credential_id: &[u8]) -> Identifiers<'_> {
    Identifiers {
        client: Some(credential_id),
        server: Some(SERVER_IDENTIFIER),
    }
}

/// Any protocol, parsing or crypto failure. The detail is deliberately coarse:
/// callers must not be able to tell a wrong password from a malformed message.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeError {
    /// A message or state blob could not be parsed.
    Malformed,
    /// The protocol rejected the exchange (for example a wrong password).
    Protocol,
}

impl core::fmt::Display for BridgeError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            BridgeError::Malformed => f.write_str("malformed OPAQUE message"),
            BridgeError::Protocol => f.write_str("OPAQUE protocol failure"),
        }
    }
}

impl std::error::Error for BridgeError {}
