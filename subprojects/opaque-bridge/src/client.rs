// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! Client side of OPAQUE. Native only: the password and `export_key` never
//! exist on the server.

use rand::rngs::OsRng;
use opaque_ke::{
    ClientLogin, ClientLoginFinishParameters, ClientRegistration,
    ClientRegistrationFinishParameters, CredentialResponse, RegistrationResponse,
};

use crate::suite::{BridgeError, Suite, identifiers, ksf};

pub struct RegistrationStart {
    /// Send to the server.
    pub request: Vec<u8>,
    /// Keep locally until `registration_finish`.
    pub state: Vec<u8>,
}

pub struct RegistrationFinish {
    /// Send to the server to complete registration.
    pub upload: Vec<u8>,
    /// Never leaves the device. Derive the backup wrap key from it.
    pub export_key: Vec<u8>,
}

pub struct LoginStart {
    pub request: Vec<u8>,
    pub state: Vec<u8>,
}

pub struct LoginFinish {
    pub finalization: Vec<u8>,
    pub session_key: Vec<u8>,
    pub export_key: Vec<u8>,
}

pub fn registration_start(password: &[u8]) -> Result<RegistrationStart, BridgeError> {
    let r = ClientRegistration::<Suite>::start(&mut OsRng, password)
        .map_err(|_| BridgeError::Protocol)?;
    Ok(RegistrationStart {
        request: r.message.serialize().to_vec(),
        state: r.state.serialize().to_vec(),
    })
}

pub fn registration_finish(
    password: &[u8],
    state: &[u8],
    response: &[u8],
    credential_id: &[u8],
) -> Result<RegistrationFinish, BridgeError> {
    let state =
        ClientRegistration::<Suite>::deserialize(state).map_err(|_| BridgeError::Malformed)?;
    let response =
        RegistrationResponse::deserialize(response).map_err(|_| BridgeError::Malformed)?;
    let ksf = ksf();
    let r = state
        .finish(
            &mut OsRng,
            password,
            response,
            ClientRegistrationFinishParameters::new(identifiers(credential_id), Some(&ksf)),
        )
        .map_err(|_| BridgeError::Protocol)?;
    Ok(RegistrationFinish {
        upload: r.message.serialize().to_vec(),
        export_key: r.export_key.to_vec(),
    })
}

pub fn login_start(password: &[u8]) -> Result<LoginStart, BridgeError> {
    let r = ClientLogin::<Suite>::start(&mut OsRng, password).map_err(|_| BridgeError::Protocol)?;
    Ok(LoginStart {
        request: r.message.serialize().to_vec(),
        state: r.state.serialize().to_vec(),
    })
}

/// Fails with [`BridgeError::Protocol`] for a wrong password: the envelope
/// cannot be opened, so the client learns of the failure before the server does.
pub fn login_finish(
    password: &[u8],
    state: &[u8],
    response: &[u8],
    credential_id: &[u8],
) -> Result<LoginFinish, BridgeError> {
    let state = ClientLogin::<Suite>::deserialize(state).map_err(|_| BridgeError::Malformed)?;
    let response = CredentialResponse::deserialize(response).map_err(|_| BridgeError::Malformed)?;
    let ksf = ksf();
    let r = state
        .finish(
            &mut OsRng,
            password,
            response,
            ClientLoginFinishParameters::new(None, identifiers(credential_id), Some(&ksf)),
        )
        .map_err(|_| BridgeError::Protocol)?;
    Ok(LoginFinish {
        finalization: r.message.serialize().to_vec(),
        session_key: r.session_key.to_vec(),
        export_key: r.export_key.to_vec(),
    })
}
