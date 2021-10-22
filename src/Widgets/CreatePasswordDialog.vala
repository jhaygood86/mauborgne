public class CreatePasswordDialog : Granite.MessageDialog {

    private Gtk.Revealer feedback_revealer;
    private Granite.ValidatedEntry password_entry;
    private Granite.ValidatedEntry confirm_password_entry;
    private Gtk.Label password_feedback;

    public CreatePasswordDialog (Gtk.Window parent) {
        Object (
            title: _("Create Aegis Vault Password"),
            transient_for: parent
        );
    }

    construct {
        var header = new Granite.HeaderLabel (_("Create Aegis Vault Password"));

        primary_text = _("Create Password");
        secondary_text = _("Need a password to secure the Aegis vault file");

        password_entry = new Granite.ValidatedEntry ();
        password_entry.hexpand = true;
        password_entry.input_purpose = Gtk.InputPurpose.PASSWORD;
        password_entry.primary_icon_name = "dialog-password-symbolic";
        password_entry.primary_icon_tooltip_text = _("Password");
        password_entry.visibility = false;
        password_entry.changed.connect(on_password_entry_changed);

        confirm_password_entry = new Granite.ValidatedEntry ();
        confirm_password_entry.hexpand = true;
        confirm_password_entry.input_purpose = Gtk.InputPurpose.PASSWORD;
        confirm_password_entry.primary_icon_name = "dialog-password-symbolic";
        confirm_password_entry.primary_icon_tooltip_text = _("Confirm Password");
        confirm_password_entry.visibility = false;
        confirm_password_entry.changed.connect(on_confirm_password_entry_changed);

        password_feedback = new Gtk.Label (null);
        password_feedback.justify = Gtk.Justification.RIGHT;
        password_feedback.max_width_chars = 40;
        password_feedback.wrap = true;
        password_feedback.xalign = 1;
        password_feedback.get_style_context ().add_class (Gtk.STYLE_CLASS_ERROR);

        feedback_revealer = new Gtk.Revealer ();
        feedback_revealer.add (password_feedback);

        var credentials_grid = new Gtk.Grid ();
        credentials_grid.column_spacing = 12;
        credentials_grid.row_spacing = 6;
        credentials_grid.attach (password_entry, 0, 2, 1, 1);
        credentials_grid.attach (confirm_password_entry, 0, 3, 1, 1);
        credentials_grid.attach (feedback_revealer, 0, 4, 1, 1);

        image_icon = new ThemedIcon ("dialog-password");

        if (icon_name != "" && Gtk.IconTheme.get_default ().has_icon (icon_name)) {
            badge_icon = new ThemedIcon (icon_name);
        }

        custom_bin.add (credentials_grid);

        var cancel_button = (Gtk.Button)add_button (_("Cancel"), Gtk.ResponseType.CANCEL);

        var unlock_button = (Gtk.Button)add_button (_("Lock"), Gtk.ResponseType.ACCEPT);
        unlock_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);

        unlock_button.button_press_event.connect ((event) => {
            return validate();
        });

        unlock_button.clicked.connect(() => {
            password_entry.secondary_icon_name = "";
            feedback_revealer.reveal_child = false;
        });

        show_all ();

        key_release_event.connect (on_key_release);
    }

    private void on_password_entry_changed () {
        on_changed (password_entry);
    }

    private void on_confirm_password_entry_changed () {
        on_changed (confirm_password_entry);
    }

    private void on_changed (Granite.ValidatedEntry entry) {
        entry.is_valid = true;

        // Minimum length check
        if (entry.is_valid) {
            entry.is_valid = entry.get_text_length() >= 8;
        }
    }

    private bool on_key_release (Gdk.EventKey key) {
        switch (key.keyval) {
            case Gdk.Key.KP_Enter:
            case Gdk.Key.Return:

                if (validate ()) {
                    response (Gtk.ResponseType.ACCEPT);
                }

                return Gdk.EVENT_STOP;
        }

        return Gdk.EVENT_PROPAGATE;
    }

    private bool validate() {
        if (password_entry.text != confirm_password_entry.text) {
            show_error(_("Passwords need to match"));
            return Gdk.EVENT_STOP;
        } else {
            return Gdk.EVENT_PROPAGATE;
        }
    }

    public void show_error (string error) {
        password_entry.secondary_icon_name = "dialog-error-symbolic";
        password_feedback.label = error;
        feedback_revealer.reveal_child = true;
        shake ();
    }

    private void shake () {
        int x, y;
        get_position (out x, out y);

        for (int n = 0; n < 10; n++) {
            int diff = 15;
            if (n % 2 == 0) {
                diff = -15;
            }

            move (x + diff, y);

            while (Gtk.events_pending ()) {
                Gtk.main_iteration ();
            }

            Thread.usleep (10000);
        }

        move (x, y);
    }

    public string password {
        get {
            return password_entry.text;
        }
    }
}
