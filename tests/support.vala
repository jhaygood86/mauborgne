namespace TestSupport {

    public const string SHA1_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    public const string FIXTURE_ISSUER = "FixtureIssuer";
    public const string FIXTURE_ACCOUNT = "fixture@example.com";

    /** Runs the main loop until the async operation calls done (). */
    public class Waiter : Object {
        private MainLoop loop = new MainLoop ();
        private bool finished = false;

        public void done () {
            finished = true;
            loop.quit ();
        }

        public void wait () {
            if (!finished) {
                // fail rather than hang if something never completes
                var timeout = Timeout.add_seconds (30, () => {
                    Test.fail ();
                    loop.quit ();
                    return false;
                });

                loop.run ();
                Source.remove (timeout);
            }
        }
    }

    public OneTimePad pad_from_uri (string uri) {
        try {
            return new OneTimePad.from_uri (uri);
        } catch (Error e) {
            Test.message ("could not parse %s: %s", uri, e.message);
            Test.fail ();
            assert_not_reached ();
        }
    }

    public OneTimePad make_pad (OneTimePadType type = OneTimePadType.TOTP,
                                string issuer = "Example",
                                string account = "alice@example.com") {
        var key_file = new KeyFile ();
        key_file.set_integer ("PadSettings", "PadType", type);
        key_file.set_string ("PadSettings", "Issuer", issuer);
        key_file.set_string ("PadSettings", "AccountName", account);
        key_file.set_integer ("PadSettings", "Algorithm", OneTimePadAlgorithm.SHA1);
        key_file.set_integer ("PadSettings", "Digits", 6);
        key_file.set_int64 ("PadSettings", "Counter", 0);
        key_file.set_integer ("PadSettings", "Period", 30);

        try {
            return new OneTimePad.from_keyfile (key_file);
        } catch (Error e) {
            Test.fail ();
            assert_not_reached ();
        }
    }

    /** The tests that talk to the Secret Service need a real, unlocked keyring. */
    public bool secret_service_enabled () {
        if (Environment.get_variable ("MAURBORGNE_TEST_SECRET_SERVICE") != "1") {
            return false;
        }

        try {
            Secret.Service.get_sync (Secret.ServiceFlags.NONE, null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    /** Warnings about the session bus and input methods that headless environments always print. */
    public bool is_missing_bus_warning (string? domain, string message) {
        if (domain == "IBUS") {
            return true;
        }

        return message.contains ("session bus") || message.contains ("ibus");
    }

    /** True if a session bus can be reached; WebKit needs one for its sandbox. */
    public bool session_bus_available () {
        try {
            Bus.get_sync (BusType.SESSION, null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    public bool display_available () {
        return Gtk.init_check ();
    }

    /** Pads and issuer names that OneTimePadLibrary should find at start-up. */
    public void write_library_fixtures () {
        var data_dir = Environment.get_user_data_dir ();

        var pad = make_pad (OneTimePadType.TOTP, FIXTURE_ISSUER, FIXTURE_ACCOUNT);
        pad.note = "fixture note";
        pad.account_name_display = "Fixture Account";

        var issuers = new KeyFile ();
        issuers.set_string ("Issuer Names", FIXTURE_ISSUER, "Fixture Display");

        var deleted = new KeyFile ();
        deleted.set_int64 ("Deleted", Uri.escape_string ("Fixture Gone:old@example.com", null, true), 1799999999000);

        try {
            deleted.save_to_file (Path.build_filename (data_dir, "deleted.txt"));
            pad.to_keyfile ().save_to_file (Path.build_filename (data_dir, pad.get_file_name ()));
            issuers.save_to_file (Path.build_filename (data_dir, "issuers.txt"));
        } catch (Error e) {
            error ("could not write fixtures: %s", e.message);
        }
    }
}
