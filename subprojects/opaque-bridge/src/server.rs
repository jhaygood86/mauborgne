// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! Server side of OPAQUE, compiled to WASM for the Cloudflare Worker.
//! It only ever sees OPRF messages, the registration record and a session key.

use rand::rngs::OsRng;
use opaque_ke::{
    CredentialFinalization, CredentialRequest, RegistrationRequest, RegistrationUpload,
    ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup,
};

use crate::suite::{BridgeError, Suite, identifiers};

pub struct LoginStart {
    pub response: Vec<u8>,
    /// Hold server-side (short TTL, single use) until `login_finish`.
    pub state: Vec<u8>,
}

/// New server setup: OPRF seed plus the server's long-term AKE key pair.
/// Store the result as the `OPAQUE_SERVER_SETUP` Worker secret.
pub fn setup_new() -> Vec<u8> {
    ServerSetup::<Suite>::new(&mut OsRng).serialize().to_vec()
}

fn load_setup(setup: &[u8]) -> Result<ServerSetup<Suite>, BridgeError> {
    ServerSetup::<Suite>::deserialize(setup).map_err(|_| BridgeError::Malformed)
}

pub fn registration_start(
    setup: &[u8],
    request: &[u8],
    credential_id: &[u8],
) -> Result<Vec<u8>, BridgeError> {
    let setup = load_setup(setup)?;
    let request = RegistrationRequest::deserialize(request).map_err(|_| BridgeError::Malformed)?;
    let r = ServerRegistration::<Suite>::start(&setup, request, credential_id)
        .map_err(|_| BridgeError::Protocol)?;
    Ok(r.message.serialize().to_vec())
}

/// Turns the client's upload into the record to persist.
pub fn registration_finish(upload: &[u8]) -> Result<Vec<u8>, BridgeError> {
    let upload =
        RegistrationUpload::<Suite>::deserialize(upload).map_err(|_| BridgeError::Malformed)?;
    Ok(ServerRegistration::<Suite>::finish(upload).serialize().to_vec())
}

/// `record` is `None` for an unknown identity: the library then answers with a
/// fake record, so the reply looks the same as for a real account.
pub fn login_start(
    setup: &[u8],
    record: Option<&[u8]>,
    request: &[u8],
    credential_id: &[u8],
) -> Result<LoginStart, BridgeError> {
    let setup = load_setup(setup)?;
    let record = match record {
        Some(bytes) => Some(
            ServerRegistration::<Suite>::deserialize(bytes).map_err(|_| BridgeError::Malformed)?,
        ),
        None => None,
    };
    let request = CredentialRequest::deserialize(request).map_err(|_| BridgeError::Malformed)?;
    let r = ServerLogin::start(
        &mut OsRng,
        &setup,
        record,
        request,
        credential_id,
        ServerLoginParameters {
            context: None,
            identifiers: identifiers(credential_id),
        },
    )
    .map_err(|_| BridgeError::Protocol)?;
    Ok(LoginStart {
        response: r.message.serialize().to_vec(),
        state: r.state.serialize().to_vec(),
    })
}

/// Returns the session key. Fails unless the client proved knowledge of the
/// password (a wrong password, or a login against a fake record).
pub fn login_finish(
    state: &[u8],
    finalization: &[u8],
    credential_id: &[u8],
) -> Result<Vec<u8>, BridgeError> {
    let state = ServerLogin::<Suite>::deserialize(state).map_err(|_| BridgeError::Malformed)?;
    let finalization =
        CredentialFinalization::deserialize(finalization).map_err(|_| BridgeError::Malformed)?;
    let r = state
        .finish(
            finalization,
            ServerLoginParameters {
                context: None,
                identifiers: identifiers(credential_id),
            },
        )
        .map_err(|_| BridgeError::Protocol)?;
    Ok(r.session_key.to_vec())
}
