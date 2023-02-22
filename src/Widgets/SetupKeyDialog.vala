public class SetupKeyDialog : Hdy.Window {
    public signal void save_requested (OneTimePad pad);

    private Gtk.Entry issuer_name_entry;
    private Gtk.Entry account_name_entry;
    private Gtk.Entry setup_key_entry;
    private Gtk.Entry note_entry;
    
    private Gtk.Button save_button;

    construct {
        default_width = 400;
        
        var grid = new Gtk.Grid () {
            margin = 12,
            orientation = Gtk.Orientation.VERTICAL,
            row_spacing = 6,
            hexpand = true
        };
        
        var issuer_name_label = new Granite.HeaderLabel(_("Issuer Name"));

        issuer_name_entry = new Gtk.Entry () {
            hexpand = true
        };
        
        var account_name_label = new Granite.HeaderLabel(_("Account Name"));

        account_name_entry = new Gtk.Entry () {
            hexpand = true
        };
        
        var setup_key_label = new Granite.HeaderLabel(_("Setup Key"));
        
        setup_key_entry = new Gtk.Entry () {
            hexpand = true
        };

        var note_label = new Granite.HeaderLabel(_("Note"));

        note_entry = new Gtk.Entry () {
            hexpand = true
        };

        grid.add (issuer_name_label);
        grid.add (issuer_name_entry);
        grid.add (account_name_label);
        grid.add (account_name_entry);
        grid.add (setup_key_label);
        grid.add (setup_key_entry);
        grid.add (note_label);
        grid.add (note_entry);
        
        var cancel_button = new Gtk.Button.with_label (_("Cancel"));

        save_button = new Gtk.Button.with_label (_("Save")) {
            can_default = true
        };

        save_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);

        var action_area = new Gtk.ButtonBox (Gtk.Orientation.HORIZONTAL) {
            layout_style = Gtk.ButtonBoxStyle.END,
            margin_top = 24,
            spacing = 6,
            valign = Gtk.Align.END,
            vexpand = true
        };

        action_area.add (cancel_button);
        action_area.add (save_button);

        grid.add (action_area);

        add (grid);

        cancel_button.clicked.connect (() => {
            destroy ();
        });

        save_button.clicked.connect (() => {
            string secret_key = setup_key_entry.text.replace(" ","");
            
            string issuer_name = issuer_name_entry.text;
            string account_name = account_name_entry.text;
            string note = note_entry.text;

            var pad = new OneTimePad.from_secret_key(issuer_name, account_name, secret_key, note);
            save_requested (pad);

            destroy ();
        });
    }
}
