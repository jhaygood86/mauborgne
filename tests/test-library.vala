namespace LibraryTests {

    public void register () {
        Test.add_func ("/library/loads_existing_pads", test_loads_existing);
        Test.add_func ("/library/loads_issuer_names", test_loads_issuer_names);
        Test.add_func ("/library/default_is_singleton", test_singleton);
        Test.add_func ("/library/get_pad", test_get_pad);
        Test.add_func ("/library/issuer_display_name", test_issuer_display_name);
        Test.add_func ("/library/add_and_save", test_add_and_save);
        Test.add_func ("/library/save_ignores_unknown_pad", test_save_unknown_pad);
        Test.add_func ("/library/content_changed_on_add_and_edit", test_content_changed);
        Test.add_func ("/library/saving_unchanged_pad_is_not_a_change", test_save_unchanged);
        Test.add_func ("/library/add_stamps_new_pads", test_add_stamps);
        Test.add_func ("/library/add_cancels_tombstone", test_add_cancels_tombstone);
        Test.add_func ("/library/tombstones_are_stored_escaped", test_tombstone_file);
        Test.add_func ("/library/old_tombstones_are_pruned", test_prune);
        Test.add_func ("/library/loads_stored_tombstones", test_loads_tombstones);
        Test.add_func ("/library/secret_service_remove_leaves_tombstone", test_remove_tombstone);
        Test.add_func ("/library/secret_service_sync_snapshot_and_apply", test_snapshot_and_apply);
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

    private void test_loads_tombstones () {
        // written by the fixtures before the library started; the key is escaped on disk
        assert_true (library ().deleted.has_key ("Fixture Gone:old@example.com"));
        assert_true (library ().deleted["Fixture Gone:old@example.com"] == 1799999999000);
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

    private void save_pad (OneTimePad pad) {
        var waiter = new TestSupport.Waiter ();

        library ().save.begin (pad, (obj, res) => {
            library ().save.end (res);
            waiter.done ();
        });

        waiter.wait ();
    }

    private void test_content_changed () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "ChangedIssuer", "changed@example.com");

        var changes = 0;
        var handler = library ().content_changed.connect (() => { changes++; });

        add_pad (pad);
        assert_cmpint (changes, CompareOperator.EQ, 1);

        // an edit made by the user
        pad.note = "edited";
        pad.touch ();
        save_pad (pad);
        assert_cmpint (changes, CompareOperator.EQ, 2);

        library ().disconnect (handler);
    }

    // the code on screen is saved every second; that must not look like an edit
    private void test_save_unchanged () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "RefreshIssuer", "refresh@example.com");
        add_pad (pad);

        var changes = 0;
        var handler = library ().content_changed.connect (() => { changes++; });

        save_pad (pad);
        save_pad (pad);

        library ().disconnect (handler);
        assert_cmpint (changes, CompareOperator.EQ, 0);
    }

    private void test_add_stamps () {
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "StampIssuer", "stamp@example.com");
        assert_true (pad.modified_at == 0);

        var before = OneTimePad.now_ms ();
        add_pad (pad);

        assert_true (pad.modified_at >= before);

        // a pad that already has a time (restored from a backup) keeps it
        var restored = TestSupport.make_pad (OneTimePadType.TOTP, "StampIssuer", "restored@example.com");
        restored.modified_at = 1700000000000;
        add_pad (restored);

        assert_true (restored.modified_at == 1700000000000);
    }

    private void test_add_cancels_tombstone () {
        library ().deleted["BackIssuer:back@example.com"] = OneTimePad.now_ms () - 1000;

        add_pad (TestSupport.make_pad (OneTimePadType.TOTP, "BackIssuer", "back@example.com"));

        assert_false (library ().deleted.has_key ("BackIssuer:back@example.com"));
    }

    // key file keys cannot hold every character an issuer name can
    private void test_tombstone_file () {
        var recent = OneTimePad.now_ms () - 1000;
        library ().deleted["We=ird [issuer]:ac count"] = recent;

        // pruning an expired entry rewrites the file
        library ().deleted["Ancient:pad"] = 1;
        library ().prune_deleted ();

        var path = data_file ("deleted.txt");
        assert_true (FileUtils.test (path, FileTest.EXISTS));

        var key_file = new KeyFile ();

        try {
            key_file.load_from_file (path, KeyFileFlags.NONE);
            assert_true (key_file.has_group ("Deleted"));

            foreach (var key in key_file.get_keys ("Deleted")) {
                assert_false (key.contains ("="));
                assert_false (key.contains (" "));
                assert_false (key.contains ("["));
            }

            assert_true (key_file.get_int64 ("Deleted", Uri.escape_string ("We=ird [issuer]:ac count", null, true)) == recent);
            assert_false (key_file.has_key ("Deleted", "Ancient%3Apad"));
        } catch (Error e) {
            Test.message ("could not read deleted.txt: %s", e.message);
            Test.fail ();
        }
    }

    private void test_prune () {
        var now = OneTimePad.now_ms ();

        library ().deleted["OldGone:a"] = now - OneTimePadLibrary.TOMBSTONE_LIFETIME_MS - 5000;
        library ().deleted["NewGone:b"] = now - 5000;

        library ().prune_deleted (now);

        assert_false (library ().deleted.has_key ("OldGone:a"));
        assert_true (library ().deleted.has_key ("NewGone:b"));
    }

    private SyncSnapshot take_snapshot () {
        SyncSnapshot? result = null;
        var waiter = new TestSupport.Waiter ();

        library ().create_sync_snapshot.begin ((obj, res) => {
            result = library ().create_sync_snapshot.end (res);
            waiter.done ();
        });

        waiter.wait ();

        return result;
    }

    private void apply (SyncSnapshot merged, SyncSnapshot local) {
        var waiter = new TestSupport.Waiter ();

        library ().apply_sync.begin (merged, local, (obj, res) => {
            library ().apply_sync.end (res);
            waiter.done ();
        });

        waiter.wait ();
    }

    /** Needs MAURBORGNE_TEST_SECRET_SERVICE=1 and an unlocked keyring. */
    private void test_remove_tombstone () {
        if (!TestSupport.secret_service_enabled ()) {
            Test.skip ("no usable Secret Service (set MAURBORGNE_TEST_SECRET_SERVICE=1)");
            return;
        }

        var account = "tomb-%u".printf (Random.next_int ());
        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", account);
        pad.secret = TestSupport.SHA1_SECRET;
        add_pad (pad);

        var changes = 0;
        var handler = library ().content_changed.connect (() => { changes++; });

        var before = OneTimePad.now_ms ();
        var waiter = new TestSupport.Waiter ();
        library ().remove.begin (pad, (obj, res) => {
            library ().remove.end (res);
            waiter.done ();
        });
        waiter.wait ();

        library ().disconnect (handler);

        assert_null (library ().get_pad ("MauborgneTest", account));
        assert_true (library ().deleted.has_key ("MauborgneTest:" + account));
        assert_true (library ().deleted["MauborgneTest:" + account] >= before);
        assert_cmpint (changes, CompareOperator.EQ, 1);
    }

    /** Needs MAURBORGNE_TEST_SECRET_SERVICE=1 and an unlocked keyring. */
    private void test_snapshot_and_apply () {
        if (!TestSupport.secret_service_enabled ()) {
            Test.skip ("no usable Secret Service (set MAURBORGNE_TEST_SECRET_SERVICE=1)");
            return;
        }

        var account = "apply-%u".printf (Random.next_int ());
        var local_pad = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", account);
        local_pad.secret = TestSupport.SHA1_SECRET;
        local_pad.modified_at = 100;
        add_pad (local_pad);
        local_pad.modified_at = 100;

        var local = take_snapshot ();

        // the snapshot holds detached copies with the secrets from the keyring
        var mine = find_in (local, "MauborgneTest:" + account);
        assert_nonnull (mine);
        assert_cmpstr (mine.secret, CompareOperator.EQ, TestSupport.SHA1_SECRET);
        assert_true (mine.pad != local_pad);

        // another device edited the pad and added one of its own
        var remote = new SyncSnapshot ();
        var edited = new OneTimePad.clone_of (local_pad);
        edited.note = "edited elsewhere";
        edited.modified_at = 500;
        remote.pads.add (new SyncPad (edited, TestSupport.SHA1_SECRET));

        var added = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", account + "-new");
        added.modified_at = 600;
        remote.pads.add (new SyncPad (added, TestSupport.SHA1_SECRET));

        var merged = Mauborgne.SyncMerge.merge (local, remote, OneTimePad.now_ms ());

        var changes = 0;
        var handler = library ().content_changed.connect (() => { changes++; });

        apply (merged, local);

        library ().disconnect (handler);

        // applying sync results is not a user change, so it must not trigger another sync
        assert_cmpint (changes, CompareOperator.EQ, 0);

        // the existing pad object was updated in place, the new one added
        var updated = library ().get_pad ("MauborgneTest", account);
        assert_true (updated == local_pad);
        assert_cmpstr (updated.note, CompareOperator.EQ, "edited elsewhere");
        assert_true (updated.modified_at == 500);
        assert_nonnull (library ().get_pad ("MauborgneTest", account + "-new"));

        // sync drops pads the merge dropped, without leaving tombstones of its own
        apply (new SyncSnapshot (), take_snapshot ());

        assert_null (library ().get_pad ("MauborgneTest", account));
        assert_null (library ().get_pad ("MauborgneTest", account + "-new"));
        assert_false (library ().deleted.has_key ("MauborgneTest:" + account));
    }

    private SyncPad? find_in (SyncSnapshot snapshot, string identity) {
        foreach (var one in snapshot.pads) {
            if (one.pad.identity == identity) {
                return one;
            }
        }

        return null;
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
