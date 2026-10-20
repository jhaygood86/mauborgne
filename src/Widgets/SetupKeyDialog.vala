public class SetupKeyDialog : Adw.Dialog {
    public signal void save_requested (OneTimePad pad);

    private Adw.EntryRow issuer_name_entry;
    private Adw.EntryRow account_name_entry;
    private Adw.PasswordEntryRow setup_key_entry;
    private Adw.EntryRow note_entry;

    construct {
        title = _("Add Pad From Setup Key");
        content_width = 400;

        issuer_name_entry = new Adw.EntryRow () {
            title = _("Issuer Name")
        };

        account_name_entry = new Adw.EntryRow () {
            title = _("Account Name")
        };

        setup_key_entry = new Adw.PasswordEntryRow () {
            title = _("Setup Key")
        };

        note_entry = new Adw.EntryRow () {
            title = _("Note")
        };

        var group = new Adw.PreferencesGroup ();
        group.add (issuer_name_entry);
        group.add (account_name_entry);
        group.add (setup_key_entry);
        group.add (note_entry);

        var cancel_button = new Gtk.Button.with_label (_("Cancel"));

        var save_button = new Gtk.Button.with_label (_("Save"));
        save_button.add_css_class ("suggested-action");

        var action_area = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            margin_top = 12
        };
        action_area.append (cancel_button);
        action_area.append (save_button);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12
        };
        box.append (group);
        box.append (action_area);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (new Adw.HeaderBar ());
        toolbar_view.content = box;

        child = toolbar_view;
        default_widget = save_button;

        cancel_button.clicked.connect (() => {
            close ();
        });

        save_button.clicked.connect (() => {
            string secret_key = setup_key_entry.text.replace(" ","");

            string issuer_name = issuer_name_entry.text;
            string account_name = account_name_entry.text;
            string note = note_entry.text;

            var pad = new OneTimePad.from_secret_key(issuer_name, account_name, secret_key, note);
            save_requested (pad);

            close ();
        });
    }
}
