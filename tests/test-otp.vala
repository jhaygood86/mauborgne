namespace OtpTests {

    const string SHA256_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====";
    const string SHA512_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA=";

    public void register () {
        Test.add_func ("/otp/uri_totp_defaults", test_uri_totp_defaults);
        Test.add_func ("/otp/uri_issuer_from_label", test_uri_issuer_from_label);
        Test.add_func ("/otp/uri_issuer_param_wins", test_uri_issuer_param_wins);
        Test.add_func ("/otp/uri_options", test_uri_options);
        Test.add_func ("/otp/uri_hotp_counter", test_uri_hotp_counter);
        Test.add_func ("/otp/uri_percent_encoding", test_uri_percent_encoding);
        Test.add_func ("/otp/uri_label_prefix_removed", test_uri_label_prefix_removed);
        Test.add_func ("/otp/uri_build_roundtrip", test_build_uri_roundtrip);
        Test.add_func ("/otp/uri_build_minimal", test_build_uri_minimal);
        Test.add_func ("/otp/secret_key_defaults", test_secret_key_defaults);
        Test.add_func ("/otp/keyfile_roundtrip", test_keyfile_roundtrip);
        Test.add_func ("/otp/keyfile_legacy_without_additional_data", test_keyfile_legacy);
        Test.add_func ("/otp/keyfile_strips_issuer_prefix", test_keyfile_strips_prefix);
        Test.add_func ("/otp/aegis_entry_roundtrip", test_aegis_entry_roundtrip);
        Test.add_func ("/otp/aegis_entry_unknown_type", test_aegis_unknown_type);
        Test.add_func ("/otp/names_file_names", test_file_names);
        Test.add_func ("/otp/names_variant_identifier", test_variant_identifier);
        Test.add_func ("/otp/code_hotp_rfc4226", test_hotp_rfc4226);
        Test.add_func ("/otp/code_totp_rfc6238_sha1", test_totp_rfc6238_sha1);
        Test.add_func ("/otp/code_totp_rfc6238_sha256", test_totp_rfc6238_sha256);
        Test.add_func ("/otp/code_totp_rfc6238_sha512", test_totp_rfc6238_sha512);
        Test.add_func ("/otp/code_totp_current_time", test_totp_current_time);
        Test.add_func ("/otp/code_invalid_secret", test_invalid_secret);
        Test.add_func ("/otp/code_remaining_time", test_remaining_time);
        Test.add_func ("/otp/secret_service_code_and_export", test_secret_service_pad);
    }

    private void test_uri_totp_defaults () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example");

        assert_true (pad.pad_type == OneTimePadType.TOTP);
        assert_cmpstr (pad.issuer, CompareOperator.EQ, "Example");
        assert_cmpstr (pad.account_name, CompareOperator.EQ, "alice@example.com");
        assert_cmpstr (pad.account_name_display, CompareOperator.EQ, "alice@example.com");
        assert_cmpstr (pad.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        assert_true (pad.algorithm == OneTimePadAlgorithm.SHA1);
        assert_cmpint (pad.digits, CompareOperator.EQ, 6);
        assert_cmpint (pad.period, CompareOperator.EQ, 30);
        assert_cmpstr (pad.note, CompareOperator.EQ, "");
    }

    private void test_uri_issuer_from_label () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/Acme:bob?secret=JBSWY3DPEHPK3PXP");

        assert_cmpstr (pad.issuer, CompareOperator.EQ, "Acme");
        assert_cmpstr (pad.account_name, CompareOperator.EQ, "bob");
    }

    private void test_uri_issuer_param_wins () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/Old:bob?secret=JBSWY3DPEHPK3PXP&issuer=New");

        assert_cmpstr (pad.issuer, CompareOperator.EQ, "New");
        // the label still starts with the old issuer, which is only stripped when it matches
        assert_cmpstr (pad.account_name, CompareOperator.EQ, "Old:bob");
    }

    private void test_uri_options () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/Acme:bob?secret=JBSWY3DPEHPK3PXP&issuer=Acme&algorithm=SHA256&digits=8&period=60");

        assert_true (pad.algorithm == OneTimePadAlgorithm.SHA256);
        assert_cmpint (pad.digits, CompareOperator.EQ, 8);
        assert_cmpint (pad.period, CompareOperator.EQ, 60);

        pad = TestSupport.pad_from_uri ("otpauth://totp/Acme:bob?secret=JBSWY3DPEHPK3PXP&issuer=Acme&algorithm=SHA512");
        assert_true (pad.algorithm == OneTimePadAlgorithm.SHA512);
    }

    private void test_uri_hotp_counter () {
        var pad = TestSupport.pad_from_uri ("otpauth://hotp/Acme:bob?secret=JBSWY3DPEHPK3PXP&issuer=Acme&counter=42");

        assert_true (pad.pad_type == OneTimePadType.HOTP);
        assert_cmpint ((int) pad.counter, CompareOperator.EQ, 42);
    }

    private void test_uri_percent_encoding () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/My%20Corp:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=My%20Corp");

        assert_cmpstr (pad.issuer, CompareOperator.EQ, "My Corp");
        assert_cmpstr (pad.account_name, CompareOperator.EQ, "alice@example.com");
    }

    private void test_uri_label_prefix_removed () {
        var pad = TestSupport.pad_from_uri ("otpauth://totp/Acme:bob?secret=JBSWY3DPEHPK3PXP&issuer=Acme");

        assert_cmpstr (pad.account_name, CompareOperator.EQ, "bob");
    }

    private void test_build_uri_roundtrip () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "My Corp", "alice@example.com");
        pad.algorithm = OneTimePadAlgorithm.SHA512;
        pad.digits = 8;
        pad.period = 45;

        var parsed = TestSupport.pad_from_uri (pad.build_uri ("JBSWY3DPEHPK3PXP"));

        assert_true (parsed.pad_type == OneTimePadType.TOTP);
        assert_cmpstr (parsed.issuer, CompareOperator.EQ, "My Corp");
        assert_cmpstr (parsed.account_name, CompareOperator.EQ, "alice@example.com");
        assert_cmpstr (parsed.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        assert_true (parsed.algorithm == OneTimePadAlgorithm.SHA512);
        assert_cmpint (parsed.digits, CompareOperator.EQ, 8);
        assert_cmpint (parsed.period, CompareOperator.EQ, 45);

        // HOTP exports counter + 1 so the next code the other app shows matches ours
        var hotp = TestSupport.make_pad (OneTimePadType.HOTP, "Acme", "bob");
        hotp.counter = 7;

        var parsed_hotp = TestSupport.pad_from_uri (hotp.build_uri ("JBSWY3DPEHPK3PXP"));

        assert_true (parsed_hotp.pad_type == OneTimePadType.HOTP);
        assert_cmpint ((int) parsed_hotp.counter, CompareOperator.EQ, 8);
    }

    private void test_build_uri_minimal () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "bob");
        var uri = pad.build_uri ("JBSWY3DPEHPK3PXP");

        assert_true (uri.has_prefix ("otpauth://totp/Acme:bob?secret=JBSWY3DPEHPK3PXP&issuer=Acme"));
        assert_false (uri.contains ("algorithm="));
        assert_false (uri.contains ("digits="));
        assert_false (uri.contains ("period="));
        assert_false (uri.contains ("counter="));
    }

    private void test_secret_key_defaults () {
        var pad = new OneTimePad.from_secret_key ("Acme", "bob", "JBSWY3DPEHPK3PXP", "my note");

        assert_true (pad.pad_type == OneTimePadType.TOTP);
        assert_cmpstr (pad.issuer, CompareOperator.EQ, "Acme");
        assert_cmpstr (pad.account_name, CompareOperator.EQ, "bob");
        assert_cmpstr (pad.account_name_display, CompareOperator.EQ, "bob");
        assert_cmpstr (pad.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        assert_cmpstr (pad.note, CompareOperator.EQ, "my note");
        assert_true (pad.algorithm == OneTimePadAlgorithm.SHA1);
        assert_cmpint (pad.digits, CompareOperator.EQ, 6);
        assert_cmpint (pad.period, CompareOperator.EQ, 30);
    }

    private void test_keyfile_roundtrip () {
        var pad = TestSupport.make_pad (OneTimePadType.HOTP, "Acme", "bob");
        pad.algorithm = OneTimePadAlgorithm.SHA256;
        pad.digits = 8;
        pad.counter = 99;
        pad.period = 60;
        pad.note = "a note";
        pad.account_name_display = "Bob's account";

        try {
            var loaded = new OneTimePad.from_keyfile (pad.to_keyfile ());

            assert_true (loaded.pad_type == OneTimePadType.HOTP);
            assert_cmpstr (loaded.issuer, CompareOperator.EQ, "Acme");
            assert_cmpstr (loaded.account_name, CompareOperator.EQ, "bob");
            assert_cmpstr (loaded.account_name_display, CompareOperator.EQ, "Bob's account");
            assert_cmpstr (loaded.note, CompareOperator.EQ, "a note");
            assert_true (loaded.algorithm == OneTimePadAlgorithm.SHA256);
            assert_cmpint (loaded.digits, CompareOperator.EQ, 8);
            assert_cmpint ((int) loaded.counter, CompareOperator.EQ, 99);
            assert_cmpint (loaded.period, CompareOperator.EQ, 60);
            // secrets live in the keyring, never in the key file
            assert_null (loaded.secret);
            assert_false (pad.to_keyfile ().has_key ("PadSettings", "Secret"));
        } catch (Error e) {
            Test.fail ();
        }
    }

    private void test_keyfile_legacy () {
        var key_file = new KeyFile ();
        key_file.set_integer ("PadSettings", "PadType", 0);
        key_file.set_string ("PadSettings", "Issuer", "Old");
        key_file.set_string ("PadSettings", "AccountName", "carol");
        key_file.set_string ("PadSettings", "Secret", "JBSWY3DPEHPK3PXP");
        key_file.set_integer ("PadSettings", "Algorithm", 0);
        key_file.set_integer ("PadSettings", "Digits", 6);
        key_file.set_int64 ("PadSettings", "Counter", 0);
        key_file.set_integer ("PadSettings", "Period", 30);

        try {
            var pad = new OneTimePad.from_keyfile (key_file);

            assert_cmpstr (pad.note, CompareOperator.EQ, "");
            assert_cmpstr (pad.account_name_display, CompareOperator.EQ, "carol");
            // old files kept the secret inline; it is migrated into the keyring on first use
            assert_cmpstr (pad.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
        } catch (Error e) {
            Test.fail ();
        }
    }

    private void test_keyfile_strips_prefix () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "Acme:bob");

        assert_cmpstr (pad.account_name, CompareOperator.EQ, "bob");
    }

    private void test_aegis_entry_roundtrip () {
        var totp = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "bob");
        totp.algorithm = OneTimePadAlgorithm.SHA256;
        totp.digits = 8;
        totp.period = 45;
        totp.note = "totp note";

        var entry = totp.build_aegis_vault_entry ("JBSWY3DPEHPK3PXP");
        assert_true (entry is AegisVaultContent.AegisTotpVaultEntry);
        assert_cmpstr (entry.entry_type, CompareOperator.EQ, "totp");

        try {
            var back = new OneTimePad.from_aegis_vault_entry (entry);

            assert_true (back.pad_type == OneTimePadType.TOTP);
            assert_cmpstr (back.issuer, CompareOperator.EQ, "Acme");
            assert_cmpstr (back.account_name, CompareOperator.EQ, "bob");
            assert_cmpstr (back.secret, CompareOperator.EQ, "JBSWY3DPEHPK3PXP");
            assert_true (back.algorithm == OneTimePadAlgorithm.SHA256);
            assert_cmpint (back.digits, CompareOperator.EQ, 8);
            assert_cmpint (back.period, CompareOperator.EQ, 45);
            assert_cmpstr (back.note, CompareOperator.EQ, "totp note");

            var hotp = TestSupport.make_pad (OneTimePadType.HOTP, "Acme", "carol");
            hotp.algorithm = OneTimePadAlgorithm.SHA512;
            hotp.counter = 12;

            var hotp_entry = hotp.build_aegis_vault_entry ("JBSWY3DPEHPK3PXP");
            assert_true (hotp_entry is AegisVaultContent.AegisHotpVaultEntry);
            assert_cmpstr (hotp_entry.entry_type, CompareOperator.EQ, "hotp");

            var hotp_back = new OneTimePad.from_aegis_vault_entry (hotp_entry);

            assert_true (hotp_back.pad_type == OneTimePadType.HOTP);
            assert_true (hotp_back.algorithm == OneTimePadAlgorithm.SHA512);
            assert_cmpint ((int) hotp_back.counter, CompareOperator.EQ, 12);
        } catch (Error e) {
            Test.message ("unexpected error: %s", e.message);
            Test.fail ();
        }
    }

    private class UnknownVaultEntry : AegisVaultContent.AegisVaultEntry {
    }

    private void test_aegis_unknown_type () {
        var entry = new UnknownVaultEntry ();
        entry.issuer = "Acme";
        entry.name = "bob";

        try {
            new OneTimePad.from_aegis_vault_entry (entry);
            Test.fail ();
        } catch (OneTimePadError e) {
            assert_true (e is OneTimePadError.UNKNOWN_PAD_TYPE);
        }
    }

    private void test_file_names () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "bob");

        assert_cmpstr (pad.get_file_name (), CompareOperator.EQ, "Acme_bob.txt");
        assert_cmpstr (pad.get_file_name_with_issuer_in_account_name (), CompareOperator.EQ, "Acme_Acme:bob.txt");
    }

    private void test_variant_identifier () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "bob");

        assert_cmpstr (pad.to_variant_identifier ().print (false), CompareOperator.EQ, "('Acme', 'bob')");
    }

    private void test_hotp_rfc4226 () {
        string[] expected = { "755224", "287082", "359152", "969429", "338314",
                              "254676", "287922", "162583", "399871", "520489" };

        var pad = TestSupport.make_pad (OneTimePadType.HOTP);
        // generating a code advances the counter first, so start one below RFC counter 0
        pad.counter = -1;

        for (int i = 0; i < expected.length; i++) {
            assert_cmpstr (pad.generate_code (TestSupport.SHA1_SECRET), CompareOperator.EQ, expected[i]);
            assert_cmpint ((int) pad.counter, CompareOperator.EQ, i);
        }
    }

    private void assert_totp (OneTimePad pad, string secret, int64 time, string expected) {
        assert_cmpstr (pad.generate_code (secret, time), CompareOperator.EQ, expected);
    }

    private OneTimePad rfc6238_pad (OneTimePadAlgorithm algorithm) {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP);
        pad.algorithm = algorithm;
        pad.digits = 8;
        pad.period = 30;
        return pad;
    }

    private void test_totp_rfc6238_sha1 () {
        var pad = rfc6238_pad (OneTimePadAlgorithm.SHA1);

        assert_totp (pad, TestSupport.SHA1_SECRET, 59, "94287082");
        assert_totp (pad, TestSupport.SHA1_SECRET, 1111111109, "07081804");
        assert_totp (pad, TestSupport.SHA1_SECRET, 1111111111, "14050471");
        assert_totp (pad, TestSupport.SHA1_SECRET, 1234567890, "89005924");
        assert_totp (pad, TestSupport.SHA1_SECRET, 2000000000, "69279037");
        assert_totp (pad, TestSupport.SHA1_SECRET, 20000000000, "65353130");
    }

    private void test_totp_rfc6238_sha256 () {
        var pad = rfc6238_pad (OneTimePadAlgorithm.SHA256);

        assert_totp (pad, SHA256_SECRET, 59, "46119246");
        assert_totp (pad, SHA256_SECRET, 1111111109, "68084774");
    }

    private void test_totp_rfc6238_sha512 () {
        var pad = rfc6238_pad (OneTimePadAlgorithm.SHA512);

        assert_totp (pad, SHA512_SECRET, 59, "90693936");
        assert_totp (pad, SHA512_SECRET, 1111111109, "25091201");
    }

    private void test_totp_current_time () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP);

        var code = pad.generate_code (TestSupport.SHA1_SECRET);

        assert_nonnull (code);
        assert_cmpint (code.length, CompareOperator.EQ, 6);
        assert_true (Regex.match_simple ("^[0-9]{6}$", code));
    }

    private void test_invalid_secret () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP);

        assert_null (pad.generate_code ("not base32 !!!"));
    }

    private void test_remaining_time () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP);

        var remaining = pad.get_remaining_time ();

        assert_true (remaining >= 1 && remaining <= pad.period);

        pad.period = 60;
        remaining = pad.get_remaining_time ();
        assert_true (remaining >= 1 && remaining <= 60);
    }

    /** Needs MAURBORGNE_TEST_SECRET_SERVICE=1 and an unlocked keyring. */
    private void test_secret_service_pad () {
        if (!TestSupport.secret_service_enabled ()) {
            Test.skip ("no usable Secret Service (set MAURBORGNE_TEST_SECRET_SERVICE=1)");
            return;
        }

        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", "secret-service-%u".printf (Random.next_int ()));
        pad.secret = TestSupport.SHA1_SECRET;

        var waiter = new TestSupport.Waiter ();
        string? code = null;
        string? uri = null;
        AegisVaultContent.AegisVaultEntry? entry = null;

        pad.get_otp_code.begin ((obj, res) => {
            code = pad.get_otp_code.end (res);

            // the secret moved to the keyring
            assert_null (pad.secret);

            pad.to_uri.begin ((obj2, res2) => {
                uri = pad.to_uri.end (res2);

                pad.to_aegis_vault_entry.begin ((obj3, res3) => {
                    entry = pad.to_aegis_vault_entry.end (res3);

                    pad.clear_secret.begin ((obj4, res4) => {
                        pad.clear_secret.end (res4);
                        waiter.done ();
                    });
                });
            });
        });

        waiter.wait ();

        assert_true (Regex.match_simple ("^[0-9]{6}$", code));
        assert_true (uri.contains ("secret=" + TestSupport.SHA1_SECRET));
        assert_cmpstr (((AegisVaultContent.AegisTotpVaultEntry) entry).info.secret, CompareOperator.EQ, TestSupport.SHA1_SECRET);
    }
}
