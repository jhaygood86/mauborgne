/* SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial */
/* SPDX-FileCopyrightText: 2026 Justin Haygood <jhaygood86@gmail.com> */

/*
 * C ABI of the opaque-bridge client library (see opaque-bridge/src/ffi.rs).
 *
 * Every call returns 0 on success, 1 for a malformed input and 2 for a protocol
 * failure (a wrong password included). Outputs are written to caller-provided
 * OpaqueBuf slots and must be released with opaque_buf_free.
 */
#ifndef OPAQUE_BRIDGE_H
#define OPAQUE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef struct OpaqueBuf {
    uint8_t *ptr;
    size_t len;
} OpaqueBuf;

void opaque_buf_free (OpaqueBuf buf);

int32_t opaque_client_registration_start (const uint8_t *password, size_t password_len,
                                          OpaqueBuf *out_request, OpaqueBuf *out_state);

int32_t opaque_client_registration_finish (const uint8_t *password, size_t password_len,
                                           const uint8_t *state, size_t state_len,
                                           const uint8_t *response, size_t response_len,
                                           const uint8_t *credential_id, size_t credential_id_len,
                                           OpaqueBuf *out_upload, OpaqueBuf *out_export_key);

int32_t opaque_client_login_start (const uint8_t *password, size_t password_len,
                                   OpaqueBuf *out_request, OpaqueBuf *out_state);

int32_t opaque_client_login_finish (const uint8_t *password, size_t password_len,
                                    const uint8_t *state, size_t state_len,
                                    const uint8_t *response, size_t response_len,
                                    const uint8_t *credential_id, size_t credential_id_len,
                                    OpaqueBuf *out_finalization, OpaqueBuf *out_session_key,
                                    OpaqueBuf *out_export_key);

#endif
