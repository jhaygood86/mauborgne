/**
 * Talks to the Cloud Backup Worker (protocol: worker/README.md in the Windows/Android repo).
 *
 * The cloud password is only ever used on this device: the server holds an OPAQUE record, a vault
 * encrypted with a random per-backup key, and that key wrapped under a secret derived from the password.
 * A port of CloudBackupService.cs.
 */
public class CloudBackupService : Object {

    public const string DEFAULT_URL = "https://mauborgne-backup.peachstatetechnologies.com";

    private const int MAX_SYNC_ATTEMPTS = 4;

    private Soup.Session http;
    private OpaqueProtocol opaque;
    private LicenseProvider licenses;
    private string base_url;

    public CloudBackupService (OpaqueProtocol opaque, LicenseProvider licenses, string? base_url = null) {
        this.opaque = opaque;
        this.licenses = licenses;
        this.http = new Soup.Session () {
            user_agent = "Mauborgne/%s".printf (VERSION)
        };

        var url = base_url ?? Environment.get_variable ("MAUBORGNE_CLOUD_URL");
        var resolved = url == null || url.strip () == "" ? DEFAULT_URL : url.strip ();

        while (resolved.has_suffix ("/")) {
            resolved = resolved.substring (0, resolved.length - 1);
        }

        this.base_url = resolved;
    }

    // ---- public operations ---------------------------------------------------------------

    public async CloudBackupStatus get_status () throws Error {
        var license = yield require_license ();

        return yield fetch_status (license);
    }

    /** Encrypts the snapshot with a new key and uploads it. Registers the password on first use. */
    public async CloudBackupInfo back_up (string password, SyncSnapshot snapshot) throws Error {
        var license = yield require_license ();

        var status = yield fetch_status (license);

        if (!status.registered) {
            var registered = yield register (license, password, null, null);
            Mauborgne.CloudCrypto.zero (registered.export_key);
        }

        var login = yield log_in (license, password);
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (login.export_key);
        var backup_key = Mauborgne.CloudCrypto.new_backup_key ();

        try {
            var backup_id = Mauborgne.CloudCrypto.new_backup_id ();
            var vault = yield encrypt_vault (snapshot.to_content (), Mauborgne.CloudCrypto.aegis_password (backup_key));
            var wrapped = Mauborgne.CloudCrypto.wrap (wrap_key, backup_key, Mauborgne.CloudCrypto.hash_vault (vault), login.credential_id, backup_id);

            yield upload (license, login.session, backup_id, status.backup_id, vault, wrapped);

            return new CloudBackupInfo (backup_id, new DateTime.now_utc ().to_unix ());
        } finally {
            Mauborgne.CloudCrypto.zero (wrap_key);
            Mauborgne.CloudCrypto.zero (backup_key);
            Mauborgne.CloudCrypto.zero (login.export_key);
        }
    }

    public async CloudRestoreResult restore (string password) throws Error {
        var license = yield require_license ();
        var status = yield fetch_status (license);

        if (!status.registered) {
            throw new CloudBackupError.NOT_REGISTERED ("No cloud password registered");
        }

        if (!status.backup_exists) {
            throw new CloudBackupError.NO_BACKUP ("No backup stored");
        }

        var login = yield log_in (license, password);
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (login.export_key);
        Mauborgne.CloudCrypto.UnwrappedKey? unwrapped = null;

        try {
            var download = yield download_backup (license, login.session);
            unwrapped = unwrap_download (wrap_key, download, login.credential_id);

            var content = yield decrypt_vault (download.vault, Mauborgne.CloudCrypto.aegis_password (unwrapped.backup_key));

            if (content == null) {
                throw new CloudBackupError.TAMPERED ("The backup could not be decrypted");
            }

            return new CloudRestoreResult (SyncSnapshot.from_content (content), download.backup_id, download.updated_at);
        } finally {
            Mauborgne.CloudCrypto.zero (wrap_key);
            Mauborgne.CloudCrypto.zero (login.export_key);

            if (unwrapped != null) {
                Mauborgne.CloudCrypto.zero (unwrapped.backup_key);
            }
        }
    }

    /**
     * Automatic sync. Reads the cloud status; if nothing changed anywhere (known_backup_id is current
     * and local_changed is false) returns without a login. Otherwise logs in, downloads the current
     * vault, asks reconcile for the merged result and uploads it if the plan says so. An upload built
     * on a stale backup is refused by the server; the vault is then downloaded again and reconciled.
     */
    public async CloudSyncResult sync (string password, string? known_backup_id, bool local_changed, ReconcileFunc reconcile) throws Error {
        var license = yield require_license ();
        var status = yield fetch_status (license);

        if (!status.registered) {
            throw new CloudBackupError.NOT_REGISTERED ("No cloud password registered");
        }

        if (status.backup_id == known_backup_id && !local_changed) {
            return new CloudSyncResult (status.backup_id, status.updated_at, false, false);
        }

        var login = yield log_in (license, password);
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (login.export_key);

        try {
            for (int attempt = 0; attempt < MAX_SYNC_ATTEMPTS; attempt++) {
                SyncSnapshot? remote = null;
                string? remote_id = null;
                int64 remote_at = 0;

                if (status.backup_exists) {
                    var download = yield download_backup (license, login.session);
                    var unwrapped = unwrap_download (wrap_key, download, login.credential_id);

                    try {
                        var content = yield decrypt_vault (download.vault, Mauborgne.CloudCrypto.aegis_password (unwrapped.backup_key));

                        if (content == null) {
                            throw new CloudBackupError.TAMPERED ("The backup could not be decrypted");
                        }

                        remote = SyncSnapshot.from_content (content);
                    } finally {
                        Mauborgne.CloudCrypto.zero (unwrapped.backup_key);
                    }

                    remote_id = download.backup_id;
                    remote_at = download.updated_at;
                }

                var plan = reconcile (remote);

                if (!plan.upload) {
                    return new CloudSyncResult (remote_id, remote_at, true, false);
                }

                var backup_key = Mauborgne.CloudCrypto.new_backup_key ();

                try {
                    var backup_id = Mauborgne.CloudCrypto.new_backup_id ();
                    var vault = yield encrypt_vault (plan.merged.to_content (), Mauborgne.CloudCrypto.aegis_password (backup_key));
                    var wrapped = Mauborgne.CloudCrypto.wrap (wrap_key, backup_key, Mauborgne.CloudCrypto.hash_vault (vault), login.credential_id, backup_id);

                    try {
                        yield upload (license, login.session, backup_id, remote_id, vault, wrapped);
                    } catch (CloudBackupError.CONFLICT e) {
                        // Another device got there first: look at what is current now and merge again.
                        status = yield fetch_status (license);
                        continue;
                    }

                    return new CloudSyncResult (backup_id, new DateTime.now_utc ().to_unix (), true, true);
                } finally {
                    Mauborgne.CloudCrypto.zero (backup_key);
                }
            }

            throw new CloudBackupError.CONFLICT ("Too many conflicting uploads");
        } finally {
            Mauborgne.CloudCrypto.zero (wrap_key);
            Mauborgne.CloudCrypto.zero (login.export_key);
        }
    }

    /** Re-wraps the current backup key under the new password. Needs the old password. */
    public async void change_password (string old_password, string new_password) throws Error {
        var license = yield require_license ();
        var status = yield fetch_status (license);

        if (!status.registered) {
            throw new CloudBackupError.NOT_REGISTERED ("No cloud password registered");
        }

        var login = yield log_in (license, old_password);
        var old_wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (login.export_key);
        Mauborgne.CloudCrypto.UnwrappedKey? unwrapped = null;
        uint8[]? new_wrap_key = null;

        try {
            // Unwrap while the old password still works: registering replaces the record.
            Download? download = null;

            if (status.backup_exists) {
                download = yield download_backup (license, login.session);
                unwrapped = unwrap_download (old_wrap_key, download, login.credential_id);
            }

            // The record and the re-wrapped key travel in one request, so the server switches both at once.
            var registered = yield register (license, new_password, login.session, (new_export_key) => {
                if (unwrapped == null || download == null) {
                    return null;
                }

                new_wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (new_export_key);

                return Base64.encode (Mauborgne.CloudCrypto.wrap (
                    new_wrap_key, unwrapped.backup_key, unwrapped.vault_hash, login.credential_id, download.backup_id));
            });

            Mauborgne.CloudCrypto.zero (registered.export_key);
        } finally {
            Mauborgne.CloudCrypto.zero (old_wrap_key);
            Mauborgne.CloudCrypto.zero (login.export_key);
            Mauborgne.CloudCrypto.zero (new_wrap_key);

            if (unwrapped != null) {
                Mauborgne.CloudCrypto.zero (unwrapped.backup_key);
            }
        }
    }

    /** Deletes the account and every stored backup. */
    public async void delete_backup (string password) throws Error {
        var license = yield require_license ();
        var status = yield fetch_status (license);

        if (!status.registered) {
            throw new CloudBackupError.NOT_REGISTERED ("No cloud password registered");
        }

        var login = yield log_in (license, password);
        Mauborgne.CloudCrypto.zero (login.export_key);

        yield send ("DELETE", "/v1/backup", license, login.session, null);
    }

    // ---- OPAQUE flows --------------------------------------------------------------------

    private class LoginResult : Object {
        public string session;
        public uint8[] export_key;
        public string credential_id;
    }

    private async LoginResult log_in (string license, string passphrase) throws Error {
        var password = Mauborgne.CloudCrypto.password_bytes (passphrase);

        try {
            OpaqueStart? start = null;
            yield Mauborgne.Threads.run_blocking (() => { start = opaque.login_start (password); });

            var request = new Json.Object ();
            request.set_string_member ("request", Base64.encode (start.request));
            var started = (yield send ("POST", "/v1/opaque/login/start", license, null, request)).get_object ();

            var credential_id = string_member (started, "credentialId");
            var response = Base64.decode (string_member (started, "response"));

            OpaqueLoginFinish? finish = null;

            try {
                yield Mauborgne.Threads.run_blocking (() => {
                    finish = opaque.login_finish (password, start.state, response, credential_id.data);
                });
            } catch (OpaqueError e) {
                if (e is OpaqueError.UNAVAILABLE) {
                    throw new CloudBackupError.UNAVAILABLE (e.message);
                }

                // A wrong password fails here, before the server learns anything about the attempt.
                throw new CloudBackupError.WRONG_PASSWORD ("Wrong cloud password");
            }

            var finalize = new Json.Object ();
            finalize.set_string_member ("loginId", string_member (started, "loginId"));
            finalize.set_string_member ("finalization", Base64.encode (finish.finalization));
            var done = (yield send ("POST", "/v1/opaque/login/finish", license, null, finalize)).get_object ();

            Mauborgne.CloudCrypto.zero (finish.session_key);

            var result = new LoginResult ();
            result.session = string_member (done, "session");
            result.export_key = (owned) finish.export_key;
            result.credential_id = credential_id;

            return result;
        } finally {
            Mauborgne.CloudCrypto.zero (password);
        }
    }

    /** Given the new export key, returns the backup key re-wrapped under it (base64), or null. */
    private delegate string? RewrapFunc (uint8[] new_export_key);

    private async OpaqueRegistrationFinish register (string license, string passphrase, string? session, RewrapFunc? rewrap) throws Error {
        var password = Mauborgne.CloudCrypto.password_bytes (passphrase);

        try {
            OpaqueStart? start = null;
            yield Mauborgne.Threads.run_blocking (() => { start = opaque.registration_start (password); });

            var request = new Json.Object ();
            request.set_string_member ("request", Base64.encode (start.request));
            var started = (yield send ("POST", "/v1/opaque/register/start", license, session, request)).get_object ();

            var credential_id = string_member (started, "credentialId");
            var response = Base64.decode (string_member (started, "response"));

            OpaqueRegistrationFinish? finish = null;

            try {
                yield Mauborgne.Threads.run_blocking (() => {
                    finish = opaque.registration_finish (password, start.state, response, credential_id.data);
                });
            } catch (OpaqueError e) {
                if (e is OpaqueError.UNAVAILABLE) {
                    throw new CloudBackupError.UNAVAILABLE (e.message);
                }

                throw new CloudBackupError.SERVER ("Registration failed");
            }

            var wrapped_key = rewrap != null ? rewrap (finish.export_key) : null;

            var upload_body = new Json.Object ();
            upload_body.set_string_member ("upload", Base64.encode (finish.upload));

            if (wrapped_key != null) {
                upload_body.set_string_member ("wrappedKey", wrapped_key);
            }

            yield send ("POST", "/v1/opaque/register/finish", license, session, upload_body);

            return finish;
        } finally {
            Mauborgne.CloudCrypto.zero (password);
        }
    }

    // ---- vaults ---------------------------------------------------------------------------

    private async string encrypt_vault (AegisVaultContent content, string aegis_password) throws Error {
        string? vault = null;

        yield Mauborgne.Threads.run_blocking (() => {
            vault = AegisManager.create_encrypted_vault_json (content, aegis_password);
        });

        return vault;
    }

    /** Null when the vault cannot be opened with this key: it was altered, or is not ours. */
    private async AegisVaultContent? decrypt_vault (string vault_json, string aegis_password) throws Error {
        AegisVaultContent? content = null;

        yield Mauborgne.Threads.run_blocking (() => {
            var parser = new Json.Parser ();

            try {
                parser.load_from_data (vault_json);
            } catch (Error e) {
                return;
            }

            var vault = AegisManager.parse_vault (parser.get_root ());

            if (vault != null && vault.header != null && AegisManager.is_vault_encrypted (vault)) {
                content = AegisManager.unlock_vault (vault, aegis_password);
            }
        });

        return content;
    }

    // ---- helpers -------------------------------------------------------------------------

    private class Download : Object {
        public string backup_id;
        public string vault;
        public uint8[] wrapped_key;
        public int64 updated_at;
    }

    private async Download download_backup (string license, string session) throws Error {
        var json = (yield send ("GET", "/v1/backup", license, session, null)).get_object ();

        var download = new Download ();
        download.backup_id = string_member (json, "backupId");
        download.vault = string_member (json, "vault");
        download.wrapped_key = Base64.decode (string_member (json, "wrappedKey"));
        download.updated_at = parse_time (string_member (json, "updatedAt"));

        return download;
    }

    private async void upload (string license, string session, string backup_id, string? base_backup_id, string vault, uint8[] wrapped) throws Error {
        var body = new Json.Object ();
        body.set_string_member ("backupId", backup_id);

        if (base_backup_id != null) {
            body.set_string_member ("baseBackupId", base_backup_id);
        } else {
            body.set_null_member ("baseBackupId");
        }

        body.set_string_member ("vault", vault);
        body.set_string_member ("wrappedKey", Base64.encode (wrapped));

        yield send ("PUT", "/v1/backup", license, session, body);
    }

    /** Opens the wrapped key and checks the vault is the one that was wrapped. */
    private Mauborgne.CloudCrypto.UnwrappedKey unwrap_download (uint8[] wrap_key, Download download, string credential_id) throws CloudBackupError {
        var unwrapped = Mauborgne.CloudCrypto.unwrap (wrap_key, download.wrapped_key, credential_id, download.backup_id);

        if (unwrapped == null) {
            throw new CloudBackupError.TAMPERED ("The backup key could not be unwrapped");
        }

        if (!Mauborgne.CloudCrypto.fixed_time_equals (Mauborgne.CloudCrypto.hash_vault (download.vault), unwrapped.vault_hash)) {
            throw new CloudBackupError.TAMPERED ("The backup does not match its hash");
        }

        return unwrapped;
    }

    private async CloudBackupStatus fetch_status (string license) throws Error {
        var json = (yield send ("GET", "/v1/backup/status", license, null, null)).get_object ();

        var updated = json.has_member ("updatedAt") && !json.get_null_member ("updatedAt")
            ? parse_time (json.get_string_member ("updatedAt")) : 0;

        return new CloudBackupStatus (
            json.get_boolean_member ("registered"),
            json.get_boolean_member ("exists"),
            updated,
            string_member (json, "credentialId"),
            json.has_member ("backupId") && !json.get_null_member ("backupId") ? json.get_string_member ("backupId") : null);
    }

    private async string require_license () throws Error {
        var license = yield licenses.get_license ();

        if (license == null) {
            throw new CloudBackupError.LICENSE_INVALID ("No license");
        }

        return license;
    }

    private static string string_member (Json.Object object, string name) throws CloudBackupError {
        if (!object.has_member (name) || object.get_null_member (name)) {
            throw new CloudBackupError.SERVER ("The server response is missing %s", name);
        }

        return object.get_string_member (name);
    }

    /** The server sends ISO 8601; this keeps whole seconds. */
    private static int64 parse_time (string iso8601) {
        var time = new DateTime.from_iso8601 (iso8601, null);

        return time != null ? time.to_unix () : 0;
    }

    private async Json.Node send (string method, string path, string license, string? session, Json.Object? body) throws Error {
        var message = new Soup.Message (method, base_url + path);
        message.request_headers.append ("Authorization", "Bearer " + license);

        if (session != null) {
            message.request_headers.append ("X-Cloud-Session", session);
        }

        if (body != null) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (body);

            var generator = new Json.Generator ();
            generator.set_root (node);

            message.set_request_body_from_bytes ("application/json", new Bytes (generator.to_data (null).data));
        }

        Bytes response;

        try {
            response = yield http.send_and_read_async (message, Priority.DEFAULT, null);
        } catch (Error e) {
            throw new CloudBackupError.NETWORK ("%s", e.message);
        }

        var data = response.get_data ();
        var text = new StringBuilder.sized (data.length);
        text.append_len ((string) data, data.length);

        var status = (uint) message.status_code;

        if (status >= 200 && status < 300) {
            var parser = new Json.Parser ();

            try {
                parser.load_from_data (text.str);
            } catch (Error e) {
                throw new CloudBackupError.SERVER ("The server sent an unreadable response");
            }

            return parser.get_root ().copy ();
        }

        throw map_error (status, read_error_code (text.str));
    }

    private static string? read_error_code (string text) {
        var parser = new Json.Parser ();

        try {
            parser.load_from_data (text);
        } catch (Error e) {
            return null;
        }

        var root = parser.get_root ();

        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }

        var object = root.get_object ();

        return object.has_member ("error") && !object.get_null_member ("error") ? object.get_string_member ("error") : null;
    }

    private static Error map_error (uint status, string? code) {
        switch (code) {
            case "license_invalid":
                return new CloudBackupError.LICENSE_INVALID ("License rejected");
            case "license_expired":
                return new CloudBackupError.LICENSE_EXPIRED ("License expired");
            case "login_failed":
                return new CloudBackupError.WRONG_PASSWORD ("Wrong cloud password");
            case "too_many_attempts":
                return new CloudBackupError.TOO_MANY_ATTEMPTS ("Too many attempts");
            case "no_backup":
                return new CloudBackupError.NO_BACKUP ("No backup stored");
            case "not_registered":
                return new CloudBackupError.NOT_REGISTERED ("No cloud password registered");
            case "conflict":
                return new CloudBackupError.CONFLICT ("The backup changed on another device");
            default:
                if (status == 429) {
                    return new CloudBackupError.TOO_MANY_ATTEMPTS ("Too many attempts");
                }

                return new CloudBackupError.SERVER ("The server answered %u", status);
        }
    }
}
