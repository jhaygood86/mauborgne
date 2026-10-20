public class CreatePasswordDialog : PasswordPromptDialog {

    private const int MIN_PASSWORD_LENGTH = 8;

    protected Gtk.PasswordEntry confirm_password_entry;

    public CreatePasswordDialog () {
        Object (
            heading: _("Create Password"),
            body: _("Need a password to secure the Aegis vault file"),
            action_label: _("Lock")
        );
    }

    construct {
        confirm_password_entry = new Gtk.PasswordEntry () {
            show_peek_icon = true,
            placeholder_text = _("Confirm Password"),
            hexpand = true
        };
        confirm_password_entry.activate.connect (() => password_entry.activate ());

        entries_box.append (confirm_password_entry);
    }

    protected override string? validate () {
        if (password_entry.text.length < MIN_PASSWORD_LENGTH) {
            return _("Password needs to be at least %d characters").printf (MIN_PASSWORD_LENGTH);
        }

        if (password_entry.text != confirm_password_entry.text) {
            return _("Passwords need to match");
        }

        return null;
    }
}
