namespace LibraryTests {

    public void register () {
        Test.add_func ("/library/loads_existing_pads", test_loads_existing);
        Test.add_func ("/library/loads_issuer_names", test_loads_issuer_names);
        Test.add_func ("/library/default_is_singleton", test_singleton);
        Test.add_func ("/library/get_pad", test_get_pad);
        Test.add_func ("/library/issuer_display_name", test_issuer_display_name);
        Test.add_func ("/library/add_and_save", test_add_and_save);
        Test.add_func ("/library/save_ignores_unknown_pad", test_save_unknown_pad);
        Test.add_func ("/library/secret_service_add_replace_remove", test_add_replace_remove);
    }

    private OneTimePadLibrary library () {
        return OneTimePadLibrary.get_default ();
    }

    private void add_pad (OneTimePad pad) {
        var waiter = new TestSupport.Waiter ();

        library ().add.begin (pad, (obj, res) => {
            library ().add.end (res);
            waiter.done ();
        });

        waiter.wait ();
    }

    private string data_file (string name) {
        return Path.build_filename (Environment.get_user_data_dir (), name);
    }

    private void test_loads_existing () {
        var pad = library ().get_pad (TestSupport.FIXTURE_ISSUER, TestSupport.FIXTURE_ACCOUNT);

        assert_nonnull (pad);
        assert_cmpstr (pad.note, CompareOperator.EQ, "fixture note");
        assert_cmpstr (pad.account_name_display, CompareOperator.EQ, "Fixture Account");
        assert_true (pad in library ().get_set ());
    }

    private void test_loads_issuer_names () {
        assert_cmpstr (library ().get_issuer_display_name (TestSupport.FIXTURE_ISSUER), CompareOperator.EQ, "Fixture Display");
    }

    private void test_singleton () {
        assert_true (OneTimePadLibrary.get_default () == OneTimePadLibrary.get_default ());
    }

    private void test_get_pad () {
        assert_null (library ().get_pad ("NoSuchIssuer", "nobody"));
        assert_null (library ().get_pad (TestSupport.FIXTURE_ISSUER, "nobody"));
    }

    private void test_issuer_display_name () {
        // unknown issuers show their own name
        assert_cmpstr (library ().get_issuer_display_name ("Unmapped"), CompareOperator.EQ, "Unmapped");

        var signalled = 0;
        var handler = library ().issuer_display_name_changed.connect (() => { signalled++; });

        library ().set_issuer_display_name ("Unmapped", "Mapped Name");

        library ().disconnect (handler);

        assert_cmpint (signalled, CompareOperator.EQ, 1);
        assert_cmpstr (library ().get_issuer_display_name ("Unmapped"), CompareOperator.EQ, "Mapped Name");

        // persisted next to the pads, alongside the fixture mapping
        var key_file = new KeyFile ();

        try {
            key_file.load_from_file (data_file ("issuers.txt"), KeyFileFlags.NONE);
            assert_cmpstr (key_file.get_string ("Issuer Names", "Unmapped"), CompareOperator.EQ, "Mapped Name");
            assert_cmpstr (key_file.get_string ("Issuer Names", TestSupport.FIXTURE_ISSUER), CompareOperator.EQ, "Fixture Display");
        } catch (Error e) {
            Test.message ("could not read issuers.txt: %s", e.message);
            Test.fail ();
        }
    }

    // Pads without an inline secret never touch the keyring
    private void test_add_and_save () {
        var pad = TestSupport.make_pad (OneTimePadType.HOTP, "AddedIssuer", "added@example.com");
        pad.counter = 3;

        var changes = 0;
        var handler = library ().changed.connect (() => { changes++; });

        add_pad (pad);

        library ().disconnect (handler);

        assert_cmpint (changes, CompareOperator.EQ, 1);
        assert_true (library ().get_pad ("AddedIssuer", "added@example.com") == pad);
        assert_true (FileUtils.test (data_file (pad.get_file_name ()), FileTest.EXISTS));

        // changes are written back to the pad's file
        pad.counter = 4;
        pad.note = "updated";

        var waiter = new TestSupport.Waiter ();
        library ().save.begin (pad, (obj, res) => {
            library ().save.end (res);
            waiter.done ();
        });
        waiter.wait ();

        var key_file = new KeyFile ();

        try {
            key_file.load_from_file (data_file (pad.get_file_name ()), KeyFileFlags.NONE);
            var reloaded = new OneTimePad.from_keyfile (key_file);

            assert_cmpint ((int) reloaded.counter, CompareOperator.EQ, 4);
            assert_cmpstr (reloaded.note, CompareOperator.EQ, "updated");
            assert_true (reloaded.pad_type == OneTimePadType.HOTP);
        } catch (Error e) {
            Test.fail ();
        }
    }

    private void test_save_unknown_pad () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "NeverAdded", "ghost");

        var waiter = new TestSupport.Waiter ();
        library ().save.begin (pad, (obj, res) => {
            library ().save.end (res);
            waiter.done ();
        });
        waiter.wait ();

        assert_false (FileUtils.test (data_file (pad.get_file_name ()), FileTest.EXISTS));
    }

    /** Needs MAURBORGNE_TEST_SECRET_SERVICE=1 and an unlocked keyring. */
    private void test_add_replace_remove () {
        if (!TestSupport.secret_service_enabled ()) {
            Test.skip ("no usable Secret Service (set MAURBORGNE_TEST_SECRET_SERVICE=1)");
            return;
        }

        var account = "library-%u".printf (Random.next_int ());

        var first = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", account);
        first.secret = TestSupport.SHA1_SECRET;
        first.note = "first";
        add_pad (first);

        assert_true (library ().get_pad ("MauborgneTest", account) == first);
        assert_null (first.secret);

        // adding a pad with the same identity replaces the old one
        var second = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", account);
        second.secret = TestSupport.SHA1_SECRET;
        second.note = "second";
        add_pad (second);

        assert_true (library ().get_pad ("MauborgneTest", account) == second);
        assert_false (first in library ().get_set ());

        var waiter = new TestSupport.Waiter ();
        library ().remove.begin (second, (obj, res) => {
            library ().remove.end (res);
            waiter.done ();
        });
        waiter.wait ();

        assert_null (library ().get_pad ("MauborgneTest", account));
        assert_false (FileUtils.test (data_file (second.get_file_name ()), FileTest.EXISTS));
    }
}
