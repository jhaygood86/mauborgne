public class PasswordDialog : PasswordPromptDialog {

    public PasswordDialog () {
        Object (
            heading: _("Password Required"),
            body: _("Need the password to access the Aegis Vault file"),
            action_label: _("Unlock")
        );
    }
}
