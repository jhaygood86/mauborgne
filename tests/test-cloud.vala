/* Cloud Backup building blocks: crypto, licence helpers, merge and the synced content. */
namespace CloudTests {

    private const string EXPORT_KEY_WRAP = "1b81d064b37e48b3b2384cb1223c648994624ead6ca4841f8624a5724767a714";

    public void register () {
        Test.add_func ("/cloud/crypto_hkdf_rfc5869_case_1", test_hkdf_case_1);
        Test.add_func ("/cloud/crypto_hkdf_rfc5869_case_3", test_hkdf_case_3);
        Test.add_func ("/cloud/crypto_wrap_key_known_answer", test_wrap_key_known_answer);
        Test.add_func ("/cloud/crypto_wrap_key_depends_on_export_key", test_wrap_key_depends);
        Test.add_func ("/cloud/crypto_wrap_roundtrip", test_wrap_roundtrip);
        Test.add_func ("/cloud/crypto_wrap_fresh_nonce", test_wrap_fresh_nonce);
        Test.add_func ("/cloud/crypto_unwrap_rejects_tampering", test_unwrap_rejects);
        Test.add_func ("/cloud/crypto_backup_ids", test_backup_ids);
        Test.add_func ("/cloud/crypto_password_normalisation", test_password_normalisation);
        Test.add_func ("/cloud/crypto_hashes_and_compare", test_hash_and_compare);
        Test.add_func ("/cloud/license_pkce_rfc7636", test_pkce_vector);
        Test.add_func ("/cloud/license_pkce_pairs", test_pkce_pairs);
        Test.add_func ("/cloud/license_client_id", test_client_id);
        Test.add_func ("/cloud/license_claims", test_claims);
        Test.add_func ("/cloud/license_claims_rejected", test_claims_rejected);
        Test.add_func ("/cloud/policy_new_password", test_policy_new);
        Test.add_func ("/cloud/policy_existing_password", test_policy_existing);
        Test.add_func ("/cloud/merge_keeps_both_sides", test_merge_union);
        Test.add_func ("/cloud/merge_newer_pad_wins", test_merge_newer_wins);
        Test.add_func ("/cloud/merge_tie_keeps_local", test_merge_tie);
        Test.add_func ("/cloud/merge_hotp_takes_larger_counter", test_merge_hotp_counter);
        Test.add_func ("/cloud/merge_deletion_beats_older_pad", test_merge_deletion);
        Test.add_func ("/cloud/merge_pad_modified_after_deletion_survives", test_merge_revived);
        Test.add_func ("/cloud/merge_forgets_old_tombstones", test_merge_old_tombstone);
        Test.add_func ("/cloud/merge_legacy_pads_survive", test_merge_legacy);
        Test.add_func ("/cloud/merge_order", test_merge_order);
        Test.add_func ("/cloud/merge_converges", test_merge_converges);
        Test.add_func ("/cloud/snapshot_content_roundtrip", test_snapshot_roundtrip);
        Test.add_func ("/cloud/snapshot_member_names", test_snapshot_member_names);
        Test.add_func ("/cloud/snapshot_reads_other_apps", test_snapshot_reads_commercial_json);
        Test.add_func ("/cloud/snapshot_equivalence", test_snapshot_equivalence);
    }

    // ---- helpers -------------------------------------------------------------------------

    private uint8[] hex (string text) {
        return AegisManager.hex_to_bytes (text);
    }

    private string to_hex (uint8[] bytes) {
        return AegisManager.bytes_to_hex (bytes);
    }

    private uint8[] export_key () {
        var key = new uint8[64];

        for (int i = 0; i < key.length; i++) {
            key[i] = (uint8) i;
        }

        return key;
    }

    private SyncPad pad (string issuer, string account, int64 modified, OneTimePadType type = OneTimePadType.TOTP, int64 counter = 0, string secret = "JBSWY3DPEHPK3PXP") {
        var one = TestSupport.make_pad (type, issuer, account);
        one.modified_at = modified;
        one.counter = counter;

        return new SyncPad (one, secret);
    }

    private SyncSnapshot snapshot (SyncPad[] pads, int64 order_modified = 0) {
        var result = new SyncSnapshot ();

        foreach (var one in pads) {
            result.pads.add (one);
        }

        result.order_modified = order_modified;

        return result;
    }

    private SyncPad? find (SyncSnapshot snapshot, string identity) {
        foreach (var one in snapshot.pads) {
            if (one.pad.identity == identity) {
                return one;
            }
        }

        return null;
    }

    private string identities (SyncSnapshot snapshot) {
        var names = new string[snapshot.pads.size];

        for (int i = 0; i < names.length; i++) {
            names[i] = snapshot.pads[i].pad.identity;
        }

        return string.joinv (",", names);
    }

    // ---- crypto --------------------------------------------------------------------------

    // RFC 5869 appendix A.1
    private void test_hkdf_case_1 () {
        var okm = Mauborgne.CloudCrypto.hkdf_sha256 (
            hex ("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
            hex ("000102030405060708090a0b0c"),
            hex ("f0f1f2f3f4f5f6f7f8f9"),
            42);

        assert_cmpstr (to_hex (okm), CompareOperator.EQ,
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865");
    }

    // RFC 5869 appendix A.3: no salt, no info
    private void test_hkdf_case_3 () {
        var okm = Mauborgne.CloudCrypto.hkdf_sha256 (
            hex ("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), new uint8[0], new uint8[0], 42);

        assert_cmpstr (to_hex (okm), CompareOperator.EQ,
            "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8");
    }

    // computed independently with Python's hmac, so the other apps' derivation must agree
    private void test_wrap_key_known_answer () {
        var key = Mauborgne.CloudCrypto.derive_wrap_key (export_key ());

        assert_cmpint (key.length, CompareOperator.EQ, 32);
        assert_cmpstr (to_hex (key), CompareOperator.EQ, EXPORT_KEY_WRAP);
    }

    private void test_wrap_key_depends () {
        var first = Mauborgne.CloudCrypto.derive_wrap_key (export_key ());

        assert_cmpstr (to_hex (first), CompareOperator.EQ, to_hex (Mauborgne.CloudCrypto.derive_wrap_key (export_key ())));
        assert_cmpstr (to_hex (first), CompareOperator.NE, to_hex (Mauborgne.CloudCrypto.derive_wrap_key (new uint8[64])));
    }

    private void test_wrap_roundtrip () {
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (export_key ());
        var backup_key = Mauborgne.CloudCrypto.new_backup_key ();
        var hash = Mauborgne.CloudCrypto.hash_vault ("{\"vault\":1}");

        var blob = Mauborgne.CloudCrypto.wrap (wrap_key, backup_key, hash, "cred", "backup-1");

        // nonce 12 + tag 16 + key 32 + hash 32
        assert_cmpint (blob.length, CompareOperator.EQ, 92);

        var opened = Mauborgne.CloudCrypto.unwrap (wrap_key, blob, "cred", "backup-1");

        assert_nonnull (opened);
        assert_cmpstr (to_hex (opened.backup_key), CompareOperator.EQ, to_hex (backup_key));
        assert_cmpstr (to_hex (opened.vault_hash), CompareOperator.EQ, to_hex (hash));
    }

    private void test_wrap_fresh_nonce () {
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (export_key ());
        var key = Mauborgne.CloudCrypto.new_backup_key ();
        var hash = Mauborgne.CloudCrypto.hash_vault ("v");

        assert_cmpstr (
            to_hex (Mauborgne.CloudCrypto.wrap (wrap_key, key, hash, "c", "b")), CompareOperator.NE,
            to_hex (Mauborgne.CloudCrypto.wrap (wrap_key, key, hash, "c", "b")));
    }

    private void test_unwrap_rejects () {
        var wrap_key = Mauborgne.CloudCrypto.derive_wrap_key (export_key ());
        var blob = Mauborgne.CloudCrypto.wrap (wrap_key, Mauborgne.CloudCrypto.new_backup_key (), Mauborgne.CloudCrypto.hash_vault ("v"), "cred", "b1");

        assert_null (Mauborgne.CloudCrypto.unwrap (Mauborgne.CloudCrypto.derive_wrap_key (new uint8[64]), blob, "cred", "b1"));
        // bound to the account and to the backup
        assert_null (Mauborgne.CloudCrypto.unwrap (wrap_key, blob, "other-account", "b1"));
        assert_null (Mauborgne.CloudCrypto.unwrap (wrap_key, blob, "cred", "b2"));

        for (int i = 0; i < blob.length; i += 9) {
            var tampered = new uint8[blob.length];
            Memory.copy (tampered, blob, blob.length);
            tampered[i] ^= 1;

            assert_null (Mauborgne.CloudCrypto.unwrap (wrap_key, tampered, "cred", "b1"));
        }

        var shorter = new uint8[blob.length - 1];
        Memory.copy (shorter, blob, shorter.length);

        assert_null (Mauborgne.CloudCrypto.unwrap (wrap_key, shorter, "cred", "b1"));
        assert_null (Mauborgne.CloudCrypto.unwrap (wrap_key, new uint8[0], "cred", "b1"));
    }

    private void test_backup_ids () {
        var seen = new Gee.HashSet<string> ();

        for (int i = 0; i < 50; i++) {
            var id = Mauborgne.CloudCrypto.new_backup_id ();

            assert_true (Regex.match_simple ("^[A-Za-z0-9_-]{16,64}$", id));
            assert_true (seen.add (id));
        }

        assert_cmpint (Mauborgne.CloudCrypto.new_backup_id ().length, CompareOperator.EQ, 22);
    }

    private void test_password_normalisation () {
        // "é" as one code point against "e" plus a combining acute accent
        assert_cmpstr (
            to_hex (Mauborgne.CloudCrypto.password_bytes ("café")), CompareOperator.EQ,
            to_hex (Mauborgne.CloudCrypto.password_bytes ("café")));

        // compatibility forms fold too (NFKC): full-width letters become plain ones
        assert_cmpstr (
            to_hex (Mauborgne.CloudCrypto.password_bytes ("ｐａｓｓ")), CompareOperator.EQ,
            to_hex (Mauborgne.CloudCrypto.password_bytes ("pass")));

        assert_cmpint (Mauborgne.CloudCrypto.password_bytes ("").length, CompareOperator.EQ, 0);
    }

    private void test_hash_and_compare () {
        assert_cmpstr (
            to_hex (Mauborgne.CloudCrypto.hash_vault ("")), CompareOperator.EQ,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

        assert_true (Mauborgne.CloudCrypto.fixed_time_equals (hex ("0102"), hex ("0102")));
        assert_false (Mauborgne.CloudCrypto.fixed_time_equals (hex ("0102"), hex ("0103")));
        assert_false (Mauborgne.CloudCrypto.fixed_time_equals (hex ("0102"), hex ("010203")));

        var secret = hex ("aabbcc");
        Mauborgne.CloudCrypto.zero (secret);
        assert_cmpstr (to_hex (secret), CompareOperator.EQ, "000000");
    }

    // ---- licence helpers -----------------------------------------------------------------

    // RFC 7636 appendix B
    private void test_pkce_vector () {
        assert_cmpstr (
            LicenseService.pkce_challenge ("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), CompareOperator.EQ,
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    }

    private void test_pkce_pairs () {
        string verifier, challenge;
        LicenseService.new_pkce_pair (out verifier, out challenge);

        assert_cmpint (verifier.length, CompareOperator.EQ, 43);
        assert_true (Regex.match_simple ("^[A-Za-z0-9_-]{43}$", verifier));
        assert_cmpstr (LicenseService.pkce_challenge (verifier), CompareOperator.EQ, challenge);

        string other_verifier, other_challenge;
        LicenseService.new_pkce_pair (out other_verifier, out other_challenge);
        assert_cmpstr (verifier, CompareOperator.NE, other_verifier);
    }

    // derived independently; the CRM matches licences to the app by this id
    private void test_client_id () {
        assert_cmpstr (LicenseService.client_id (), CompareOperator.EQ, "shNuLpCzBpLbfzuF-1i6kw5gsT8iNSBp1_quR0pkYgg");
        assert_cmpint (LicenseService.client_id ().length, CompareOperator.EQ, 43);
    }

    private string jwt (string header, string claims) {
        return LicenseService.base64_url (header.data) + "." + LicenseService.base64_url (claims.data) + "." + LicenseService.base64_url ("signature".data);
    }

    private void test_claims () {
        var claims = LicenseService.read_claims (jwt ("{\"alg\":\"RS256\"}", "{\"exp\":2000000000,\"contactId\":\"abc\",\"subscriptionId\":42}"));

        assert_nonnull (claims);
        assert_true ((int64) claims.expires_at == 2000000000);
        assert_cmpstr (claims.contact_id, CompareOperator.EQ, "abc");
        assert_cmpstr (claims.subscription_id, CompareOperator.EQ, "42");

        var minimal = LicenseService.read_claims (jwt ("{\"alg\":\"RS256\"}", "{\"exp\":1}"));
        assert_nonnull (minimal);
        assert_null (minimal.contact_id);
    }

    private void test_claims_rejected () {
        assert_null (LicenseService.read_claims (""));
        assert_null (LicenseService.read_claims ("a.b"));
        assert_null (LicenseService.read_claims ("a.b.c.d"));
        assert_null (LicenseService.read_claims ("not.valid.base64!"));
        // only RS256 is accepted
        assert_null (LicenseService.read_claims (jwt ("{\"alg\":\"HS256\"}", "{\"exp\":2000000000}")));
        assert_null (LicenseService.read_claims (jwt ("{\"alg\":\"none\"}", "{\"exp\":2000000000}")));
        // exp is required and must be a number
        assert_null (LicenseService.read_claims (jwt ("{\"alg\":\"RS256\"}", "{\"contactId\":\"abc\"}")));
        assert_null (LicenseService.read_claims (jwt ("{\"alg\":\"RS256\"}", "{\"exp\":\"tomorrow\"}")));
        assert_null (LicenseService.read_claims (jwt ("{\"alg\":\"RS256\"}", "[1,2]")));
    }

    // ---- password policy -----------------------------------------------------------------

    private void test_policy_new () {
        assert_nonnull (Mauborgne.CloudPasswordPolicy.validate_new ("short", "short"));
        assert_nonnull (Mauborgne.CloudPasswordPolicy.validate_new ("eleven chars", "eleven chars".substring (0, 11)));
        assert_nonnull (Mauborgne.CloudPasswordPolicy.validate_new ("twelve chars", "different one"));
        assert_null (Mauborgne.CloudPasswordPolicy.validate_new ("twelve chars", "twelve chars"));
        // the length counts characters, not bytes
        assert_nonnull (Mauborgne.CloudPasswordPolicy.validate_new ("éééééé", "éééééé"));
    }

    private void test_policy_existing () {
        assert_nonnull (Mauborgne.CloudPasswordPolicy.validate_existing (""));
        assert_null (Mauborgne.CloudPasswordPolicy.validate_existing ("x"));
    }

    // ---- merge ---------------------------------------------------------------------------

    private const int64 NOW = 1800000000000;

    private void test_merge_union () {
        var merged = Mauborgne.SyncMerge.merge (
            snapshot ({ pad ("A", "a", 10) }), snapshot ({ pad ("B", "b", 10) }), NOW);

        assert_cmpint (merged.pads.size, CompareOperator.EQ, 2);
        assert_nonnull (find (merged, "A:a"));
        assert_nonnull (find (merged, "B:b"));
    }

    private void test_merge_newer_wins () {
        var local = pad ("A", "a", 10);
        local.pad.note = "local";
        var remote = pad ("A", "a", 20);
        remote.pad.note = "remote";

        assert_cmpstr (find (Mauborgne.SyncMerge.merge (snapshot ({ local }), snapshot ({ remote }), NOW), "A:a").pad.note, CompareOperator.EQ, "remote");

        local.pad.modified_at = 30;
        assert_cmpstr (find (Mauborgne.SyncMerge.merge (snapshot ({ local }), snapshot ({ remote }), NOW), "A:a").pad.note, CompareOperator.EQ, "local");
    }

    private void test_merge_tie () {
        var local = pad ("A", "a", 10);
        local.pad.note = "local";
        var remote = pad ("A", "a", 10);
        remote.pad.note = "remote";

        assert_cmpstr (find (Mauborgne.SyncMerge.merge (snapshot ({ local }), snapshot ({ remote }), NOW), "A:a").pad.note, CompareOperator.EQ, "local");
    }

    private void test_merge_hotp_counter () {
        // the remote pad is newer, but the local counter is further on and counters only move forward
        var local = pad ("A", "a", 10, OneTimePadType.HOTP, 9);
        var remote = pad ("A", "a", 20, OneTimePadType.HOTP, 3);
        remote.pad.note = "remote";

        var winner = find (Mauborgne.SyncMerge.merge (snapshot ({ local }), snapshot ({ remote }), NOW), "A:a");

        assert_cmpint ((int) winner.pad.counter, CompareOperator.EQ, 9);
        assert_cmpstr (winner.pad.note, CompareOperator.EQ, "remote");
        // the original pad is left alone
        assert_cmpint ((int) remote.pad.counter, CompareOperator.EQ, 3);

        // and the other way round
        var merged = find (Mauborgne.SyncMerge.merge (snapshot ({ remote }), snapshot ({ local }), NOW), "A:a");
        assert_cmpint ((int) merged.pad.counter, CompareOperator.EQ, 9);
    }

    private void test_merge_deletion () {
        var local = snapshot ({ pad ("A", "a", 10) });
        var remote = snapshot ({});
        remote.deleted["A:a"] = NOW - 1000;

        // deleted after the pad was last changed
        local.pads[0].pad.modified_at = NOW - 5000;

        var merged = Mauborgne.SyncMerge.merge (local, remote, NOW);

        assert_cmpint (merged.pads.size, CompareOperator.EQ, 0);
        assert_true (merged.deleted.has_key ("A:a"));
        assert_true (merged.deleted["A:a"] == NOW - 1000);
    }

    private void test_merge_revived () {
        var local = snapshot ({ pad ("A", "a", NOW - 1000) });
        var remote = snapshot ({});
        remote.deleted["A:a"] = NOW - 5000;

        var merged = Mauborgne.SyncMerge.merge (local, remote, NOW);

        assert_nonnull (find (merged, "A:a"));
        assert_false (merged.deleted.has_key ("A:a"));
    }

    private void test_merge_old_tombstone () {
        var local = snapshot ({});
        local.deleted["A:a"] = NOW - Mauborgne.SyncMerge.TOMBSTONE_LIFETIME_MS - 1000;
        local.deleted["B:b"] = NOW - 1000;

        var merged = Mauborgne.SyncMerge.merge (local, snapshot ({}), NOW);

        assert_false (merged.deleted.has_key ("A:a"));
        assert_true (merged.deleted.has_key ("B:b"));
    }

    // pads from before sync existed carry no modification time
    private void test_merge_legacy () {
        var merged = Mauborgne.SyncMerge.merge (snapshot ({ pad ("A", "a", 0) }), snapshot ({}), NOW);

        assert_nonnull (find (merged, "A:a"));
    }

    private void test_merge_order () {
        var local = snapshot ({ pad ("L1", "x", 1), pad ("L2", "x", 1) });
        var remote = snapshot ({ pad ("R1", "x", 1), pad ("L2", "x", 1) }, 50);

        // this app has no order of its own: the cloud's order wins, and pads it has not seen follow
        assert_cmpstr (identities (Mauborgne.SyncMerge.merge (local, remote, NOW)), CompareOperator.EQ, "R1:x,L2:x,L1:x");

        // unless ours is strictly newer
        local.order_modified = 80;
        assert_cmpstr (identities (Mauborgne.SyncMerge.merge (local, remote, NOW)), CompareOperator.EQ, "L1:x,L2:x,R1:x");
        assert_cmpint ((int) Mauborgne.SyncMerge.merge (local, remote, NOW).order_modified, CompareOperator.EQ, 80);
    }

    private void test_merge_converges () {
        var a = snapshot ({ pad ("A", "1", 10), pad ("C", "3", 40) });
        a.deleted["D:4"] = NOW - 100;
        var b = snapshot ({ pad ("A", "1", 20), pad ("B", "2", 5), pad ("D", "4", 10) });

        var ab = Mauborgne.SyncMerge.merge (a, b, NOW);
        var ba = Mauborgne.SyncMerge.merge (b, a, NOW);

        assert_true (ab.equivalent_to (ba));
        assert_cmpint (ab.pads.size, CompareOperator.EQ, 3);
        assert_null (find (ab, "D:4"));

        // merging the result again changes nothing
        assert_true (Mauborgne.SyncMerge.merge (ab, ba, NOW).equivalent_to (ab));
    }

    // ---- snapshot and the synced content --------------------------------------------------

    private void test_snapshot_roundtrip () {
        var original = snapshot ({
            pad ("Example", "alice@example.com", 1700000000123),
            pad ("Acme", "bob", 1700000000456, OneTimePadType.HOTP, 7, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        }, 99);
        original.pads[0].pad.account_name_display = "Alice";
        original.pads[1].pad.digits = 8;
        original.deleted["Old:one"] = 1699999999999;

        var node = parse_json (original.to_content ().to_json ());
        var content = Json.gobject_deserialize (typeof (AegisVaultContent), node) as AegisVaultContent;
        var back = SyncSnapshot.from_content (content);

        assert_true (original.equivalent_to (back));

        var alice = find (back, "Example:alice@example.com");
        assert_cmpstr (alice.pad.account_name_display, CompareOperator.EQ, "Alice");
        assert_true ((int64) alice.pad.modified_at == 1700000000123);

        var bob = find (back, "Acme:bob");
        assert_true (bob.pad.pad_type == OneTimePadType.HOTP);
        assert_cmpint ((int) bob.pad.counter, CompareOperator.EQ, 7);
        assert_cmpint (bob.pad.digits, CompareOperator.EQ, 8);
        assert_true ((int64) back.deleted["Old:one"] == 1699999999999);
        assert_cmpint ((int) back.order_modified, CompareOperator.EQ, 99);
    }

    private void test_snapshot_member_names () {
        var original = snapshot ({ pad ("Example", "alice", 1700000000123) }, 5);
        original.deleted["Old:one"] = 1699999999999;

        var root = parse_json (original.to_content ().to_json ()).get_object ();

        assert_true (root.has_member ("mb_deleted"));
        assert_false (root.has_member ("deleted"));
        assert_true ((int64) root.get_object_member ("mb_deleted").get_int_member ("Old:one") == 1699999999999);
        assert_cmpint ((int) root.get_int_member ("mb_order_modified"), CompareOperator.EQ, 5);
        assert_false (root.has_member ("order-modified"));

        var entry = root.get_array_member ("entries").get_object_element (0);

        assert_true ((int64) entry.get_int_member ("mb_modified") == 1700000000123);
        assert_cmpstr (entry.get_string_member ("mb_display"), CompareOperator.EQ, "alice");
        assert_false (entry.has_member ("modified"));
        assert_false (entry.has_member ("display-name"));
        assert_cmpstr (entry.get_string_member ("type"), CompareOperator.EQ, "totp");
    }

    // what the Windows and Android apps put in their vaults
    private const string COMMERCIAL_CONTENT = """{
        "version": 1,
        "entries": [
            {
                "type": "totp", "uuid": "9d6c9d3e-5c51-4a1e-9d3f-0e8e8d2f0a11", "name": "alice@example.com",
                "issuer": "Example", "note": "work", "icon": null,
                "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA256", "digits": 8, "period": 60 },
                "mb_modified": 1700000000123, "mb_display": "Alice (work)"
            },
            {
                "type": "hotp", "uuid": "0b2f5f9c-8a4d-4a0e-8d4e-1f6a6c3b7e22", "name": "bob",
                "issuer": "Acme", "note": "", "icon": null,
                "info": { "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "algo": "SHA1", "digits": 6, "counter": 12 },
                "mb_modified": 1700000000456
            }
        ],
        "mb_deleted": { "Gone:account": 1700000000999 },
        "mb_order_modified": 1700000000777
    }""";

    private void test_snapshot_reads_commercial_json () {
        var content = Json.gobject_deserialize (typeof (AegisVaultContent), parse_json (COMMERCIAL_CONTENT)) as AegisVaultContent;
        var snapshot = SyncSnapshot.from_content (content);

        assert_cmpint (snapshot.pads.size, CompareOperator.EQ, 2);

        var alice = find (snapshot, "Example:alice@example.com");
        assert_true (alice.pad.algorithm == OneTimePadAlgorithm.SHA256);
        assert_cmpint (alice.pad.digits, CompareOperator.EQ, 8);
        assert_cmpint (alice.pad.period, CompareOperator.EQ, 60);
        assert_cmpstr (alice.pad.account_name_display, CompareOperator.EQ, "Alice (work)");
        assert_cmpstr (alice.pad.note, CompareOperator.EQ, "work");
        assert_cmpstr (alice.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        assert_true ((int64) alice.pad.modified_at == 1700000000123);

        var bob = find (snapshot, "Acme:bob");
        assert_true (bob.pad.pad_type == OneTimePadType.HOTP);
        assert_cmpint ((int) bob.pad.counter, CompareOperator.EQ, 12);
        assert_cmpstr (bob.pad.account_name_display, CompareOperator.EQ, "bob");

        assert_true ((int64) snapshot.deleted["Gone:account"] == 1700000000999);
        assert_true ((int64) snapshot.order_modified == 1700000000777);
    }

    private void test_snapshot_equivalence () {
        var a = snapshot ({ pad ("A", "1", 10), pad ("B", "2", 10) });
        var b = snapshot ({ pad ("B", "2", 10), pad ("A", "1", 10) });

        // the order of the pads is not a difference
        assert_true (a.equivalent_to (b));

        b.pads[0].pad.note = "changed";
        assert_false (a.equivalent_to (b));

        var c = snapshot ({ pad ("A", "1", 10), pad ("B", "2", 10, OneTimePadType.TOTP, 0, "OTHERSECRET234567") });
        assert_false (a.equivalent_to (c));

        var d = snapshot ({ pad ("A", "1", 10), pad ("B", "2", 10) });
        d.deleted["X:y"] = 5;
        assert_false (a.equivalent_to (d));

        var e = snapshot ({ pad ("A", "1", 10), pad ("B", "2", 10) }, 7);
        assert_false (a.equivalent_to (e));

        assert_false (a.equivalent_to (snapshot ({ pad ("A", "1", 10) })));
    }

    private Json.Node parse_json (string text) {
        var parser = new Json.Parser ();

        try {
            parser.load_from_data (text);
        } catch (Error e) {
            Test.message ("bad json: %s", e.message);
            Test.fail ();
        }

        return parser.get_root ().copy ();
    }
}
