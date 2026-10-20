# opaque-bridge

The OPAQUE (RFC 9807) client used by Cloud Backup. It is the same Rust crate the Windows and Android
apps use (and the Cloud Backup server runs), so every side agrees on the ciphersuite and the Argon2id
stretching parameters. The app talks to it through the C ABI in `include/opaque_bridge.h`, bound for Vala
in `vapi/opaque-bridge.vapi`.

**License:** dual licensed, `GPL-3.0-or-later OR LicenseRef-Mauborgne-Commercial`. See `LICENSE.md`. The rest of
the repository is `GPL-3.0-or-later`.

## Building

`meson.build` builds the crate when `cargo` is available (`cargo build --release --offline
--no-default-features --features client`) and links the static library. Without cargo the app still builds,
and Cloud Backup reports that it is unavailable.

The Flatpak has no network while building, so the crates are vendored through `cargo-sources.json`. Regenerate
it whenever `Cargo.lock` changes, with
[flatpak-cargo-generator](https://github.com/flatpak/flatpak-builder-tools/tree/master/cargo):

```bash
python3 flatpak-cargo-generator.py subprojects/opaque-bridge/Cargo.lock -o subprojects/opaque-bridge/cargo-sources.json
```

The manifest uses the `org.freedesktop.Sdk.Extension.rust-stable` extension of the runtime's freedesktop
base (GNOME 51 is on 26.08).

## Tests

The crate's own tests include the server half of the protocol, so they cover a full registration and login:

```bash
cargo test --features server
```
