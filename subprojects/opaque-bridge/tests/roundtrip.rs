// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

use opaque_bridge::{client, server};

const CRED: &[u8] = b"credential-id-1";

fn register(setup: &[u8], password: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let start = client::registration_start(password).unwrap();
    let response = server::registration_start(setup, &start.request, CRED).unwrap();
    let finish = client::registration_finish(password, &start.state, &response, CRED).unwrap();
    let record = server::registration_finish(&finish.upload).unwrap();
    (record, finish.export_key)
}

#[test]
fn login_with_correct_password_agrees_on_keys() {
    let setup = server::setup_new();
    let (record, export_key) = register(&setup, b"correct horse battery staple");

    let start = client::login_start(b"correct horse battery staple").unwrap();
    let server_start = server::login_start(&setup, Some(&record), &start.request, CRED).unwrap();
    let finish =
        client::login_finish(b"correct horse battery staple", &start.state, &server_start.response, CRED)
            .unwrap();
    let server_key = server::login_finish(&server_start.state, &finish.finalization, CRED).unwrap();

    assert_eq!(finish.session_key, server_key);
    // export_key is the stable, client-only secret used to wrap backup keys.
    assert_eq!(finish.export_key, export_key);
}

#[test]
fn wrong_password_is_rejected_by_the_client() {
    let setup = server::setup_new();
    let (record, _) = register(&setup, b"right password");

    let start = client::login_start(b"wrong password").unwrap();
    let server_start = server::login_start(&setup, Some(&record), &start.request, CRED).unwrap();
    let result = client::login_finish(b"wrong password", &start.state, &server_start.response, CRED);
    assert!(result.is_err());
}

#[test]
fn unknown_identity_never_yields_a_session() {
    let setup = server::setup_new();
    let start = client::login_start(b"anything").unwrap();
    // No record: the server still answers, indistinguishably from a real account.
    let server_start = server::login_start(&setup, None, &start.request, CRED).unwrap();
    let result = client::login_finish(b"anything", &start.state, &server_start.response, CRED);
    assert!(result.is_err());
}

#[test]
fn export_key_differs_per_server_setup() {
    // The OPRF key lives in the server setup: without it, KV contents alone
    // cannot be used for offline guessing.
    let (_, key_a) = register(&server::setup_new(), b"same password");
    let (_, key_b) = register(&server::setup_new(), b"same password");
    assert_ne!(key_a, key_b);
}

#[test]
fn login_bound_to_credential_identifier() {
    let setup = server::setup_new();
    let (record, _) = register(&setup, b"pw");
    let start = client::login_start(b"pw").unwrap();
    let server_start = server::login_start(&setup, Some(&record), &start.request, b"other-id").unwrap();
    assert!(client::login_finish(b"pw", &start.state, &server_start.response, CRED).is_err());
}
