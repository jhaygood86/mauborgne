// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial
// SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com>

//! C ABI for the native client (P/Invoke from .NET).
//!
//! Every call returns 0 on success, 1 for a malformed input and 2 for a protocol
//! failure (wrong password included). Outputs are written to caller-provided
//! `OpaqueBuf` slots and must be released with `opaque_buf_free`.

use std::ptr;
use std::slice;

use crate::BridgeError;
use crate::client;

#[repr(C)]
pub struct OpaqueBuf {
    pub ptr: *mut u8,
    pub len: usize,
}

impl OpaqueBuf {
    const EMPTY: OpaqueBuf = OpaqueBuf { ptr: ptr::null_mut(), len: 0 };
}

fn to_buf(bytes: Vec<u8>) -> OpaqueBuf {
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    OpaqueBuf { ptr: Box::into_raw(boxed) as *mut u8, len }
}

fn code(e: BridgeError) -> i32 {
    match e {
        BridgeError::Malformed => 1,
        BridgeError::Protocol => 2,
    }
}

/// # Safety
/// `ptr` must be valid for `len` bytes, or `len` must be 0.
unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if len == 0 { &[] } else { unsafe { slice::from_raw_parts(ptr, len) } }
}

/// Releases a buffer returned by this library. Safe to call on an empty buffer.
///
/// # Safety
/// `buf` must come from this library and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn opaque_buf_free(buf: OpaqueBuf) {
    if !buf.ptr.is_null() {
        drop(unsafe { Box::from_raw(slice::from_raw_parts_mut(buf.ptr, buf.len)) });
    }
}

/// # Safety
/// All pointers must be valid; outputs must be non-null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn opaque_client_registration_start(
    password: *const u8,
    password_len: usize,
    out_request: *mut OpaqueBuf,
    out_state: *mut OpaqueBuf,
) -> i32 {
    unsafe {
        *out_request = OpaqueBuf::EMPTY;
        *out_state = OpaqueBuf::EMPTY;
        match client::registration_start(input(password, password_len)) {
            Ok(r) => {
                *out_request = to_buf(r.request);
                *out_state = to_buf(r.state);
                0
            }
            Err(e) => code(e),
        }
    }
}

/// # Safety
/// All pointers must be valid; outputs must be non-null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn opaque_client_registration_finish(
    password: *const u8,
    password_len: usize,
    state: *const u8,
    state_len: usize,
    response: *const u8,
    response_len: usize,
    credential_id: *const u8,
    credential_id_len: usize,
    out_upload: *mut OpaqueBuf,
    out_export_key: *mut OpaqueBuf,
) -> i32 {
    unsafe {
        *out_upload = OpaqueBuf::EMPTY;
        *out_export_key = OpaqueBuf::EMPTY;
        match client::registration_finish(
            input(password, password_len),
            input(state, state_len),
            input(response, response_len),
            input(credential_id, credential_id_len),
        ) {
            Ok(r) => {
                *out_upload = to_buf(r.upload);
                *out_export_key = to_buf(r.export_key);
                0
            }
            Err(e) => code(e),
        }
    }
}

/// # Safety
/// All pointers must be valid; outputs must be non-null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn opaque_client_login_start(
    password: *const u8,
    password_len: usize,
    out_request: *mut OpaqueBuf,
    out_state: *mut OpaqueBuf,
) -> i32 {
    unsafe {
        *out_request = OpaqueBuf::EMPTY;
        *out_state = OpaqueBuf::EMPTY;
        match client::login_start(input(password, password_len)) {
            Ok(r) => {
                *out_request = to_buf(r.request);
                *out_state = to_buf(r.state);
                0
            }
            Err(e) => code(e),
        }
    }
}

/// # Safety
/// All pointers must be valid; outputs must be non-null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn opaque_client_login_finish(
    password: *const u8,
    password_len: usize,
    state: *const u8,
    state_len: usize,
    response: *const u8,
    response_len: usize,
    credential_id: *const u8,
    credential_id_len: usize,
    out_finalization: *mut OpaqueBuf,
    out_session_key: *mut OpaqueBuf,
    out_export_key: *mut OpaqueBuf,
) -> i32 {
    unsafe {
        *out_finalization = OpaqueBuf::EMPTY;
        *out_session_key = OpaqueBuf::EMPTY;
        *out_export_key = OpaqueBuf::EMPTY;
        match client::login_finish(
            input(password, password_len),
            input(state, state_len),
            input(response, response_len),
            input(credential_id, credential_id_len),
        ) {
            Ok(r) => {
                *out_finalization = to_buf(r.finalization);
                *out_session_key = to_buf(r.session_key);
                *out_export_key = to_buf(r.export_key);
                0
            }
            Err(e) => code(e),
        }
    }
}
