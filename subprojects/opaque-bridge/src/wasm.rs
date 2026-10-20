// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! wasm-bindgen exports for the Cloudflare Worker (server side only).
//! Errors surface as a JS exception carrying a coarse message.

use wasm_bindgen::prelude::*;

use crate::server;

fn err(e: crate::BridgeError) -> JsError {
    JsError::new(&e.to_string())
}

#[wasm_bindgen]
pub struct LoginStart {
    response: Vec<u8>,
    state: Vec<u8>,
}

#[wasm_bindgen]
impl LoginStart {
    #[wasm_bindgen(getter)]
    pub fn response(&self) -> Vec<u8> {
        self.response.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn state(&self) -> Vec<u8> {
        self.state.clone()
    }
}

#[wasm_bindgen(js_name = setupNew)]
pub fn setup_new() -> Vec<u8> {
    server::setup_new()
}

#[wasm_bindgen(js_name = registrationStart)]
pub fn registration_start(
    setup: &[u8],
    request: &[u8],
    credential_id: &[u8],
) -> Result<Vec<u8>, JsError> {
    server::registration_start(setup, request, credential_id).map_err(err)
}

#[wasm_bindgen(js_name = registrationFinish)]
pub fn registration_finish(upload: &[u8]) -> Result<Vec<u8>, JsError> {
    server::registration_finish(upload).map_err(err)
}

/// Pass `undefined` as `record` for an unknown identity.
#[wasm_bindgen(js_name = loginStart)]
pub fn login_start(
    setup: &[u8],
    record: Option<Vec<u8>>,
    request: &[u8],
    credential_id: &[u8],
) -> Result<LoginStart, JsError> {
    let r = server::login_start(setup, record.as_deref(), request, credential_id).map_err(err)?;
    Ok(LoginStart { response: r.response, state: r.state })
}

#[wasm_bindgen(js_name = loginFinish)]
pub fn login_finish(
    state: &[u8],
    finalization: &[u8],
    credential_id: &[u8],
) -> Result<Vec<u8>, JsError> {
    server::login_finish(state, finalization, credential_id).map_err(err)
}
