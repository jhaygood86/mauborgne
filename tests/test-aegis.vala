namespace AegisTests {

    const string PASSPHRASE = "correct horse battery staple";

    // Shaped like a real Aegis export: extra members we do not model, and a null icon
    const string CONTENT_JSON = """{
        "version": 2,
        "entries": [
            {
                "type": "totp", "uuid": "01234567-89ab-cdef-0123-456789abcdef",
                "name": "alice@example.com", "issuer": "Example", "note": "work",
                "favorite": false, "icon": null, "icon_mime": null, "icon_hash": null, "groups": [],
                "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA1", "digits": 6, "period": 30 }
            },
            {
                "type": "hotp", "uuid": "11234567-89ab-cdef-0123-456789abcdef",
                "name": "bob", "issuer": "Acme", "note": "",
                "icon": null,
                "info": { "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "algo": "SHA256", "digits": 8, "counter": 5 }
            }
        ]
    }""";

    public void register () {
        Test.add_func ("/aegis/hex_roundtrip", test_hex_roundtrip);
        Test.add_func ("/aegis/hex_invalid", test_hex_invalid);
        Test.add_func ("/aegis/json_entry_member_names", test_entry_member_names);
        Test.add_func ("/aegis/json_slot_member_names", test_slot_member_names);
        Test.add_func ("/aegis/json_rename_ignores_missing", test_rename_ignores_missing);
        Test.add_func ("/aegis/import_content", test_deserialize_content);
        Test.add_func ("/aegis/import_plain_vault", test_plain_vault);
        Test.add_func ("/aegis/import_plain_vault_with_null_header", test_plain_vault_null_header);
        Test.add_func ("/aegis/crypto_master_key_roundtrip", test_master_key_roundtrip);
        Test.add_func ("/aegis/crypto_data_roundtrip", test_data_roundtrip);
        Test.add_func ("/aegis/export_encrypted_roundtrip", test_encrypted_roundtrip);
        Test.add_func ("/aegis/export_vault_layout", test_vault_layout);
        Test.add_func ("/aegis/export_wrong_password", test_wrong_password);
        Test.add_func ("/aegis/export_tampered_data", test_tampered_data);
        Test.add_func ("/aegis/export_different_salts", test_unique_salts);
        Test.add_func ("/aegis/slots_password_slot_lookup", test_password_slot_lookup);
        Test.add_func ("/aegis/slots_deserialize_types", test_slot_types);
    }

    private Json.Node parse (string json) {
        var parser = new Json.Parser ();

        try {
            parser.load_from_data (json);
        } catch (Error e) {
            Test.message ("bad json: %s", e.message);
            Test.fail ();
        }

        return parser.get_root ().copy ();
    }

    private AegisVaultContent content_from_json () {
        var content = Json.gobject_deserialize (typeof (AegisVaultContent), parse (CONTENT_JSON)) as AegisVaultContent;
        assert_nonnull (content);
        return content;
    }

    private AegisVaultContent sample_content () {
        var content = new AegisVaultContent ();
        content.version = 2;
        content.entries = new Gee.ArrayList<AegisVaultContent.AegisVaultEntry> ();

        var totp = TestSupport.make_pad (OneTimePadType.TOTP, "Example", "alice@example.com");
        totp.note = "work";
        content.entries.add (totp.build_aegis_vault_entry (TestSupport.SHA1_SECRET));

        var hotp = TestSupport.make_pad (OneTimePadType.HOTP, "Acme", "bob");
        hotp.counter = 5;
        hotp.digits = 8;
        hotp.algorithm = OneTimePadAlgorithm.SHA256;
        content.entries.add (hotp.build_aegis_vault_entry (TestSupport.SHA1_SECRET));

        return content;
    }

    private void assert_sample_content (AegisVaultContent content) {
        assert_cmpint (content.entries.size, CompareOperator.EQ, 2);

        var totp = content.entries[0] as AegisVaultContent.AegisTotpVaultEntry;
        assert_nonnull (totp);
        assert_cmpstr (totp.issuer, CompareOperator.EQ, "Example");
        assert_cmpstr (totp.name, CompareOperator.EQ, "alice@example.com");
        assert_cmpstr (totp.note, CompareOperator.EQ, "work");
        assert_cmpstr (totp.info.secret, CompareOperator.EQ, TestSupport.SHA1_SECRET);
        assert_cmpstr (totp.info.algo, CompareOperator.EQ, "SHA1");
        assert_cmpint (totp.info.digits, CompareOperator.EQ, 6);
        assert_cmpint (totp.info.period, CompareOperator.EQ, 30);

        var hotp = content.entries[1] as AegisVaultContent.AegisHotpVaultEntry;
        assert_nonnull (hotp);
        assert_cmpstr (hotp.issuer, CompareOperator.EQ, "Acme");
        assert_cmpstr (hotp.info.algo, CompareOperator.EQ, "SHA256");
        assert_cmpint (hotp.info.digits, CompareOperator.EQ, 8);
        assert_cmpint ((int) hotp.info.counter, CompareOperator.EQ, 5);
    }

    private string content_to_json (AegisVaultContent content) {
        return AegisManager.get_json_string (content);
    }

    private void test_hex_roundtrip () {
        uint8[] bytes = { 0x00, 0x01, 0x7f, 0x80, 0xab, 0xff };

        var hex = AegisManager.bytes_to_hex (bytes);
        assert_cmpstr (hex, CompareOperator.EQ, "00017f80abff");

        var back = AegisManager.hex_to_bytes (hex);
        assert_nonnull (back);
        assert_cmpint (back.length, CompareOperator.EQ, bytes.length);

        for (int i = 0; i < bytes.length; i++) {
            assert_cmpint (back[i], CompareOperator.EQ, bytes[i]);
        }

        // upper case is accepted too
        assert_cmpint (AegisManager.hex_to_bytes ("ABCDEF")[1], CompareOperator.EQ, 0xcd);
    }

    private void test_hex_invalid () {
        assert_null (AegisManager.hex_to_bytes ("abc"));
        assert_null (AegisManager.hex_to_bytes ("zz"));
        assert_null (AegisManager.hex_to_bytes (null));
    }

    private void test_entry_member_names () {
        var entry = new AegisVaultContent.AegisTotpVaultEntry ();
        entry.uuid = "u";
        entry.name = "alice";
        entry.issuer = "Example";
        entry.info = new AegisVaultContent.AegisTotpVaultEntryInfo ();
        entry.info.secret = "JBSWY3DPEHPK3PXP";
        entry.info.algo = "SHA1";
        entry.info.digits = 6;
        entry.info.period = 30;

        var object = AegisVaultContent.AegisVaultEntry.serialize (entry).get_object ();

        assert_true (object.has_member ("type"));
        assert_cmpstr (object.get_string_member ("type"), CompareOperator.EQ, "totp");
        assert_false (object.has_member ("entry-type"));
        assert_true (object.has_member ("icon"));
        assert_true (object.get_member ("icon").is_null ());
        assert_true (object.has_member ("info"));
        assert_cmpint ((int) object.get_object_member ("info").get_int_member ("period"), CompareOperator.EQ, 30);
    }

    private void test_slot_member_names () {
        var slot = new AegisVault.AegisPasswordSlot ();
        slot.uuid = "u";
        slot.key = "00";
        slot.n = 32768;
        slot.key_params = new AegisVault.AegisEncryptionParams ();
        slot.key_params.nonce = "aa";
        slot.key_params.tag = "bb";

        var object = AegisVault.AegisRawSlot.serialize (slot).get_object ();

        assert_cmpint ((int) object.get_int_member ("type"), CompareOperator.EQ, 1);
        assert_false (object.has_member ("slot-type"));
        assert_true (object.has_member ("key_params"));
        assert_false (object.has_member ("key-params"));
        assert_cmpstr (object.get_object_member ("key_params").get_string_member ("nonce"), CompareOperator.EQ, "aa");
        assert_cmpint ((int) object.get_int_member ("n"), CompareOperator.EQ, 32768);
    }

    private void test_rename_ignores_missing () {
        var entry = new AegisVaultContent.AegisTotpVaultEntry ();

        var node = Mauborgne.JsonHelpers.serialize_renamed (entry, { "no-such-member", "other", "entry-type", "type" });
        var object = node.get_object ();

        assert_false (object.has_member ("other"));
        assert_true (object.has_member ("type"));
    }

    private void test_deserialize_content () {
        var content = content_from_json ();

        assert_cmpint (content.version, CompareOperator.EQ, 2);

        var totp = content.entries[0] as AegisVaultContent.AegisTotpVaultEntry;
        assert_nonnull (totp);
        assert_cmpstr (totp.uuid, CompareOperator.EQ, "01234567-89ab-cdef-0123-456789abcdef");
        assert_cmpstr (totp.entry_type, CompareOperator.EQ, "totp");
        assert_cmpstr (totp.note, CompareOperator.EQ, "work");
        assert_null (totp.icon);
        assert_cmpint (totp.info.period, CompareOperator.EQ, 30);

        var hotp = content.entries[1] as AegisVaultContent.AegisHotpVaultEntry;
        assert_nonnull (hotp);
        assert_cmpstr (hotp.entry_type, CompareOperator.EQ, "hotp");
        assert_cmpint ((int) hotp.info.counter, CompareOperator.EQ, 5);
        assert_cmpint (hotp.info.digits, CompareOperator.EQ, 8);
    }

    private string plain_vault_json (string header) {
        return """{"version": 1, "header": %s, "db": "%s"}""".printf (header, Base64.encode (CONTENT_JSON.data));
    }

    private void test_plain_vault () {
        var vault = AegisManager.parse_vault (parse (plain_vault_json ("""{"slots": null, "params": {"nonce": null, "tag": null}}""")));

        assert_nonnull (vault);
        assert_false (AegisManager.is_vault_encrypted (vault));

        assert_sample_content_from_import (AegisManager.read_plain_vault (vault));
    }

    // Aegis writes "params": null for unencrypted vaults
    private void test_plain_vault_null_header () {
        var vault = AegisManager.parse_vault (parse (plain_vault_json ("""{"slots": null, "params": null}""")));

        assert_nonnull (vault);
        assert_false (AegisManager.is_vault_encrypted (vault));

        assert_sample_content_from_import (AegisManager.read_plain_vault (vault));
    }

    private void assert_sample_content_from_import (AegisVaultContent? content) {
        assert_nonnull (content);
        assert_cmpint (content.entries.size, CompareOperator.EQ, 2);
        assert_cmpstr (content.entries[0].issuer, CompareOperator.EQ, "Example");
        assert_cmpstr (content.entries[1].issuer, CompareOperator.EQ, "Acme");

        // and the entries turn into pads
        try {
            var pad = new OneTimePad.from_aegis_vault_entry (content.entries[0]);
            assert_cmpstr (pad.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        } catch (Error e) {
            Test.fail ();
        }
    }

    private void test_master_key_roundtrip () {
        var slot = AegisManager.create_password_slot ();
        var master_key = new uchar[32];
        for (int i = 0; i < master_key.length; i++) {
            master_key[i] = (uchar) i;
        }

        try {
            AegisManager.encrypt_master_key (slot, master_key, AegisManager.derive_key (slot, PASSPHRASE));
        } catch (Error e) {
            Test.fail ();
        }

        assert_cmpint (slot.key.length, CompareOperator.EQ, 64);
        assert_cmpint (slot.key_params.tag.length, CompareOperator.EQ, 32);

        var vault = new AegisVault ();
        vault.header = new AegisVault.AegisHeader ();
        vault.header.slots = new Gee.ArrayList<AegisVault.AegisRawSlot> ();
        vault.header.slots.add (slot);

        var recovered = AegisManager.decrypt_master_key (vault, PASSPHRASE);

        assert_nonnull (recovered);
        assert_cmpint (recovered.length, CompareOperator.EQ, master_key.length);
        for (int i = 0; i < master_key.length; i++) {
            assert_cmpint (recovered[i], CompareOperator.EQ, master_key[i]);
        }
    }

    private void test_data_roundtrip () {
        var vault = new AegisVault ();
        vault.header = new AegisVault.AegisHeader ();

        var key = new uchar[32];
        GCrypt.Random.nonce (key);

        var plaintext = "some secret data é中文";

        try {
            AegisManager.encrypt_data (vault, key, plaintext.data);
        } catch (Error e) {
            Test.fail ();
        }

        assert_nonnull (vault.db);
        assert_cmpint (vault.header.params.nonce.length, CompareOperator.EQ, 24);
        assert_cmpint (vault.header.params.tag.length, CompareOperator.EQ, 32);

        var decrypted = AegisManager.decrypt_data (vault, key);

        assert_nonnull (decrypted);
        assert_cmpint (decrypted.length, CompareOperator.EQ, plaintext.data.length);

        var builder = new StringBuilder ();
        builder.append_len ((string) decrypted, decrypted.length);
        assert_cmpstr (builder.str, CompareOperator.EQ, plaintext);
    }

    private AegisVault export_sample () {
        try {
            var json = AegisManager.create_encrypted_vault_json (sample_content (), PASSPHRASE);

            return AegisManager.parse_vault (parse (json));
        } catch (Error e) {
            Test.message ("export failed: %s", e.message);
            Test.fail ();
            assert_not_reached ();
        }
    }

    private void test_encrypted_roundtrip () {
        var vault = export_sample ();

        assert_true (AegisManager.is_vault_encrypted (vault));

        var content = AegisManager.unlock_vault (vault, PASSPHRASE);

        assert_nonnull (content);
        assert_sample_content (content);
    }

    // The export must be readable by Aegis, so check the layout it expects
    private void test_vault_layout () {
        var json = AegisManager.create_encrypted_vault_json (sample_content (), PASSPHRASE);
        var root = parse (json).get_object ();

        assert_cmpint ((int) root.get_int_member ("version"), CompareOperator.EQ, 1);
        assert_true (root.has_member ("db"));

        var header = root.get_object_member ("header");
        var params = header.get_object_member ("params");
        assert_cmpint (params.get_string_member ("nonce").length, CompareOperator.EQ, 24);
        assert_cmpint (params.get_string_member ("tag").length, CompareOperator.EQ, 32);

        var slots = header.get_array_member ("slots");
        assert_cmpint ((int) slots.get_length (), CompareOperator.EQ, 1);

        var slot = slots.get_object_element (0);
        assert_cmpint ((int) slot.get_int_member ("type"), CompareOperator.EQ, 1);
        assert_cmpint ((int) slot.get_int_member ("n"), CompareOperator.EQ, 32768);
        assert_cmpint ((int) slot.get_int_member ("r"), CompareOperator.EQ, 8);
        assert_cmpint ((int) slot.get_int_member ("p"), CompareOperator.EQ, 1);
        assert_cmpint (slot.get_string_member ("salt").length, CompareOperator.EQ, 64);
        assert_true (slot.get_boolean_member ("repaired"));
        assert_true (slot.has_member ("key_params"));
        assert_false (slot.has_member ("key-params"));
        assert_false (slot.has_member ("slot-type"));

        // the decrypted database uses Aegis' member names too
        var content = AegisManager.unlock_vault (AegisManager.parse_vault (parse (json)), PASSPHRASE);
        var db_json = content_to_json (content);
        var entry = parse (db_json).get_object ().get_array_member ("entries").get_object_element (0);
        assert_cmpstr (entry.get_string_member ("type"), CompareOperator.EQ, "totp");
        assert_false (entry.has_member ("entry-type"));
    }

    private void test_wrong_password () {
        var vault = export_sample ();

        // a failed GCM tag check is logged as critical
        Test.expect_message (null, LogLevelFlags.LEVEL_CRITICAL, "*");

        assert_null (AegisManager.unlock_vault (vault, "not the password"));

        Test.assert_expected_messages ();
    }

    private void test_tampered_data () {
        var vault = export_sample ();

        var data = Base64.decode (vault.db);
        data[0] = data[0] ^ 0xff;
        vault.db = Base64.encode (data);

        Test.expect_message (null, LogLevelFlags.LEVEL_CRITICAL, "*");

        assert_null (AegisManager.unlock_vault (vault, PASSPHRASE));

        Test.assert_expected_messages ();
    }

    private void test_unique_salts () {
        var first = export_sample ();
        var second = export_sample ();

        var slot_one = AegisManager.get_password_slot (first);
        var slot_two = AegisManager.get_password_slot (second);

        assert_cmpstr (slot_one.salt, CompareOperator.NE, slot_two.salt);
        assert_cmpstr (slot_one.key_params.nonce, CompareOperator.NE, slot_two.key_params.nonce);
        assert_cmpstr (first.db, CompareOperator.NE, second.db);
    }

    private void test_password_slot_lookup () {
        var vault = new AegisVault ();
        vault.header = new AegisVault.AegisHeader ();
        vault.header.slots = new Gee.ArrayList<AegisVault.AegisRawSlot> ();

        assert_null (AegisManager.get_password_slot (vault));

        var raw = new AegisVault.AegisRawSlot ();
        raw.slot_type = 0;
        var password = new AegisVault.AegisPasswordSlot ();

        vault.header.slots.add (raw);
        vault.header.slots.add (password);

        assert_true (AegisManager.get_password_slot (vault) == password);
    }

    private void test_slot_types () {
        var json = """{"version": 1, "header": {"slots": [
            {"type": 0, "uuid": "a", "key": "00", "key_params": {"nonce": "aa", "tag": "bb"}, "repaired": true},
            {"type": 1, "uuid": "b", "key": "11", "key_params": {"nonce": "cc", "tag": "dd"}, "n": 32768, "r": 8, "p": 1, "salt": "ee", "repaired": true},
            {"type": 2, "uuid": "c", "key": "22", "key_params": {"nonce": "ff", "tag": "00"}, "repaired": false}
        ], "params": {"nonce": "aa", "tag": "bb"}}, "db": ""}""";

        var vault = AegisManager.parse_vault (parse (json));
        var slots = vault.header.slots;

        assert_cmpint (slots.size, CompareOperator.EQ, 3);
        assert_false (slots[0] is AegisVault.AegisPasswordSlot);
        assert_cmpint (slots[0].slot_type, CompareOperator.EQ, 0);
        assert_cmpstr (slots[0].key_params.nonce, CompareOperator.EQ, "aa");

        assert_true (slots[1] is AegisVault.AegisPasswordSlot);
        var password = (AegisVault.AegisPasswordSlot) slots[1];
        assert_cmpint (password.n, CompareOperator.EQ, 32768);
        assert_cmpstr (password.salt, CompareOperator.EQ, "ee");

        assert_cmpint (slots[2].slot_type, CompareOperator.EQ, 2);
        assert_false (slots[2].repaired);
    }
}
