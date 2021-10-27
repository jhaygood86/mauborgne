public class EditDialog : Hdy.Window {

    public signal void save_requested (OneTimePad pad);

    public OneTimePad pad { get; construct; }

    private Gtk.Entry account_name_entry;
    private Gtk.Entry note_entry;
    private Gtk.SpinButton counter_entry;

    private Gtk.Button save_button;

    public EditDialog (OneTimePad pad) {
        Object(pad: pad);
    }

    construct {

        default_width = 400;

        var grid = new Gtk.Grid () {
            margin = 12,
            orientation = Gtk.Orientation.VERTICAL,
            row_spacing = 6,
            hexpand = true
        };

        var account_name_label = new Granite.HeaderLabel(_("Account Name"));

        account_name_entry = new Gtk.Entry () {
            hexpand = true
        };

        var note_label = new Granite.HeaderLabel(_("Note"));

        note_entry = new Gtk.Entry () {
            hexpand = true
        };

        grid.add (account_name_label);
        grid.add (account_name_entry);
        grid.add (note_label);
        grid.add (note_entry);

        if (pad.pad_type == OneTimePadType.HOTP) {
            var counter_label = new Granite.HeaderLabel(_("Counter"));

            counter_entry = new Gtk.SpinButton.with_range (0, double.MAX, 1) {
                hexpand = true,
                input_purpose = Gtk.InputPurpose.NUMBER
            };

            grid.add (counter_label);
            grid.add (counter_entry);
        }


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
           pad.account_name = account_name_entry.text;
           pad.note = note_entry.text;

           if (pad.pad_type == OneTimePadType.HOTP) {
                int64 counter = (int64)counter_entry.value;
                pad.counter = counter;
           }

           save_requested (pad);

           destroy ();
        });

        account_name_entry.text = pad.account_name;
        note_entry.text = pad.note;

        if (pad.pad_type == OneTimePadType.HOTP) {
            counter_entry.value = pad.counter;
        }
    }

}
