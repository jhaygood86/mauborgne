public class EditDialog : Adw.Dialog {

    public signal void save_requested (OneTimePad pad);

    public OneTimePad pad { get; construct; }

    private Adw.EntryRow account_name_entry;
    private Adw.EntryRow note_entry;
    private Adw.SpinRow counter_entry;

    public EditDialog (OneTimePad pad) {
        Object(pad: pad);
    }

    construct {
        title = _("Edit");
        content_width = 400;

        account_name_entry = new Adw.EntryRow () {
            title = _("Account Name"),
            text = pad.account_name_display
        };

        note_entry = new Adw.EntryRow () {
            title = _("Note"),
            text = pad.note
        };

        var group = new Adw.PreferencesGroup ();
        group.add (account_name_entry);
        group.add (note_entry);

        if (pad.pad_type == OneTimePadType.HOTP) {
            counter_entry = new Adw.SpinRow.with_range (0, double.MAX, 1) {
                title = _("Counter"),
                value = pad.counter
            };

            group.add (counter_entry);
        }

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
           pad.account_name_display = account_name_entry.text;
           pad.note = note_entry.text;

           if (pad.pad_type == OneTimePadType.HOTP) {
                int64 counter = (int64)counter_entry.value;
                pad.counter = counter;
           }

           save_requested (pad);

           close ();
        });
    }

}
