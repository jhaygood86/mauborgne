/**
 * Runs the Cloud Backup user flows: status, back up, restore, change password and delete,
 * and the sign-in that stands in front of all of them. All cryptography and networking lives in
 * CloudBackupService; this class only sequences dialogs around it and turns failures into
 * plain-language messages. A port of CloudBackupFlow.cs.
 */
public class CloudBackupFlow : Object {

    /** Restoring a backup older than the last one this device saw (beyond clock skew) asks first. */
    private const int64 REPLAY_TOLERANCE_SECONDS = 5 * 60;

    public Gtk.Window parent { get; construct; }
    public OneTimePadLibrary library { get; construct; }
    public CloudSettings settings { get; construct; }
    public LicenseService licenses { get; construct; }
    public CloudBackupService cloud { get; construct; }
    public CloudSyncService sync { get; construct; }

    /** Set when the user signed in while resolving a license problem, so the entry point can retry. */
    private bool signed_in = false;

    public CloudBackupFlow (Gtk.Window parent, OneTimePadLibrary library, Settings gsettings) {
        var settings = new GSettingsCloudSettings (gsettings);
        var licenses = new LicenseService (new WebViewAuthorizationBrowser (parent), new KeyringLicenseStore ());
        var cloud = new CloudBackupService (Mauborgne.OpaqueFactory.create (), licenses);
        var sync = new CloudSyncService (cloud, library, settings, new KeyringSyncPasswordStore ());

        Object (parent: parent, library: library, settings: settings, licenses: licenses, cloud: cloud, sync: sync);
    }

    public async void show () {
        CloudBackupStatus? status = null;

        do {
            signed_in = false;
            status = null;
            Error? failure = null;

            var busy = begin_busy (_("Contacting Cloud Backup…"));

            try {
                status = yield cloud.get_status ();
            } catch (Error e) {
                failure = e;
            }

            busy.done ();

            if (failure != null) {
                yield report (failure);
            }
        } while (status == null && signed_in); // a failed status because of the license: retry once signed in

        if (status == null) {
            return;
        }

        var menu = new CloudBackupMenuDialog (status, sync.status, sync.is_enabled);

        switch (yield menu.pick (parent)) {
            case CloudBackupChoice.BACK_UP:
                yield back_up (status);
                break;
            case CloudBackupChoice.RESTORE:
                yield restore ();
                break;
            case CloudBackupChoice.CHANGE_PASSWORD:
                yield change_password ();
                break;
            case CloudBackupChoice.DELETE:
                yield delete_backup ();
                break;
            case CloudBackupChoice.SYNC_NOW:
                yield sync_now ();
                break;
            case CloudBackupChoice.TURN_SYNC_ON:
                yield turn_sync_on ();
                break;
            case CloudBackupChoice.TURN_SYNC_OFF:
                sync.disable ();
                break;
            default:
                break;
        }
    }

    // ---- flows ---------------------------------------------------------------------------

    private async void back_up (CloudBackupStatus status) {
        var password = yield ask_password (
            status.registered ? CloudPasswordMode.ENTER : CloudPasswordMode.CREATE,
            status.registered ? _("Back Up") : _("Create Cloud Password"), _("Back Up"));

        if (password == null) {
            return;
        }

        var snapshot = yield library.create_sync_snapshot ();

        if (snapshot.pads.size == 0) {
            yield Mauborgne.CloudUi.show_message (parent, _("Nothing to back up"), _("Add a one time pad first."));
            return;
        }

        CloudBackupInfo info;
        var busy = begin_busy (_("Encrypting and uploading…"));

        try {
            info = yield cloud.back_up (password, snapshot);
        } catch (Error e) {
            busy.done ();
            yield report (e);
            return;
        }

        busy.done ();

        remember (info.backup_id, info.updated_at);

        var sync_note = yield turn_on_sync_after (password);
        var count = snapshot.pads.size;

        yield Mauborgne.CloudUi.show_message (parent, _("Backed up"),
            ngettext ("%d pad backed up securely.", "%d pads backed up securely.", count).printf (count) + sync_note);
    }

    private async void restore () {
        var password = yield ask_password (CloudPasswordMode.ENTER, _("Restore"), _("Restore"));

        if (password == null) {
            return;
        }

        CloudRestoreResult result;
        var download_busy = begin_busy (_("Downloading and decrypting…"));

        try {
            result = yield cloud.restore (password);
        } catch (Error e) {
            download_busy.done ();
            yield report (e);
            return;
        }

        download_busy.done ();

        if (looks_replayed (result) && !(yield Mauborgne.CloudUi.confirm (parent,
                _("Older backup"),
                _("This backup is older than the last one this device saw. The server may have returned an outdated copy."),
                _("Restore Anyway")))) {
            return;
        }

        var busy = begin_busy (_("Restoring your pads…"));

        foreach (var sync_pad in result.snapshot.pads) {
            sync_pad.pad.secret = sync_pad.secret;
            yield library.add (sync_pad.pad);
        }

        busy.done ();

        remember (result.backup_id, result.updated_at);

        var sync_note = yield turn_on_sync_after (password);
        var count = result.snapshot.pads.size;

        yield Mauborgne.CloudUi.show_message (parent, _("Restored"),
            ngettext ("%d pad restored from your backup.", "%d pads restored from your backup.", count).printf (count) + sync_note);
    }

    /** After a manual backup or restore the cloud and this device match, so sync starts from here. */
    private async string turn_on_sync_after (string password) {
        if (sync.is_enabled) {
            // keep the stored password in step (it may have been entered fresh)
            yield sync.enable (password, false);
            return "";
        }

        yield sync.enable (password, false);

        return " " + _("Automatic sync is on: changes now flow between your devices.");
    }

    private async void turn_sync_on () {
        var password = yield ask_password (CloudPasswordMode.ENTER, _("Turn On Sync"), _("Turn On"));

        if (password == null) {
            return;
        }

        var busy = begin_busy (_("Syncing…"));
        yield sync.enable (password);
        busy.done ();

        if (sync.status.state != SyncState.SYNCED) {
            yield Mauborgne.CloudUi.show_message (parent, _("Sync"), sync.status.text);
        }
    }

    private async void sync_now () {
        var busy = begin_busy (_("Syncing…"));
        var status = yield sync.sync_now ();
        busy.done ();

        yield Mauborgne.CloudUi.show_message (parent, _("Sync"), status.text);
    }

    private async void change_password () {
        var dialog = new CloudPasswordDialog (CloudPasswordMode.CHANGE, _("Change Cloud Password"), _("Change Password"));

        if (!(yield dialog.wait_for_response (parent))) {
            return;
        }

        var old_password = dialog.password;
        var new_password = dialog.new_password;
        dialog.force_close ();

        var busy = begin_busy (_("Changing password…"));

        try {
            yield cloud.change_password (old_password, new_password);
        } catch (Error e) {
            busy.done ();
            yield report (e);
            return;
        }

        busy.done ();

        if (sync.is_enabled) {
            // sync logs in with the stored password, which is now out of date
            sync.disable ();
        }

        yield Mauborgne.CloudUi.show_message (parent, _("Password changed"),
            _("Your backup is now protected by the new cloud password. Turn automatic sync back on to use it."));
    }

    private async void delete_backup () {
        if (!(yield Mauborgne.CloudUi.confirm (parent,
                _("Delete cloud backup?"),
                _("This permanently deletes your backup and cloud password from the server. Pads on this device are not affected."),
                _("Delete"), true))) {
            return;
        }

        var password = yield ask_password (CloudPasswordMode.ENTER, _("Delete Cloud Backup"), _("Delete"));

        if (password == null) {
            return;
        }

        var busy = begin_busy (_("Deleting…"));

        try {
            yield cloud.delete_backup (password);
        } catch (Error e) {
            busy.done ();
            yield report (e);
            return;
        }

        busy.done ();

        sync.disable ();
        settings.last_backup_id = null;
        settings.last_backup_updated_at = 0;

        yield Mauborgne.CloudUi.show_message (parent, _("Deleted"), _("Your cloud backup has been deleted."));
    }

    // ---- license sign-in -----------------------------------------------------------------

    /** Opens the sign-up page inside the app. */
    public async void open_signup () {
        var dialog = new WebPageDialog (_("Sign up for Cloud Backup"), Mauborgne.CloudBackupLinks.SIGNUP_URL);
        SourceFunc resume = open_signup.callback;
        var finished = false;

        dialog.closed.connect (() => {
            if (!finished) {
                finished = true;
                resume ();
            }
        });

        dialog.present (parent);
        yield;
    }

    /** Runs the sign-in. True if a license was obtained. */
    private async bool sign_in () {
        string? failure = null;
        var no_entitlement = false;

        try {
            yield licenses.sign_in ();
            return true;
        } catch (Error e) {
            if (e is LicenseSignInError.CANCELLED) {
                return false; // the user knows
            }

            no_entitlement = e is LicenseSignInError.NO_ENTITLEMENT;
            failure = e.message;
        }

        if (no_entitlement) {
            if (yield Mauborgne.CloudUi.prompt_no_subscription (parent)) {
                yield open_signup ();
            }
        } else {
            warning ("Sign-in failed: %s", failure);
            yield Mauborgne.CloudUi.show_message (parent, _("Sign-in failed"), _("We couldn't complete sign-in. Please try again."));
        }

        return false;
    }

    // ---- helpers -------------------------------------------------------------------------

    private async string? ask_password (CloudPasswordMode mode, string heading, string action_label) {
        var dialog = new CloudPasswordDialog (mode, heading, action_label);

        if (!(yield dialog.wait_for_response (parent))) {
            return null;
        }

        var password = dialog.password;
        dialog.force_close ();

        return password;
    }

    private bool looks_replayed (CloudRestoreResult result) {
        return settings.last_backup_updated_at > 0
            && result.updated_at < settings.last_backup_updated_at - REPLAY_TOLERANCE_SECONDS;
    }

    private void remember (string backup_id, int64 updated_at) {
        settings.last_backup_id = backup_id;
        settings.last_backup_updated_at = updated_at;
    }

    private Mauborgne.CloudUi.BusyDialog begin_busy (string busy_text) {
        var busy = new Mauborgne.CloudUi.BusyDialog (_("Cloud Backup"), busy_text);
        busy.show_over (parent);

        return busy;
    }

    private async void report (Error e) {
        if (Mauborgne.CloudBackupErrors.should_offer_signup (e)) {
            switch (yield Mauborgne.CloudUi.prompt_sign_in (parent, e is CloudBackupError.LICENSE_EXPIRED)) {
                case Mauborgne.CloudUi.SignInChoice.SIGN_IN:
                    signed_in = yield sign_in ();
                    break;
                case Mauborgne.CloudUi.SignInChoice.SIGN_UP:
                    yield open_signup ();
                    break;
                default:
                    break;
            }

            return;
        }

        string title, message;

        if (e is CloudBackupError.WRONG_PASSWORD) {
            title = _("Wrong cloud password");
            message = _("That cloud password is incorrect.");
        } else if (e is CloudBackupError.NOT_REGISTERED) {
            title = _("No cloud backup");
            message = _("You haven't set up Cloud Backup yet. Back up first.");
        } else if (e is CloudBackupError.NO_BACKUP) {
            title = _("No backup found");
            message = _("There is no backup stored yet.");
        } else if (e is CloudBackupError.TOO_MANY_ATTEMPTS) {
            title = _("Too many attempts");
            message = _("Please wait a few minutes before trying again.");
        } else if (e is CloudBackupError.TAMPERED) {
            title = _("Backup could not be verified");
            message = _("The downloaded backup failed an integrity check, so it was not restored. Try again, and contact support if it persists.");
        } else if (e is CloudBackupError.NETWORK) {
            title = _("Can't reach Cloud Backup");
            message = _("Check your internet connection and try again.");
        } else if (e is CloudBackupError.UNAVAILABLE) {
            title = _("Cloud Backup unavailable");
            message = _("Cloud Backup isn't available in this build of the app.");
        } else {
            warning ("Cloud Backup error: %s", e.message);
            title = _("Cloud Backup error");
            message = _("Something went wrong talking to Cloud Backup. Please try again.");
        }

        yield Mauborgne.CloudUi.show_message (parent, title, message);
    }
}
