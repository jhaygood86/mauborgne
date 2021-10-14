public class PasswordDialog : Granite.MessageDialog {

    private Gtk.Revealer feedback_revealer;
    private Gtk.Entry password_entry;
    private Gtk.Label password_feedback;

    public PasswordDialog (Gtk.Window parent) {
        Object (
            title: _("Aegis Vault Unlock Password"),
            transient_for: parent
        );
    }

    construct {
        var header = new Granite.HeaderLabel (_("Aegis Vault Unlock Password"));

        primary_text = _("Password Required");
        secondary_text = _("Need the password to access the Aegis Vault file");

        password_entry = new Gtk.Entry ();
        password_entry.hexpand = true;
        password_entry.input_purpose = Gtk.InputPurpose.PASSWORD;
        password_entry.primary_icon_name = "dialog-password-symbolic";
        password_entry.primary_icon_tooltip_text = _("Password");
        password_entry.visibility = false;

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
        credentials_grid.attach (feedback_revealer, 0, 3, 1, 1);

        image_icon = new ThemedIcon ("dialog-password");

        if (icon_name != "" && Gtk.IconTheme.get_default ().has_icon (icon_name)) {
            badge_icon = new ThemedIcon (icon_name);
        }

        custom_bin.add (credentials_grid);

        var cancel_button = (Gtk.Button)add_button (_("Cancel"), Gtk.ResponseType.CANCEL);

        var unlock_button = (Gtk.Button)add_button (_("Unlock"), Gtk.ResponseType.ACCEPT);
        unlock_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
        unlock_button.clicked.connect(() => {
            password_entry.secondary_icon_name = "";
            feedback_revealer.reveal_child = false;
        });

        set_default (unlock_button);

        show_all ();

        key_release_event.connect (on_key_release);
    }

    private bool on_key_release (Gdk.EventKey key) {
        switch (key.keyval) {
            case Gdk.Key.KP_Enter:
            case Gdk.Key.Return:
                response (Gtk.ResponseType.ACCEPT);
                return Gdk.EVENT_STOP;
        }

        return Gdk.EVENT_PROPAGATE;
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
