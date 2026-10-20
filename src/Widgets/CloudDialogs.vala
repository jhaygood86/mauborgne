/* Small dialogs the Cloud Backup flow needs. All in-window: popovers misbehave under WSLg. */

namespace Mauborgne.CloudUi {

    /** Shows a message with an OK button. */
    public async void show_message (Gtk.Widget parent, string title, string body) {
        var dialog = new Adw.AlertDialog (title, body);
        dialog.add_response ("ok", _("OK"));
        dialog.default_response = "ok";
        dialog.close_response = "ok";

        yield dialog.choose (parent, null);
    }

    /** Asks for confirmation; true if the user chose the action. */
    public async bool confirm (Gtk.Widget parent, string title, string body, string action_label, bool destructive = false) {
        var dialog = new Adw.AlertDialog (title, body);
        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("action", action_label);
        dialog.set_response_appearance ("action", destructive ? Adw.ResponseAppearance.DESTRUCTIVE : Adw.ResponseAppearance.SUGGESTED);
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";

        return (yield dialog.choose (parent, null)) == "action";
    }

    /** A progress dialog the user cannot dismiss; close it with done (). */
    public class BusyDialog : Adw.Dialog {

        public string message { get; construct; }

        public BusyDialog (string title, string message) {
            Object (title: title, message: message);
        }

        construct {
            can_close = false;
            content_width = 360;

            var spinner = new Gtk.Spinner () {
                spinning = true,
                width_request = 32,
                height_request = 32,
                halign = Gtk.Align.CENTER
            };

            var label = new Gtk.Label (message) {
                wrap = true,
                justify = Gtk.Justification.CENTER
            };

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                margin_top = 36,
                margin_bottom = 36,
                margin_start = 24,
                margin_end = 24
            };
            box.append (spinner);
            box.append (label);

            child = box;
        }

        public void show_over (Gtk.Widget parent) {
            present (parent);
        }

        public void done () {
            can_close = true;
            force_close ();
        }
    }

    /** The "sign in or sign up" prompt after a license problem. */
    public enum SignInChoice {
        NOT_NOW,
        SIGN_IN,
        SIGN_UP
    }

    public async SignInChoice prompt_sign_in (Gtk.Widget parent, bool expired) {
        var dialog = new Adw.AlertDialog (
            expired ? _("Your subscription has expired") : _("Sign in to Cloud Backup"),
            expired
                ? _("Sign in again to keep using Cloud Backup, or renew your subscription.")
                : _("Cloud Backup is a subscription service. Sign in with your account, or sign up to get started."));
        dialog.add_response ("not-now", _("Not Now"));
        dialog.add_response ("sign-up", expired ? _("Renew…") : _("Sign Up…"));
        dialog.add_response ("sign-in", _("Sign In…"));
        dialog.set_response_appearance ("sign-in", Adw.ResponseAppearance.SUGGESTED);
        dialog.default_response = "sign-in";
        dialog.close_response = "not-now";

        switch (yield dialog.choose (parent, null)) {
            case "sign-in":
                return SignInChoice.SIGN_IN;
            case "sign-up":
                return SignInChoice.SIGN_UP;
            default:
                return SignInChoice.NOT_NOW;
        }
    }

    /** "No subscription found" after a sign-in. True if the user wants to sign up. */
    public async bool prompt_no_subscription (Gtk.Widget parent) {
        var dialog = new Adw.AlertDialog (
            _("No subscription found"),
            _("This account doesn't have a Cloud Backup subscription yet. You can sign up for one now."));
        dialog.add_response ("close", _("Close"));
        dialog.add_response ("sign-up", _("Sign Up…"));
        dialog.set_response_appearance ("sign-up", Adw.ResponseAppearance.SUGGESTED);
        dialog.default_response = "sign-up";
        dialog.close_response = "close";

        return (yield dialog.choose (parent, null)) == "sign-up";
    }
}

public enum CloudPasswordMode {
    /** Back up, restore or delete with the existing password. */
    ENTER,
    /** First backup: choose a password and confirm it. */
    CREATE,
    /** Replace the password: the current one, then the new one twice. */
    CHANGE
}

/** Asks for the cloud password, following the password policy for new passwords. */
public class CloudPasswordDialog : PasswordPromptDialog {

    public CloudPasswordMode mode { get; construct; }

    protected Gtk.PasswordEntry new_password_entry;
    protected Gtk.PasswordEntry confirm_password_entry;

    public CloudPasswordDialog (CloudPasswordMode mode, string heading, string action_label) {
        Object (
            mode: mode,
            heading: heading,
            body: mode == CloudPasswordMode.CREATE
                ? _("Choose a cloud password. If you forget it, the backup cannot be recovered.")
                : mode == CloudPasswordMode.CHANGE
                    ? _("Enter your current cloud password, then choose a new one.")
                    : _("Enter your cloud password."),
            action_label: action_label
        );
    }

    construct {
        if (mode == CloudPasswordMode.CHANGE) {
            password_entry.placeholder_text = _("Current password");
        }

        if (mode != CloudPasswordMode.ENTER) {
            // in CREATE the first entry already is the new password
            new_password_entry = mode == CloudPasswordMode.CHANGE ? new_entry (_("New password")) : null;
            confirm_password_entry = new_entry (_("Confirm password"));
            confirm_password_entry.activate.connect (() => password_entry.activate ());
        }
    }

    private Gtk.PasswordEntry new_entry (string placeholder) {
        var entry = new Gtk.PasswordEntry () {
            show_peek_icon = true,
            placeholder_text = placeholder,
            hexpand = true
        };

        entries_box.append (entry);

        return entry;
    }

    /** The password to choose (create) or to change to (change). */
    public string new_password {
        owned get {
            return mode == CloudPasswordMode.CHANGE ? new_password_entry.text : password_entry.text;
        }
    }

    protected override string? validate () {
        switch (mode) {
            case CloudPasswordMode.CREATE:
                return Mauborgne.CloudPasswordPolicy.validate_new (password_entry.text, confirm_password_entry.text);
            case CloudPasswordMode.CHANGE:
                return Mauborgne.CloudPasswordPolicy.validate_existing (password_entry.text)
                    ?? Mauborgne.CloudPasswordPolicy.validate_new (new_password_entry.text, confirm_password_entry.text);
            default:
                return Mauborgne.CloudPasswordPolicy.validate_existing (password_entry.text);
        }
    }
}

public enum CloudBackupChoice {
    NONE,
    BACK_UP,
    RESTORE,
    CHANGE_PASSWORD,
    DELETE,
    SYNC_NOW,
    TURN_SYNC_ON,
    TURN_SYNC_OFF
}

/** Cloud Backup home: the status and the things you can do. */
public class CloudBackupMenuDialog : Adw.Dialog {

    public CloudBackupStatus backup_status { get; construct; }
    public SyncStatus sync_status { get; construct; }
    public bool sync_enabled { get; construct; }

    private CloudBackupChoice choice = CloudBackupChoice.NONE;

    public CloudBackupMenuDialog (CloudBackupStatus backup_status, SyncStatus sync_status, bool sync_enabled) {
        Object (title: _("Cloud Backup"), backup_status: backup_status, sync_status: sync_status, sync_enabled: sync_enabled);
    }

    construct {
        content_width = 420;

        var status_text = backup_status.backup_exists
            ? _("Last backup: %s").printf (new DateTime.from_unix_utc (backup_status.updated_at).to_local ().format ("%c"))
            : _("No backup yet");

        var status_group = new Adw.PreferencesGroup ();
        status_group.add (new Adw.ActionRow () {
            title = status_text,
            subtitle = sync_status.text
        });

        var actions = new Adw.PreferencesGroup ();
        actions.add (create_row (_("Back Up Now"), _("Encrypt your pads and upload them"), CloudBackupChoice.BACK_UP));

        if (backup_status.backup_exists) {
            actions.add (create_row (_("Restore From Backup…"), _("Add the pads from your backup to this device"), CloudBackupChoice.RESTORE));
        }

        if (sync_enabled) {
            actions.add (create_row (_("Sync Now"), null, CloudBackupChoice.SYNC_NOW));
            actions.add (create_row (_("Turn Off Automatic Sync"), null, CloudBackupChoice.TURN_SYNC_OFF));
        } else if (backup_status.registered) {
            actions.add (create_row (_("Turn On Automatic Sync…"), _("Keep your devices in step"), CloudBackupChoice.TURN_SYNC_ON));
        }

        var account = new Adw.PreferencesGroup ();

        if (backup_status.registered) {
            account.add (create_row (_("Change Cloud Password…"), null, CloudBackupChoice.CHANGE_PASSWORD));
            account.add (create_row (_("Delete Cloud Backup…"), _("Permanently deletes your backup from the server"), CloudBackupChoice.DELETE));
        }

        var warning = new Gtk.Label (_("If you forget the cloud password, the backup cannot be recovered.")) {
            wrap = true,
            xalign = 0
        };
        warning.add_css_class ("dim-label");
        warning.add_css_class ("caption");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
            margin_top = 12,
            margin_bottom = 18,
            margin_start = 18,
            margin_end = 18
        };
        box.append (status_group);
        box.append (actions);

        if (backup_status.registered) {
            box.append (account);
        }

        box.append (warning);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (new Adw.HeaderBar ());
        toolbar_view.content = new Gtk.ScrolledWindow () {
            child = box,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            propagate_natural_height = true
        };

        child = toolbar_view;
    }

    private Adw.ActionRow create_row (string title, string? subtitle, CloudBackupChoice row_choice) {
        var row = new Adw.ActionRow () {
            title = title,
            subtitle = subtitle,
            activatable = true
        };
        row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        row.activated.connect (() => {
            choice = row_choice;
            close ();
        });

        return row;
    }

    /** Shows the dialog and returns what the user picked, or NONE if they closed it. */
    public async CloudBackupChoice pick (Gtk.Widget parent) {
        SourceFunc resume = pick.callback;
        var finished = false;

        closed.connect (() => {
            if (!finished) {
                finished = true;
                resume ();
            }
        });

        present (parent);
        yield;

        return choice;
    }
}
