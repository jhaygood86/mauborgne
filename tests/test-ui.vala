/*
 * Widget smoke tests. They need a display, so they are skipped on headless
 * builders (e.g. inside the flatpak-builder sandbox).
 */
namespace UiTests {

    private class TestCreatePasswordDialog : CreatePasswordDialog {
        public void fill (string password, string confirmation) {
            password_entry.text = password;
            confirm_password_entry.text = confirmation;
        }

        public string? check () {
            return validate ();
        }

        public void submit_with_enter () {
            password_entry.activate ();
        }
    }

    private class TestPasswordDialog : PasswordDialog {
        public void fill (string password) {
            password_entry.text = password;
        }

        public void submit_with_enter () {
            password_entry.activate ();
        }
    }

    private bool ready = false;
    private Adw.Application? application = null;

    private bool init () {
        if (!ready) {
            if (!TestSupport.display_available ()) {
                return false;
            }

            Adw.init ();

            // WebKit names its sandboxed processes after the default application, which has to be
            // the Flatpak's own id or the portal refuses them. The real app is that application.
            application = new Adw.Application ("io.github.jhaygood86.mauborgne", ApplicationFlags.NON_UNIQUE);

            try {
                application.register (null);
            } catch (Error e) {
                warning ("Could not register the test application: %s", e.message);
            }

            ready = true;
        }

        return true;
    }

    private bool require_display () {
        if (!init ()) {
            Test.skip ("no display available");
            return false;
        }

        return true;
    }

    public void register () {
        Test.add_func ("/ui/create_password_dialog_validation", test_create_password_validation);
        Test.add_func ("/ui/create_password_dialog_submit", test_create_password_submit);
        Test.add_func ("/ui/password_dialog_submit_and_retry", test_password_submit_and_retry);
        Test.add_func ("/ui/password_dialog_dismiss", test_password_dismiss);
        Test.add_func ("/ui/edit_dialog_totp", test_edit_dialog_totp);
        Test.add_func ("/ui/edit_dialog_hotp", test_edit_dialog_hotp);
        Test.add_func ("/ui/setup_key_dialog_construct", test_setup_key_dialog);
        Test.add_func ("/ui/pad_view_welcome_actions", test_pad_view_welcome);
        Test.add_func ("/ui/pad_view_code_grouping", test_code_grouping);
        Test.add_func ("/ui/cloud_password_enter", test_cloud_password_enter);
        Test.add_func ("/ui/cloud_password_create", test_cloud_password_create);
        Test.add_func ("/ui/cloud_password_change", test_cloud_password_change);
        Test.add_func ("/ui/cloud_menu_choices", test_cloud_menu_choices);
        Test.add_func ("/ui/cloud_menu_closed_without_choice", test_cloud_menu_closed);
        Test.add_func ("/ui/cloud_menu_unregistered", test_cloud_menu_unregistered);
        Test.add_func ("/ui/cloud_busy_dialog", test_busy_dialog);
        Test.add_func ("/ui/cloud_authorization_callback", test_parse_callback);
        Test.add_func ("/ui/cloud_web_view_catches_redirect", test_web_view_redirect);
        Test.add_func ("/ui/issuer_avatar_initials", test_avatar_initials);
        Test.add_func ("/ui/issuer_avatar_colors", test_avatar_colors);
        Test.add_func ("/ui/issuer_avatar_widget", test_avatar_widget);
        Test.add_func ("/ui/pad_view_secret_service_shows_pad", test_pad_view_shows_pad);
    }

    private void test_create_password_validation () {
        if (!require_display ()) {
            return;
        }

        var dialog = new TestCreatePasswordDialog ();

        dialog.fill ("short", "short");
        assert_nonnull (dialog.check ());
        assert_true (dialog.check ().contains ("8"));

        dialog.fill ("long enough password", "something different");
        assert_nonnull (dialog.check ());
        assert_true (dialog.check ().contains ("match"));

        dialog.fill ("long enough password", "long enough password");
        assert_null (dialog.check ());
        assert_cmpstr (dialog.password, CompareOperator.EQ, "long enough password");
    }

    private Gtk.Window make_parent () {
        var parent = new Gtk.Window ();
        parent.present ();
        return parent;
    }

    private void test_create_password_submit () {
        if (!require_display ()) {
            return;
        }

        var parent = make_parent ();
        var dialog = new TestCreatePasswordDialog ();
        var waiter = new TestSupport.Waiter ();
        var accepted = false;

        dialog.wait_for_response.begin (parent, (obj, res) => {
            accepted = dialog.wait_for_response.end (res);
            waiter.done ();
        });

        // an invalid submission keeps the dialog waiting
        Idle.add (() => {
            dialog.fill ("short", "short");
            dialog.submit_with_enter ();
            Idle.add (() => {
                dialog.fill ("long enough password", "long enough password");
                dialog.submit_with_enter ();
                return false;
            });
            return false;
        });

        waiter.wait ();

        assert_true (accepted);
        assert_cmpstr (dialog.password, CompareOperator.EQ, "long enough password");

        dialog.force_close ();
        parent.destroy ();
    }

    // The import flow asks again after a wrong password, on the same dialog
    private void test_password_submit_and_retry () {
        if (!require_display ()) {
            return;
        }

        var parent = make_parent ();
        var dialog = new TestPasswordDialog ();
        string[] attempts = {};
        var waiter = new TestSupport.Waiter ();


        dialog.wait_for_response.begin (parent, (obj, res) => {
            if (dialog.wait_for_response.end (res)) {
                attempts += dialog.password;
                dialog.show_error ("wrong password");

                dialog.wait_for_response.begin (parent, (obj2, res2) => {
                    if (dialog.wait_for_response.end (res2)) {
                        attempts += dialog.password;
                    }

                    waiter.done ();
                });

                Idle.add (() => {
                    dialog.fill ("second try");
                    dialog.submit_with_enter ();
                    return false;
                });
            }
        });

        Idle.add (() => {
            dialog.fill ("first try");
            dialog.submit_with_enter ();
            return false;
        });

        waiter.wait ();

        assert_cmpint (attempts.length, CompareOperator.EQ, 2);
        assert_cmpstr (attempts[0], CompareOperator.EQ, "first try");
        assert_cmpstr (attempts[1], CompareOperator.EQ, "second try");

        dialog.force_close ();
        parent.destroy ();
    }

    private void test_password_dismiss () {
        if (!require_display ()) {
            return;
        }

        var parent = make_parent ();
        var dialog = new TestPasswordDialog ();
        var waiter = new TestSupport.Waiter ();
        var accepted = true;

        dialog.wait_for_response.begin (parent, (obj, res) => {
            accepted = dialog.wait_for_response.end (res);
            waiter.done ();
        });

        Idle.add (() => {
            dialog.close ();
            return false;
        });

        waiter.wait ();

        assert_false (accepted);
        parent.destroy ();
    }

    private void test_edit_dialog_totp () {
        if (!require_display ()) {
            return;
        }

        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "Acme", "bob");
        pad.note = "a note";

        var dialog = new EditDialog (pad);

        assert_true (dialog.pad == pad);
    }

    private void test_edit_dialog_hotp () {
        if (!require_display ()) {
            return;
        }

        var pad = TestSupport.make_pad (OneTimePadType.HOTP, "Acme", "bob");
        pad.counter = 17;

        var dialog = new EditDialog (pad);
        var saved = false;

        dialog.save_requested.connect ((saved_pad) => {
            saved = saved_pad == pad;
        });

        assert_true (dialog.pad == pad);
        assert_false (saved);
    }

    private void test_setup_key_dialog () {
        if (!require_display ()) {
            return;
        }

        var dialog = new SetupKeyDialog ();

        assert_nonnull (dialog.child);
    }

    private class TestCloudPasswordDialog : CloudPasswordDialog {
        public TestCloudPasswordDialog (CloudPasswordMode mode) {
            base (mode, "Heading", "Action");
        }

        public void fill (string first, string second = "", string third = "") {
            password_entry.text = first;

            if (mode == CloudPasswordMode.CREATE) {
                confirm_password_entry.text = second;
            } else if (mode == CloudPasswordMode.CHANGE) {
                new_password_entry.text = second;
                confirm_password_entry.text = third;
            }
        }

        public string? check () {
            return validate ();
        }
    }

    private void test_cloud_password_enter () {
        if (!require_display ()) {
            return;
        }

        var dialog = new TestCloudPasswordDialog (CloudPasswordMode.ENTER);

        dialog.fill ("");
        assert_nonnull (dialog.check ());

        // an existing password is not held to the length rule for new ones
        dialog.fill ("short");
        assert_null (dialog.check ());
        assert_cmpstr (dialog.password, CompareOperator.EQ, "short");
    }

    private void test_cloud_password_create () {
        if (!require_display ()) {
            return;
        }

        var dialog = new TestCloudPasswordDialog (CloudPasswordMode.CREATE);

        dialog.fill ("short", "short");
        assert_nonnull (dialog.check ());
        assert_true (dialog.check ().contains ("12"));

        dialog.fill ("a long enough password", "another long password");
        assert_nonnull (dialog.check ());

        dialog.fill ("a long enough password", "a long enough password");
        assert_null (dialog.check ());
        assert_cmpstr (dialog.new_password, CompareOperator.EQ, "a long enough password");
    }

    private void test_cloud_password_change () {
        if (!require_display ()) {
            return;
        }

        var dialog = new TestCloudPasswordDialog (CloudPasswordMode.CHANGE);

        // the current password is required
        dialog.fill ("", "a long enough password", "a long enough password");
        assert_nonnull (dialog.check ());

        // the new one must follow the policy and be confirmed
        dialog.fill ("current", "short", "short");
        assert_nonnull (dialog.check ());
        dialog.fill ("current", "a long enough password", "something else entirely");
        assert_nonnull (dialog.check ());

        dialog.fill ("current", "a long enough password", "a long enough password");
        assert_null (dialog.check ());
        assert_cmpstr (dialog.password, CompareOperator.EQ, "current");
        assert_cmpstr (dialog.new_password, CompareOperator.EQ, "a long enough password");
    }

    private void collect_action_rows (Gtk.Widget widget, Gee.List<Adw.ActionRow> rows) {
        if (widget is Adw.ActionRow) {
            rows.add ((Adw.ActionRow) widget);
        }

        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            collect_action_rows (child, rows);
        }
    }

    private CloudBackupStatus status_of (bool registered, bool exists) {
        return new CloudBackupStatus (registered, exists, exists ? 1700000000 : 0, "cred", exists ? "backup-id" : null);
    }

    private CloudBackupChoice pick_row (CloudBackupMenuDialog dialog, string title) {
        var parent = make_parent ();
        var waiter = new TestSupport.Waiter ();
        var picked = CloudBackupChoice.NONE;

        dialog.pick.begin (parent, (obj, res) => {
            picked = dialog.pick.end (res);
            waiter.done ();
        });

        Idle.add (() => {
            var rows = new Gee.ArrayList<Adw.ActionRow> ();
            collect_action_rows (dialog, rows);

            foreach (var row in rows) {
                if (row.title == title) {
                    row.activated ();
                    break;
                }
            }

            return false;
        });

        waiter.wait ();
        parent.destroy ();

        return picked;
    }

    private void test_cloud_menu_choices () {
        if (!require_display ()) {
            return;
        }

        var sync_off = new SyncStatus (SyncState.OFF, 0, "Sync is off");
        var sync_on = new SyncStatus (SyncState.SYNCED, 1700000000, "Synced just now");

        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_off, false), "Back Up Now") == CloudBackupChoice.BACK_UP);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_off, false), "Restore From Backup…") == CloudBackupChoice.RESTORE);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_off, false), "Turn On Automatic Sync…") == CloudBackupChoice.TURN_SYNC_ON);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_off, false), "Change Cloud Password…") == CloudBackupChoice.CHANGE_PASSWORD);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_off, false), "Delete Cloud Backup…") == CloudBackupChoice.DELETE);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_on, true), "Sync Now") == CloudBackupChoice.SYNC_NOW);
        assert_true (pick_row (new CloudBackupMenuDialog (status_of (true, true), sync_on, true), "Turn Off Automatic Sync") == CloudBackupChoice.TURN_SYNC_OFF);
    }

    private void test_cloud_menu_closed () {
        if (!require_display ()) {
            return;
        }

        var dialog = new CloudBackupMenuDialog (status_of (true, true), new SyncStatus (SyncState.OFF, 0, ""), false);
        var parent = make_parent ();
        var waiter = new TestSupport.Waiter ();
        var picked = CloudBackupChoice.BACK_UP;

        dialog.pick.begin (parent, (obj, res) => {
            picked = dialog.pick.end (res);
            waiter.done ();
        });

        Idle.add (() => {
            dialog.close ();
            return false;
        });

        waiter.wait ();
        parent.destroy ();

        assert_true (picked == CloudBackupChoice.NONE);
    }

    // before anything is set up there is nothing to restore, change or delete
    private void test_cloud_menu_unregistered () {
        if (!require_display ()) {
            return;
        }

        var dialog = new CloudBackupMenuDialog (status_of (false, false), new SyncStatus (SyncState.OFF, 0, ""), false);
        var parent = make_parent ();
        dialog.present (parent);

        var rows = new Gee.ArrayList<Adw.ActionRow> ();
        collect_action_rows (dialog, rows);

        var titles = new Gee.HashSet<string> ();

        foreach (var row in rows) {
            titles.add (row.title);
        }

        assert_true (titles.contains ("Back Up Now"));
        assert_false (titles.contains ("Restore From Backup…"));
        assert_false (titles.contains ("Change Cloud Password…"));
        assert_false (titles.contains ("Delete Cloud Backup…"));
        assert_false (titles.contains ("Turn On Automatic Sync…"));

        dialog.force_close ();
        parent.destroy ();
    }

    private void test_busy_dialog () {
        if (!require_display ()) {
            return;
        }

        var parent = make_parent ();
        var busy = new Mauborgne.CloudUi.BusyDialog ("Title", "Working…");

        busy.show_over (parent);
        // it cannot be dismissed until the work is done
        assert_false (busy.can_close);

        busy.done ();
        parent.destroy ();
    }

    // pure function: runs without a display
    private void test_parse_callback () {
        var ok = WebViewAuthorizationBrowser.parse_callback ("http://127.0.0.1:50000/callback?code=abc%20def&state=xyz");
        assert_cmpstr (ok.code, CompareOperator.EQ, "abc def");
        assert_cmpstr (ok.state, CompareOperator.EQ, "xyz");
        assert_null (ok.error);

        var denied = WebViewAuthorizationBrowser.parse_callback ("http://127.0.0.1:50000/callback?error=access_denied&state=xyz");
        assert_null (denied.code);
        assert_cmpstr (denied.error, CompareOperator.EQ, "access_denied");
        assert_cmpstr (denied.state, CompareOperator.EQ, "xyz");

        var bare = WebViewAuthorizationBrowser.parse_callback ("http://127.0.0.1:50000/callback");
        assert_null (bare.code);
        assert_null (bare.error);
    }

    // the embedded browser stops the navigation to the redirect address and reports it
    private void test_web_view_redirect () {
        if (!require_display ()) {
            return;
        }

        var redirect = "http://127.0.0.1:50000/callback";
        var parent = make_parent ();
        var dialog = new WebPageDialog ("Sign in", "about:blank", redirect);
        var waiter = new TestSupport.Waiter ();
        string? seen = null;

        dialog.redirected.connect ((uri) => {
            seen = uri;
            waiter.done ();
        });

        dialog.present (parent);

        // a page navigating to the redirect address, as the Portal does after sign-in
        Timeout.add (500, () => {
            dialog.run_script_for_test ("window.location = '%s?code=abc&state=xyz';".printf (redirect));
            return false;
        });

        waiter.wait ();

        assert_nonnull (seen);
        assert_true (seen.has_prefix (redirect + "?code=abc"));

        dialog.force_close ();
        parent.destroy ();
    }

    // pure functions: these run without a display
    private void test_code_grouping () {
        assert_cmpstr (OneTimePadView.group_code ("123456"), CompareOperator.EQ, "123 456");
        assert_cmpstr (OneTimePadView.group_code ("12345678"), CompareOperator.EQ, "1234 5678");
        assert_cmpstr (OneTimePadView.group_code ("1234567"), CompareOperator.EQ, "123 4567");
        // too short or too long to be a code, such as an error message, stays as it is
        assert_cmpstr (OneTimePadView.group_code ("1234"), CompareOperator.EQ, "1234");
        assert_cmpstr (OneTimePadView.group_code (""), CompareOperator.EQ, "");
        assert_cmpstr (OneTimePadView.group_code ("Invalid Secret. Please delete"), CompareOperator.EQ, "Invalid Secret. Please delete");
    }

    private void test_avatar_initials () {
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("GitHub"), CompareOperator.EQ, "GI");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("Amazon Web Services"), CompareOperator.EQ, "AW");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("k1x.okta.com"), CompareOperator.EQ, "KO");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("my-company"), CompareOperator.EQ, "MC");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("X"), CompareOperator.EQ, "X");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("\u00e9cole"), CompareOperator.EQ, "\u00c9C");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials (""), CompareOperator.EQ, "?");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials ("   "), CompareOperator.EQ, "?");
        assert_cmpstr (Mauborgne.IssuerAvatar.initials (null), CompareOperator.EQ, "?");
    }

    private void test_avatar_colors () {
        // stable, within the palette, and the same as the Windows app (hash * 31 + char)
        assert_cmpint (Mauborgne.IssuerAvatar.color_index ("GitHub"), CompareOperator.EQ, Mauborgne.IssuerAvatar.color_index ("GitHub"));
        assert_cmpint (Mauborgne.IssuerAvatar.color_index (""), CompareOperator.EQ, 0);
        assert_cmpint (Mauborgne.IssuerAvatar.color_index (null), CompareOperator.EQ, 0);
        // "A" = 65, 65 % 8 = 1; "AB" = 65 * 31 + 66 = 2081, 2081 % 8 = 1
        assert_cmpint (Mauborgne.IssuerAvatar.color_index ("A"), CompareOperator.EQ, 1);
        assert_cmpint (Mauborgne.IssuerAvatar.color_index ("AB"), CompareOperator.EQ, 1);
        // "Google" gives a known slot
        assert_cmpint (Mauborgne.IssuerAvatar.color_index ("Google"), CompareOperator.EQ, expected_color_index ("Google"));

        foreach (var name in new string[] { "GitHub", "Amazon", "Roblox", "NVIDIA", "Carta", "IBMid" }) {
            var index = Mauborgne.IssuerAvatar.color_index (name);
            assert_true (index >= 0 && index < 8);
        }
    }

    // the reference algorithm from the commercial app, written independently
    private int expected_color_index (string text) {
        int64 hash = 0;

        for (int i = 0; i < text.length; i++) {
            hash = (hash * 31 + text[i]) & 0x7FFFFFFF;
        }

        return (int) (hash % 8);
    }

    private void test_avatar_widget () {
        if (!require_display ()) {
            return;
        }

        var avatar = Mauborgne.IssuerAvatar.create ("GitHub");

        assert_true (avatar is Gtk.Label);
        assert_cmpstr (((Gtk.Label) avatar).label, CompareOperator.EQ, "GI");
        assert_true (avatar.has_css_class ("pst-avatar"));
        assert_true (avatar.has_css_class ("pst-avatar-%d".printf (Mauborgne.IssuerAvatar.color_index ("GitHub"))));
    }

    private void collect_rows (Gtk.Widget widget, Gee.List<Gtk.ListBoxRow> rows, out Gtk.ListBox? list) {
        list = null;

        if (widget is Gtk.ListBox) {
            list = (Gtk.ListBox) widget;
        }

        if (widget is Gtk.ListBoxRow) {
            rows.add ((Gtk.ListBoxRow) widget);
        }

        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            Gtk.ListBox? nested;
            collect_rows (child, rows, out nested);

            if (nested != null) {
                list = nested;
            }
        }
    }

    // The three "add a pad" rows on the welcome page raise their signals
    private void test_pad_view_welcome () {
        if (!require_display ()) {
            return;
        }

        var view = new OneTimePadView ();

        assert_false (view.has_pad);

        var rows = new Gee.ArrayList<Gtk.ListBoxRow> ();
        Gtk.ListBox? list;
        collect_rows (view, rows, out list);

        assert_nonnull (list);
        assert_cmpint (rows.size, CompareOperator.EQ, 3);

        var aegis = 0;
        var qr_file = 0;
        var setup_key = 0;
        view.add_code_from_aegis_clicked.connect (() => { aegis++; });
        view.add_code_from_qr_code_image_clicked.connect (() => { qr_file++; });
        view.add_code_from_setup_key_clicked.connect (() => { setup_key++; });

        list.row_activated (rows[0]);
        list.row_activated (rows[1]);
        list.row_activated (rows[2]);

        assert_cmpint (aegis, CompareOperator.EQ, 1);
        assert_cmpint (qr_file, CompareOperator.EQ, 1);
        assert_cmpint (setup_key, CompareOperator.EQ, 1);
    }

    /** Needs MAURBORGNE_TEST_SECRET_SERVICE=1 and an unlocked keyring. */
    private void test_pad_view_shows_pad () {
        if (!require_display ()) {
            return;
        }

        if (!TestSupport.secret_service_enabled ()) {
            Test.skip ("no usable Secret Service (set MAURBORGNE_TEST_SECRET_SERVICE=1)");
            return;
        }

        var pad = TestSupport.make_pad (OneTimePadType.TOTP, "MauborgneTest", "view-%u".printf (Random.next_int ()));
        pad.secret = TestSupport.SHA1_SECRET;

        var view = new OneTimePadView ();
        var retrieved = new TestSupport.Waiter ();
        view.code_retrieved.connect (() => { retrieved.done (); });

        view.pad = pad;
        assert_true (view.has_pad);

        retrieved.wait ();

        view.pad = null;
        assert_false (view.has_pad);

        var cleanup = new TestSupport.Waiter ();
        pad.clear_secret.begin ((obj, res) => {
            pad.clear_secret.end (res);
            cleanup.done ();
        });
        cleanup.wait ();
    }
}
