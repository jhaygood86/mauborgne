// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! wasm-bindgen exports of the client side. The Worker never ships these: they
//! exist so the Worker's tests (and Node tooling) can play the client role with
//! the very same code the native apps use.

use wasm_bindgen::prelude::*;

use crate::client;

fn err(e: crate::BridgeError) -> JsError {
    JsError::new(&e.to_string())
}

#[wasm_bindgen]
pub struct ClientStart {
    request: Vec<u8>,
    state: Vec<u8>,
}

#[wasm_bindgen]
impl ClientStart {
    #[wasm_bindgen(getter)]
    pub fn request(&self) -> Vec<u8> {
        self.request.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn state(&self) -> Vec<u8> {
        self.state.clone()
    }
}

#[wasm_bindgen]
pub struct ClientRegistrationResult {
    upload: Vec<u8>,
    export_key: Vec<u8>,
}

#[wasm_bindgen]
impl ClientRegistrationResult {
    #[wasm_bindgen(getter)]
    pub fn upload(&self) -> Vec<u8> {
        self.upload.clone()
    }

    #[wasm_bindgen(getter, js_name = exportKey)]
    pub fn export_key(&self) -> Vec<u8> {
        self.export_key.clone()
    }
}

#[wasm_bindgen]
pub struct ClientLoginResult {
    finalization: Vec<u8>,
    session_key: Vec<u8>,
    export_key: Vec<u8>,
}

#[wasm_bindgen]
impl ClientLoginResult {
    #[wasm_bindgen(getter)]
    pub fn finalization(&self) -> Vec<u8> {
        self.finalization.clone()
    }

    #[wasm_bindgen(getter, js_name = sessionKey)]
    pub fn session_key(&self) -> Vec<u8> {
        self.session_key.clone()
    }

    #[wasm_bindgen(getter, js_name = exportKey)]
    pub fn export_key(&self) -> Vec<u8> {
        self.export_key.clone()
    }
}

#[wasm_bindgen(js_name = clientRegistrationStart)]
pub fn client_registration_start(password: &[u8]) -> Result<ClientStart, JsError> {
    let r = client::registration_start(password).map_err(err)?;
    Ok(ClientStart { request: r.request, state: r.state })
}

#[wasm_bindgen(js_name = clientRegistrationFinish)]
pub fn client_registration_finish(
    password: &[u8],
    state: &[u8],
    response: &[u8],
    credential_id: &[u8],
) -> Result<ClientRegistrationResult, JsError> {
    let r = client::registration_finish(password, state, response, credential_id).map_err(err)?;
    Ok(ClientRegistrationResult { upload: r.upload, export_key: r.export_key })
}

#[wasm_bindgen(js_name = clientLoginStart)]
pub fn client_login_start(password: &[u8]) -> Result<ClientStart, JsError> {
    let r = client::login_start(password).map_err(err)?;
    Ok(ClientStart { request: r.request, state: r.state })
}

#[wasm_bindgen(js_name = clientLoginFinish)]
pub fn client_login_finish(
    password: &[u8],
    state: &[u8],
    response: &[u8],
    credential_id: &[u8],
) -> Result<ClientLoginResult, JsError> {
    let r = client::login_finish(password, state, response, credential_id).map_err(err)?;
    Ok(ClientLoginResult {
        finalization: r.finalization,
        session_key: r.session_key,
        export_key: r.export_key,
    })
}
