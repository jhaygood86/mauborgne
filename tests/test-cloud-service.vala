/*
 * The Cloud Backup service and the licence sign-in against an in-process fake of the server.
 * The fake speaks the same JSON as the Worker; its OPAQUE is a stand-in (see FakeOpaqueClient),
 * since the protocol itself lives in the Rust library.
 */
namespace CloudServiceTests {

    private const string LICENSE = "test-license";
    private const string PASSWORD = "correct horse battery";

    // ---- fakes ---------------------------------------------------------------------------

    /** Not OPAQUE: just enough structure to exercise the service, keyed by the password. */
    private class FakeOpaqueClient : Object, OpaqueProtocol {

        private static uint8[] digest (string label, uint8[] password) {
            var data = new ByteArray ();
            data.append (label.data);
            data.append (password);

            var result = new uint8[32];
            GCrypt.Hash.hash_buffer (GCrypt.Hash.Algorithm.SHA256, result, data.data);

            return result;
        }

        private static uint8[] export_key_for (uint8[] password) {
            var key = new ByteArray ();
            key.append (digest ("export-1", password));
            key.append (digest ("export-2", password));

            return key.data;
        }

        private static uint8[] record_for (uint8[] password) {
            return digest ("record", password);
        }

        public OpaqueStart registration_start (uint8[] password) throws OpaqueError {
            return new OpaqueStart ("registration-request".data, password);
        }

        public OpaqueRegistrationFinish registration_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
            return new OpaqueRegistrationFinish (record_for (password), export_key_for (password));
        }

        public OpaqueStart login_start (uint8[] password) throws OpaqueError {
            return new OpaqueStart ("login-request".data, password);
        }

        public OpaqueLoginFinish login_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
            // the "server response" is the stored record: a wrong password cannot open it
            if (AegisManager.bytes_to_hex (response) != AegisManager.bytes_to_hex (record_for (password))) {
                throw new OpaqueError.FAILED ("wrong password");
            }

            return new OpaqueLoginFinish ("finalization".data, new uint8[32], export_key_for (password));
        }
    }

    private class FixedLicense : Object, LicenseProvider {
        public string? license { get; set; default = LICENSE; }

        public async string? get_license () throws Error {
            return license;
        }
    }

    /** The Worker's API in memory. */
    private class FakeCloudServer : Object {
        public Soup.Server server;
        public string url;

        public string license = LICENSE;
        public string credential_id = "cred-test";
        public string session_token = "session-token";

        public bool registered = false;
        public string? record = null;

        public string? backup_id = null;
        public string? vault = null;
        public string? wrapped_key = null;
        public int64 updated_at = 0;

        /** Answer the next PUTs with a conflict this many times. */
        public int conflicts_to_inject = 0;

        /** Answer every call with this status and error, if set. */
        public uint forced_status = 0;
        public string? forced_error = null;

        public Gee.List<string> requests = new Gee.ArrayList<string> ();
        public Gee.List<string> upload_bases = new Gee.ArrayList<string> ();

        public FakeCloudServer () {
            server = new Soup.Server (null);
            server.add_handler (null, handle);

            try {
                server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
            } catch (Error e) {
                Test.message ("could not start the fake server: %s", e.message);
                Test.fail ();
            }

            url = server.get_uris ().data.to_string ();
        }

        public void stop () {
            server.disconnect ();
        }

        public bool saw (string fragment) {
            foreach (var request in requests) {
                if (request.contains (fragment)) {
                    return true;
                }
            }

            return false;
        }

        private void reply (Soup.ServerMessage message, uint status, string json) {
            message.set_status (status, null);
            message.set_response ("application/json", Soup.MemoryUse.COPY, json.data);
        }

        private void fail (Soup.ServerMessage message, uint status, string code) {
            reply (message, status, "{\"error\":\"%s\"}".printf (code));
        }

        private Json.Object read_body (Soup.ServerMessage message) {
            var body = message.get_request_body ();
            var text = new StringBuilder.sized ((size_t) body.length);
            text.append_len ((string) body.data, (ssize_t) body.length);

            var parser = new Json.Parser ();

            try {
                parser.load_from_data (text.str);

                if (parser.get_root () != null && parser.get_root ().get_node_type () == Json.NodeType.OBJECT) {
                    return parser.get_root ().get_object ();
                }
            } catch (Error e) {
            }

            return new Json.Object ();
        }

        private bool has_session (Soup.ServerMessage message) {
            return message.get_request_headers ().get_one ("X-Cloud-Session") == session_token;
        }

        private void handle (Soup.Server server, Soup.ServerMessage message, string path, HashTable<string, string>? query) {
            var route = message.get_method () + " " + path;
            requests.add (route);

            if (forced_status != 0) {
                fail (message, forced_status, forced_error ?? "internal");
                return;
            }

            if (message.get_request_headers ().get_one ("Authorization") != "Bearer " + license) {
                fail (message, 401, "license_invalid");
                return;
            }

            var body = read_body (message);

            switch (route) {
                case "GET /v1/backup/status":
                    var status = new Json.Object ();
                    status.set_boolean_member ("registered", registered);
                    status.set_boolean_member ("exists", backup_id != null);

                    if (backup_id != null) {
                        status.set_string_member ("backupId", backup_id);
                        status.set_string_member ("updatedAt", new DateTime.from_unix_utc (updated_at).format_iso8601 ());
                    } else {
                        status.set_null_member ("backupId");
                        status.set_null_member ("updatedAt");
                    }

                    status.set_string_member ("credentialId", credential_id);
                    reply (message, 200, to_json (status));
                    break;
                case "POST /v1/opaque/register/start":
                    if (registered && !has_session (message)) {
                        fail (message, 401, "session_required");
                        break;
                    }

                    var started = new Json.Object ();
                    started.set_string_member ("response", Base64.encode ("registration-response".data));
                    started.set_string_member ("credentialId", credential_id);
                    reply (message, 200, to_json (started));
                    break;
                case "POST /v1/opaque/register/finish":
                    if (registered && !has_session (message)) {
                        fail (message, 401, "session_required");
                        break;
                    }

                    record = body.get_string_member ("upload");
                    registered = true;

                    // a password change replaces the record and the wrapped key together
                    if (body.has_member ("wrappedKey") && !body.get_null_member ("wrappedKey")) {
                        wrapped_key = body.get_string_member ("wrappedKey");
                    }

                    reply (message, 200, "{\"ok\":true}");
                    break;
                case "POST /v1/opaque/login/start":
                    if (!registered) {
                        fail (message, 409, "not_registered");
                        break;
                    }

                    var login = new Json.Object ();
                    login.set_string_member ("loginId", "login-1");
                    login.set_string_member ("response", record);
                    login.set_string_member ("credentialId", credential_id);
                    reply (message, 200, to_json (login));
                    break;
                case "POST /v1/opaque/login/finish":
                    var done = new Json.Object ();
                    done.set_string_member ("session", session_token);
                    done.set_int_member ("expiresAt", new DateTime.now_utc ().to_unix () + 300);
                    reply (message, 200, to_json (done));
                    break;
                case "PUT /v1/backup":
                    if (!has_session (message)) {
                        fail (message, 401, "session_required");
                        break;
                    }

                    var base_id = body.has_member ("baseBackupId") && !body.get_null_member ("baseBackupId")
                        ? body.get_string_member ("baseBackupId") : null;
                    upload_bases.add (base_id ?? "(none)");

                    if (conflicts_to_inject > 0 || base_id != backup_id) {
                        conflicts_to_inject = int.max (conflicts_to_inject - 1, 0);
                        fail (message, 409, "conflict");
                        break;
                    }

                    backup_id = body.get_string_member ("backupId");
                    vault = body.get_string_member ("vault");
                    wrapped_key = body.get_string_member ("wrappedKey");
                    updated_at = new DateTime.now_utc ().to_unix ();
                    reply (message, 200, "{\"ok\":true}");
                    break;
                case "GET /v1/backup":
                    if (!has_session (message)) {
                        fail (message, 401, "session_required");
                        break;
                    }

                    if (backup_id == null) {
                        fail (message, 404, "no_backup");
                        break;
                    }

                    var download = new Json.Object ();
                    download.set_string_member ("backupId", backup_id);
                    download.set_string_member ("vault", vault);
                    download.set_string_member ("wrappedKey", wrapped_key);
                    download.set_string_member ("updatedAt", new DateTime.from_unix_utc (updated_at).format_iso8601 ());
                    reply (message, 200, to_json (download));
                    break;
                case "DELETE /v1/backup":
                    if (!has_session (message)) {
                        fail (message, 401, "session_required");
                        break;
                    }

                    registered = false;
                    record = null;
                    backup_id = null;
                    vault = null;
                    wrapped_key = null;
                    reply (message, 200, "{\"ok\":true}");
                    break;
                default:
                    fail (message, 404, "not_found");
                    break;
            }
        }

        private static string to_json (Json.Object object) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (object);

            var generator = new Json.Generator ();
            generator.set_root (node);

            return generator.to_data (null);
        }
    }

    // ---- helpers -------------------------------------------------------------------------

    [CCode (has_target = false)]
    private delegate void Starter (AsyncReadyCallback callback);

    // test functions cannot carry a closure, so the async tests are looked up by their path
    private class StarterBox : Object {
        public Starter start;
    }

    private Gee.Map<string, StarterBox>? starters = null;

    private void add_async (string path, Starter starter) {
        if (starters == null) {
            starters = new Gee.HashMap<string, StarterBox> ();
        }

        var box = new StarterBox ();
        box.start = starter;
        starters[path] = box;
        Test.add_func (path, run_current_async);
    }

    private void run_current_async () {
        var waiter = new TestSupport.Waiter ();

        var box = starters[Test.get_path ()];

        box.start ((obj, res) => {
            waiter.done ();
        });

        waiter.wait ();
    }

    private CloudBackupService service_for (FakeCloudServer server, FixedLicense? license = null) {
        return new CloudBackupService (new FakeOpaqueClient (), license ?? new FixedLicense (), server.url);
    }

    private SyncPad sync_pad (string issuer, string account, int64 modified, string secret, OneTimePadType type = OneTimePadType.TOTP, int64 counter = 0) {
        var pad = TestSupport.make_pad (type, issuer, account);
        pad.modified_at = modified;
        pad.counter = counter;

        return new SyncPad (pad, secret);
    }

    private SyncSnapshot sample_snapshot () {
        var snapshot = new SyncSnapshot ();
        snapshot.pads.add (sync_pad ("Example", "alice@example.com", 1700000000000, TestSupport.SHA1_SECRET));
        snapshot.pads.add (sync_pad ("Acme", "bob", 1700000001000, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", OneTimePadType.HOTP, 4));
        snapshot.deleted["Gone:account"] = 1799999999000;

        return snapshot;
    }

    private bool is_error (Error? error, int code) {
        return error != null && error.domain == Quark.from_string ("cloud-backup-error-quark") && error.code == code;
    }

    private void expect (Error? error, int code) {
        if (error == null || !(error is CloudBackupError) || error.code != code) {
            Test.message ("unexpected result: %s", error == null ? "no error" : error.message);
            Test.fail ();
        }

        assert_true (error != null && error.code == code);
    }

    // ---- registration --------------------------------------------------------------------

    public void register () {
        add_async ("/cloud/service_status_of_a_new_account", (cb) => test_status_new.begin (cb));
        add_async ("/cloud/service_no_license", (cb) => test_no_license.begin (cb));
        add_async ("/cloud/service_license_rejected", (cb) => test_license_rejected.begin (cb));
        add_async ("/cloud/service_error_mapping", (cb) => test_error_mapping.begin (cb));
        add_async ("/cloud/service_network_failure", (cb) => test_network_failure.begin (cb));
        add_async ("/cloud/service_back_up_and_restore", (cb) => test_back_up_and_restore.begin (cb));
        add_async ("/cloud/service_server_never_sees_secrets", (cb) => test_server_sees_nothing.begin (cb));
        add_async ("/cloud/service_second_backup_replaces_first", (cb) => test_second_backup.begin (cb));
        add_async ("/cloud/service_restore_wrong_password", (cb) => test_restore_wrong_password.begin (cb));
        add_async ("/cloud/service_restore_without_backup", (cb) => test_restore_without_backup.begin (cb));
        add_async ("/cloud/service_restore_tampered_vault", (cb) => test_restore_tampered_vault.begin (cb));
        add_async ("/cloud/service_restore_tampered_key", (cb) => test_restore_tampered_key.begin (cb));
        add_async ("/cloud/service_restore_moved_blob", (cb) => test_restore_moved_blob.begin (cb));
        add_async ("/cloud/service_change_password", (cb) => test_change_password.begin (cb));
        add_async ("/cloud/service_change_password_wrong_old", (cb) => test_change_password_wrong_old.begin (cb));
        add_async ("/cloud/service_delete", (cb) => test_delete.begin (cb));
        add_async ("/cloud/service_delete_wrong_password", (cb) => test_delete_wrong_password.begin (cb));
        add_async ("/cloud/service_sync_nothing_changed", (cb) => test_sync_unchanged.begin (cb));
        add_async ("/cloud/service_sync_uploads_to_empty_cloud", (cb) => test_sync_first_upload.begin (cb));
        add_async ("/cloud/service_sync_merges_remote_changes", (cb) => test_sync_merge.begin (cb));
        add_async ("/cloud/service_sync_no_upload_when_equal", (cb) => test_sync_equal.begin (cb));
        add_async ("/cloud/service_sync_retries_after_conflict", (cb) => test_sync_conflict_retry.begin (cb));
        add_async ("/cloud/service_sync_gives_up_after_conflicts", (cb) => test_sync_conflict_forever.begin (cb));
        add_async ("/cloud/service_sync_requires_registration", (cb) => test_sync_unregistered.begin (cb));
        add_async ("/cloud/license_sign_in", (cb) => test_license_sign_in.begin (cb));
        add_async ("/cloud/license_sign_in_state_mismatch", (cb) => test_sign_in_state_mismatch.begin (cb));
        add_async ("/cloud/license_sign_in_declined", (cb) => test_sign_in_declined.begin (cb));
        add_async ("/cloud/license_sign_in_no_subscription", (cb) => test_sign_in_no_entitlement.begin (cb));
        add_async ("/cloud/license_sign_in_cancelled", (cb) => test_sign_in_cancelled.begin (cb));
        add_async ("/cloud/license_unreadable_is_cleared", (cb) => test_license_unreadable.begin (cb));
        add_async ("/cloud/license_fresh_is_not_renewed", (cb) => test_license_fresh.begin (cb));
        add_async ("/cloud/license_renewed_when_due", (cb) => test_license_renewed.begin (cb));
        add_async ("/cloud/license_revoked_on_renewal", (cb) => test_license_revoked.begin (cb));
        add_async ("/cloud/license_renewal_not_hammered", (cb) => test_license_renewal_throttled.begin (cb));
        add_async ("/cloud/license_expired_kept_when_offline", (cb) => test_license_expired_offline.begin (cb));
    }

    private async void test_status_new () {
        var server = new FakeCloudServer ();

        try {
            var status = yield service_for (server).get_status ();

            assert_false (status.registered);
            assert_false (status.backup_exists);
            assert_null (status.backup_id);
            assert_cmpstr (status.credential_id, CompareOperator.EQ, "cred-test");
            assert_cmpint ((int) status.updated_at, CompareOperator.EQ, 0);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_no_license () {
        var server = new FakeCloudServer ();
        var provider = new FixedLicense ();
        provider.license = null;

        try {
            yield service_for (server, provider).get_status ();
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.LICENSE_INVALID);
        }

        // nothing was sent without a licence
        assert_cmpint (server.requests.size, CompareOperator.EQ, 0);
        server.stop ();
    }

    private async void test_license_rejected () {
        var server = new FakeCloudServer ();
        server.license = "a-different-license";

        try {
            yield service_for (server).get_status ();
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.LICENSE_INVALID);
            assert_true (Mauborgne.CloudBackupErrors.should_offer_signup (e));
        }

        server.stop ();
    }

    private async void test_error_mapping () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        string[,] cases = {
            { "401", "license_expired" },
            { "401", "login_failed" },
            { "429", "too_many_attempts" },
            { "429", "something_else" },
            { "409", "not_registered" },
            { "404", "no_backup" },
            { "409", "conflict" },
            { "500", "internal" },
            { "413", "too_large" }
        };

        int[] expected = {
            CloudBackupError.LICENSE_EXPIRED,
            CloudBackupError.WRONG_PASSWORD,
            CloudBackupError.TOO_MANY_ATTEMPTS,
            CloudBackupError.TOO_MANY_ATTEMPTS,
            CloudBackupError.NOT_REGISTERED,
            CloudBackupError.NO_BACKUP,
            CloudBackupError.CONFLICT,
            CloudBackupError.SERVER,
            CloudBackupError.SERVER
        };

        for (int i = 0; i < expected.length; i++) {
            server.forced_status = uint.parse (cases[i, 0]);
            server.forced_error = cases[i, 1];

            try {
                yield service.get_status ();
                Test.fail ();
            } catch (Error e) {
                expect (e, expected[i]);
            }
        }

        server.stop ();
    }

    private async void test_network_failure () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        server.stop ();

        try {
            yield service.get_status ();
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.NETWORK);
        }
    }

    // ---- back up, restore ----------------------------------------------------------------

    private async void test_back_up_and_restore () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var original = sample_snapshot ();

        try {
            var info = yield service.back_up (PASSWORD, original);

            assert_cmpint (info.backup_id.length, CompareOperator.EQ, 22);
            assert_cmpstr (server.backup_id, CompareOperator.EQ, info.backup_id);

            var status = yield service.get_status ();
            assert_true (status.registered);
            assert_true (status.backup_exists);
            assert_cmpstr (status.backup_id, CompareOperator.EQ, info.backup_id);

            var restored = yield service.restore (PASSWORD);

            assert_cmpstr (restored.backup_id, CompareOperator.EQ, info.backup_id);
            assert_true (original.equivalent_to (restored.snapshot));
            assert_cmpint ((int) restored.updated_at, CompareOperator.EQ, (int) server.updated_at);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_server_sees_nothing () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        // what the server stores: an Aegis vault whose password it never receives
        assert_false (server.vault.contains (TestSupport.SHA1_SECRET));
        assert_false (server.vault.contains ("alice@example.com"));
        assert_false (server.vault.contains ("Example"));
        assert_false (server.wrapped_key.contains (PASSWORD));

        var parser = new Json.Parser ();

        try {
            parser.load_from_data (server.vault);
        } catch (Error e) {
            Test.fail ();
        }

        var root = parser.get_root ().get_object ();
        assert_cmpint ((int) root.get_int_member ("version"), CompareOperator.EQ, 1);
        assert_cmpint ((int) root.get_object_member ("header").get_array_member ("slots").get_length (), CompareOperator.EQ, 1);

        // the cloud password is not what protects the vault: the random backup key is
        var vault = AegisManager.parse_vault (parser.get_root ());
        Test.expect_message (null, LogLevelFlags.LEVEL_CRITICAL, "*");
        assert_null (AegisManager.unlock_vault (vault, PASSWORD));
        Test.assert_expected_messages ();

        // wrapped key: nonce + tag + backup key + vault hash
        assert_cmpint (Base64.decode (server.wrapped_key).length, CompareOperator.EQ, 92);

        server.stop ();
    }

    private async void test_second_backup () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            var first = yield service.back_up (PASSWORD, sample_snapshot ());

            var smaller = new SyncSnapshot ();
            smaller.pads.add (sync_pad ("Only", "one", 5, TestSupport.SHA1_SECRET));
            var second = yield service.back_up (PASSWORD, smaller);

            assert_cmpstr (first.backup_id, CompareOperator.NE, second.backup_id);
            assert_cmpstr (server.upload_bases[0], CompareOperator.EQ, "(none)");
            // the second upload names the backup it replaces
            assert_cmpstr (server.upload_bases[1], CompareOperator.EQ, first.backup_id);

            var restored = yield service.restore (PASSWORD);
            assert_cmpint (restored.snapshot.pads.size, CompareOperator.EQ, 1);
            assert_cmpstr (restored.backup_id, CompareOperator.EQ, second.backup_id);

            // the account was registered once
            var registrations = 0;

            foreach (var request in server.requests) {
                if (request == "POST /v1/opaque/register/finish") {
                    registrations++;
                }
            }

            assert_cmpint (registrations, CompareOperator.EQ, 1);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_restore_wrong_password () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
            yield service.restore ("not the password");
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.WRONG_PASSWORD);
        }

        // it failed on the device, before the server was asked to finish the login
        assert_false (server.saw ("login/finish") && server.requests[server.requests.size - 1] == "POST /v1/opaque/login/finish");
        server.stop ();
    }

    private async void test_restore_without_backup () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.NOT_REGISTERED);
        }

        // registered, but nothing uploaded
        server.registered = true;
        server.record = Base64.encode ("x".data);

        try {
            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.NO_BACKUP);
        }

        server.stop ();
    }

    private async void test_restore_tampered_vault () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());

            // any change to the vault breaks the hash that was wrapped with the key
            server.vault = server.vault.replace ("\"db\"", "\"db\" ");
            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.TAMPERED);
        }

        server.stop ();
    }

    private async void test_restore_tampered_key () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());

            var blob = Base64.decode (server.wrapped_key);
            blob[40] ^= 1;
            server.wrapped_key = Base64.encode (blob);

            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.TAMPERED);
        }

        server.stop ();
    }

    // a genuine backup presented under another id (the replay of an older blob, say)
    private async void test_restore_moved_blob () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
            server.backup_id = "AAAAAAAAAAAAAAAAAAAAAA";

            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.TAMPERED);
        }

        server.stop ();
    }

    // ---- change and delete ---------------------------------------------------------------

    private async void test_change_password () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var original = sample_snapshot ();

        try {
            var info = yield service.back_up (PASSWORD, original);
            yield service.change_password (PASSWORD, "an entirely new password");

            // same backup, still intact, now under the new password only
            var restored = yield service.restore ("an entirely new password");
            assert_cmpstr (restored.backup_id, CompareOperator.EQ, info.backup_id);
            assert_true (original.equivalent_to (restored.snapshot));
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        try {
            yield service.restore (PASSWORD);
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.WRONG_PASSWORD);
        }

        server.stop ();
    }

    private async void test_change_password_wrong_old () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
            yield service.change_password ("not the password", "an entirely new password");
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.WRONG_PASSWORD);
        }

        // nothing changed: the old password still works
        try {
            var restored = yield service.restore (PASSWORD);
            assert_cmpint (restored.snapshot.pads.size, CompareOperator.EQ, 2);
        } catch (Error e) {
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_delete () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
            yield service.delete_backup (PASSWORD);

            var status = yield service.get_status ();
            assert_false (status.registered);
            assert_false (status.backup_exists);
            assert_null (server.vault);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_delete_wrong_password () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.back_up (PASSWORD, sample_snapshot ());
            yield service.delete_backup ("not the password");
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.WRONG_PASSWORD);
        }

        assert_nonnull (server.vault);
        server.stop ();
    }

    // ---- sync ----------------------------------------------------------------------------

    private async void test_sync_unchanged () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var calls = 0;

        try {
            var info = yield service.back_up (PASSWORD, sample_snapshot ());
            server.requests.clear ();

            var result = yield service.sync (PASSWORD, info.backup_id, false, (remote) => {
                calls++;
                return new CloudSyncPlan (new SyncSnapshot (), false);
            });

            // nothing changed anywhere: no login, no download
            assert_false (result.reconciled);
            assert_false (result.uploaded);
            assert_cmpstr (result.backup_id, CompareOperator.EQ, info.backup_id);
            assert_cmpint (calls, CompareOperator.EQ, 0);
            assert_cmpint (server.requests.size, CompareOperator.EQ, 1);
            assert_cmpstr (server.requests[0], CompareOperator.EQ, "GET /v1/backup/status");
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_sync_first_upload () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var local = sample_snapshot ();

        // an account that only has a password so far
        server.registered = true;
        server.record = Base64.encode (hex_record (PASSWORD));

        SyncSnapshot? seen = null;

        try {
            var result = yield service.sync (PASSWORD, null, true, (remote) => {
                seen = remote;
                return new CloudSyncPlan (local, true);
            });

            assert_null (seen);
            assert_true (result.reconciled);
            assert_true (result.uploaded);
            assert_nonnull (server.backup_id);

            var restored = yield service.restore (PASSWORD);
            assert_true (local.equivalent_to (restored.snapshot));
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private uint8[] hex_record (string password) {
        var client = new FakeOpaqueClient ();

        try {
            return client.registration_finish (Mauborgne.CloudCrypto.password_bytes (password), new uint8[0], new uint8[0], new uint8[0]).upload;
        } catch (Error e) {
            Test.fail ();
            return new uint8[0];
        }
    }

    private async void test_sync_merge () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        var other_device = new SyncSnapshot ();
        other_device.pads.add (sync_pad ("Remote", "only", 100, TestSupport.SHA1_SECRET));
        other_device.pads.add (sync_pad ("Shared", "pad", 100, TestSupport.SHA1_SECRET));

        var this_device = new SyncSnapshot ();
        this_device.pads.add (sync_pad ("Local", "only", 100, TestSupport.SHA1_SECRET));
        var shared = sync_pad ("Shared", "pad", 200, TestSupport.SHA1_SECRET);
        shared.pad.note = "edited here";
        this_device.pads.add (shared);

        SyncSnapshot? merged = null;

        try {
            var info = yield service.back_up (PASSWORD, other_device);

            var result = yield service.sync (PASSWORD, info.backup_id, true, (remote) => {
                merged = Mauborgne.SyncMerge.merge (this_device, remote, 1800000000000);
                return new CloudSyncPlan (merged, !merged.equivalent_to (remote));
            });

            assert_true (result.reconciled);
            assert_true (result.uploaded);
            assert_cmpint (merged.pads.size, CompareOperator.EQ, 3);

            // the cloud now has everything, including the newer edit
            var restored = yield service.restore (PASSWORD);
            assert_true (merged.equivalent_to (restored.snapshot));

            foreach (var one in restored.snapshot.pads) {
                if (one.pad.identity == "Shared:pad") {
                    assert_cmpstr (one.pad.note, CompareOperator.EQ, "edited here");
                }
            }
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_sync_equal () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var content = sample_snapshot ();

        try {
            var info = yield service.back_up (PASSWORD, content);
            var before = server.backup_id;

            var result = yield service.sync (PASSWORD, null, true, (remote) => {
                var merged = Mauborgne.SyncMerge.merge (content, remote, 1800000000000);
                return new CloudSyncPlan (merged, !merged.equivalent_to (remote));
            });

            // the cloud already had exactly this: nothing to upload
            assert_true (result.reconciled);
            assert_false (result.uploaded);
            assert_cmpstr (result.backup_id, CompareOperator.EQ, info.backup_id);
            assert_cmpstr (server.backup_id, CompareOperator.EQ, before);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_sync_conflict_retry () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var reconciles = 0;

        try {
            var info = yield service.back_up (PASSWORD, sample_snapshot ());
            server.conflicts_to_inject = 1;

            var result = yield service.sync (PASSWORD, info.backup_id, true, (remote) => {
                reconciles++;
                return new CloudSyncPlan (sample_snapshot (), true);
            });

            // the first upload was refused, so the cloud was read and merged again
            assert_cmpint (reconciles, CompareOperator.EQ, 2);
            assert_true (result.uploaded);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        server.stop ();
    }

    private async void test_sync_conflict_forever () {
        var server = new FakeCloudServer ();
        var service = service_for (server);
        var reconciles = 0;

        try {
            var info = yield service.back_up (PASSWORD, sample_snapshot ());
            server.conflicts_to_inject = 100;

            yield service.sync (PASSWORD, info.backup_id, true, (remote) => {
                reconciles++;
                return new CloudSyncPlan (sample_snapshot (), true);
            });

            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.CONFLICT);
            assert_cmpint (reconciles, CompareOperator.EQ, 4);
        }

        server.stop ();
    }

    private async void test_sync_unregistered () {
        var server = new FakeCloudServer ();
        var service = service_for (server);

        try {
            yield service.sync (PASSWORD, null, true, (remote) => new CloudSyncPlan (new SyncSnapshot (), false));
            Test.fail ();
        } catch (Error e) {
            expect (e, CloudBackupError.NOT_REGISTERED);
        }

        server.stop ();
    }

    // ---- licence sign-in -----------------------------------------------------------------

    private class MemoryLicenseStore : Object, LicenseStore {
        public string? license = null;
        public int saves = 0;

        public string? load () {
            return license;
        }

        public void save (string license) {
            this.license = license;
            saves++;
        }

        public void clear () {
            license = null;
        }
    }

    /** Plays the Portal's authorization page: answers with whatever the test decides. */
    private class FakeBrowser : Object, AuthorizationBrowser {
        public string? code = "auth-code";
        public bool echo_state = true;
        public string? wrong_state = null;
        public string? error = null;
        public bool cancel = false;

        public string? authorize_url = null;
        public string? redirect = null;

        public async AuthorizationCallback authorize (BuildAuthorizeUrl build_url) throws Error {
            redirect = "http://127.0.0.1:50000/callback";
            authorize_url = build_url (redirect);

            if (cancel) {
                throw new LicenseSignInError.CANCELLED ("closed");
            }

            var query = Uri.parse (authorize_url, UriFlags.NONE).get_query ();
            var parameters = Uri.parse_params (query);

            return new AuthorizationCallback (code, echo_state ? parameters.lookup ("state") : wrong_state, error);
        }
    }

    /** The Portal's token endpoint and the CRM's renewal endpoint. */
    private class FakePortal : Object {
        public Soup.Server server;
        public string url;

        public string issued_token = "";
        public uint token_status = 200;
        public string token_error = "";
        public string? renewed_token = null;
        public uint renew_status = 200;

        public string? last_form = null;
        public int renewals = 0;

        public FakePortal () {
            server = new Soup.Server (null);
            server.add_handler (null, (srv, message, path, query) => {
                var body = message.get_request_body ();
                var text = new StringBuilder.sized ((size_t) body.length);
                text.append_len ((string) body.data, (ssize_t) body.length);

                if (path == "/oauth/token") {
                    last_form = text.str;
                    message.set_status (token_status, null);
                    message.set_response ("application/json", Soup.MemoryUse.COPY,
                        (token_status == 200
                            ? "{\"access_token\":\"%s\"}".printf (issued_token)
                            : "{\"error\":\"%s\"}".printf (token_error)).data);
                } else if (path == "/api/license/renew") {
                    renewals++;
                    message.set_status (renew_status, null);

                    if (renew_status == 200) {
                        message.set_response ("application/json", Soup.MemoryUse.COPY, "{\"token\":\"%s\"}".printf (renewed_token ?? "").data);
                    }
                } else {
                    message.set_status (404, null);
                }
            });

            try {
                server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
            } catch (Error e) {
                Test.fail ();
            }

            url = server.get_uris ().data.to_string ();
        }

        public void stop () {
            server.disconnect ();
        }
    }

    private string token (int64 expires_at, string contact = "contact-1") {
        var header = LicenseService.base64_url ("{\"alg\":\"RS256\"}".data);
        var claims = LicenseService.base64_url ("{\"exp\":%lld,\"contactId\":\"%s\"}".printf (expires_at, contact).data);

        return "%s.%s.%s".printf (header, claims, LicenseService.base64_url ("signature".data));
    }

    private int64 now () {
        return new DateTime.now_utc ().to_unix ();
    }

    private LicenseService license_service (FakePortal portal, AuthorizationBrowser browser, LicenseStore store) {
        Environment.set_variable ("MAUBORGNE_PORTAL_URL", portal.url, true);
        Environment.set_variable ("MAUBORGNE_API_URL", portal.url, true);

        return new LicenseService (browser, store);
    }

    private async void test_license_sign_in () {
        var portal = new FakePortal ();
        portal.issued_token = token (now () + 86400 * 90);
        var browser = new FakeBrowser ();
        var store = new MemoryLicenseStore ();
        var service = license_service (portal, browser, store);

        try {
            yield service.sign_in ();
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }

        // the licence was stored and is what the cloud calls will send
        assert_cmpstr (store.license, CompareOperator.EQ, portal.issued_token);
        assert_true (service.has_license ());

        // the authorization request carried PKCE, the app's client id and the loopback redirect
        var request = Uri.parse_params (Uri.parse (browser.authorize_url, UriFlags.NONE).get_query ());
        assert_cmpstr (request.lookup ("response_type"), CompareOperator.EQ, "code");
        assert_cmpstr (request.lookup ("client_id"), CompareOperator.EQ, LicenseService.client_id ());
        assert_cmpstr (request.lookup ("redirect_uri"), CompareOperator.EQ, browser.redirect);
        assert_cmpstr (request.lookup ("code_challenge_method"), CompareOperator.EQ, "S256");
        assert_true (browser.authorize_url.has_prefix (portal.url + "oauth/authorize?"));

        // the code was redeemed with the verifier that belongs to the challenge
        var form = Soup.Form.decode (portal.last_form);
        assert_cmpstr (form.lookup ("grant_type"), CompareOperator.EQ, "authorization_code");
        assert_cmpstr (form.lookup ("code"), CompareOperator.EQ, "auth-code");
        assert_cmpstr (form.lookup ("client_id"), CompareOperator.EQ, LicenseService.client_id ());
        assert_cmpstr (form.lookup ("redirect_uri"), CompareOperator.EQ, browser.redirect);
        assert_cmpstr (LicenseService.pkce_challenge (form.lookup ("code_verifier")), CompareOperator.EQ, request.lookup ("code_challenge"));

        try {
            assert_cmpstr (yield service.get_license (), CompareOperator.EQ, portal.issued_token);
        } catch (Error e) {
            Test.fail ();
        }

        service.sign_out ();
        assert_false (service.has_license ());
        portal.stop ();
    }

    private async void expect_sign_in_failure (FakePortal portal, FakeBrowser browser, int code) {
        var store = new MemoryLicenseStore ();
        var service = license_service (portal, browser, store);

        try {
            yield service.sign_in ();
            Test.fail ();
        } catch (Error e) {
            assert_true (e is LicenseSignInError);
            assert_cmpint (e.code, CompareOperator.EQ, code);
        }

        assert_null (store.license);
    }

    // a redirect that does not answer our request must never be redeemed
    private async void test_sign_in_state_mismatch () {
        var portal = new FakePortal ();
        portal.issued_token = token (now () + 86400);
        var browser = new FakeBrowser () { echo_state = false, wrong_state = "forged" };

        yield expect_sign_in_failure (portal, browser, LicenseSignInError.FAILED);

        assert_null (portal.last_form);
        portal.stop ();
    }

    private async void test_sign_in_declined () {
        var portal = new FakePortal ();
        var browser = new FakeBrowser () { error = "access_denied", code = null };

        yield expect_sign_in_failure (portal, browser, LicenseSignInError.CANCELLED);

        browser.error = "server_error";
        yield expect_sign_in_failure (portal, browser, LicenseSignInError.FAILED);

        portal.stop ();
    }

    private async void test_sign_in_no_entitlement () {
        var portal = new FakePortal ();
        portal.token_status = 400;
        portal.token_error = "invalid_grant";

        yield expect_sign_in_failure (portal, new FakeBrowser (), LicenseSignInError.NO_ENTITLEMENT);

        portal.token_error = "server_error";
        yield expect_sign_in_failure (portal, new FakeBrowser (), LicenseSignInError.FAILED);

        // an answer that is not a licence is refused
        portal.token_status = 200;
        portal.issued_token = "not-a-jwt";
        yield expect_sign_in_failure (portal, new FakeBrowser (), LicenseSignInError.FAILED);

        portal.stop ();
    }

    private async void test_sign_in_cancelled () {
        var portal = new FakePortal ();

        yield expect_sign_in_failure (portal, new FakeBrowser () { cancel = true }, LicenseSignInError.CANCELLED);

        portal.stop ();
    }

    private async void test_license_unreadable () {
        var portal = new FakePortal ();
        var store = new MemoryLicenseStore () { license = "garbage" };
        var service = license_service (portal, new FakeBrowser (), store);

        try {
            assert_null (yield service.get_license ());
        } catch (Error e) {
            Test.fail ();
        }

        assert_null (store.license);

        // nothing stored at all
        try {
            assert_null (yield service.get_license ());
        } catch (Error e) {
            Test.fail ();
        }

        portal.stop ();
    }

    private async void test_license_fresh () {
        var portal = new FakePortal ();
        var fresh = token (now () + 86400 * 60);
        var store = new MemoryLicenseStore () { license = fresh };
        var service = license_service (portal, new FakeBrowser (), store);

        try {
            assert_cmpstr (yield service.get_license (), CompareOperator.EQ, fresh);
        } catch (Error e) {
            Test.fail ();
        }

        assert_cmpint (portal.renewals, CompareOperator.EQ, 0);
        portal.stop ();
    }

    private async void test_license_renewed () {
        var portal = new FakePortal ();
        portal.renewed_token = token (now () + 86400 * 365, "renewed");
        var store = new MemoryLicenseStore () { license = token (now () + 86400 * 3) };
        var service = license_service (portal, new FakeBrowser (), store);

        try {
            // due: it expires in three days, inside the renewal window
            assert_cmpstr (yield service.get_license (), CompareOperator.EQ, portal.renewed_token);
        } catch (Error e) {
            Test.fail ();
        }

        assert_cmpint (portal.renewals, CompareOperator.EQ, 1);
        assert_cmpstr (store.license, CompareOperator.EQ, portal.renewed_token);
        portal.stop ();
    }

    private async void test_license_revoked () {
        var portal = new FakePortal ();
        portal.renew_status = 402;
        var store = new MemoryLicenseStore () { license = token (now () - 100) };
        var service = license_service (portal, new FakeBrowser (), store);

        try {
            // the CRM took the licence back: sign in again
            assert_null (yield service.get_license ());
        } catch (Error e) {
            Test.fail ();
        }

        assert_null (store.license);
        portal.stop ();
    }

    private async void test_license_renewal_throttled () {
        var portal = new FakePortal ();
        // "nothing to renew yet"
        portal.renew_status = 204;
        var due = token (now () + 86400);
        var store = new MemoryLicenseStore () { license = due };
        var service = license_service (portal, new FakeBrowser (), store);

        try {
            for (int i = 0; i < 5; i++) {
                assert_cmpstr (yield service.get_license (), CompareOperator.EQ, due);
            }
        } catch (Error e) {
            Test.fail ();
        }

        // asked once, not on every request
        assert_cmpint (portal.renewals, CompareOperator.EQ, 1);
        portal.stop ();
    }

    // The server will answer "expired", which is the accurate message, so the expired licence is still sent
    private async void test_license_expired_offline () {
        var portal = new FakePortal ();
        var expired = token (now () - 86400);
        var store = new MemoryLicenseStore () { license = expired };
        var service = license_service (portal, new FakeBrowser (), store);
        portal.stop ();

        try {
            assert_cmpstr (yield service.get_license (), CompareOperator.EQ, expired);
        } catch (Error e) {
            Test.fail ();
        }

        assert_cmpstr (store.license, CompareOperator.EQ, expired);
    }
}
