public class OneTimePadView : Gtk.Grid {

    public signal void add_code_from_screenshot_clicked ();
    public signal void add_code_from_aegis_clicked ();

    public signal void code_retrieved ();
    public signal void delete_requested (OneTimePad pad);
    public signal void save_requested (OneTimePad pad);

    public signal void export_pad_as_aegis (OneTimePad pad);
    public signal void export_all_pads_as_aegis ();

    public OneTimePad? pad { get; set; }

    Granite.Widgets.Welcome welcome_screen;
    Gtk.Label title_label;
    Gtk.Label subtitle_label;
    Gtk.Label note_label;
    Gtk.ProgressBar code_remaining_progress;
    Gtk.Button edit_button;
    Gtk.Button export_button;
    Gtk.Button delete_button;
    Hdy.HeaderBar codeview_header;

    Gtk.Clipboard? clipboard;

    Gee.List<OneTimePadClipboardOwner> clipboard_owners;

    public bool has_pad { get; set; default = false; }

    construct {
        clipboard_owners = new Gee.ArrayList<OneTimePadClipboardOwner> ();

        codeview_header = new Hdy.HeaderBar () {
            decoration_layout = ":maximize",
            show_close_button = true,
            title = "Mauborgne"
        };

        welcome_screen = new Granite.Widgets.Welcome (_("Add a One Time Pad"),
            _("Add a one time pad from a provider"));

        welcome_screen.append ("screenshot", _("Add Pad From Screenshot"),
            _("Add a pad using a screenshot of a QR code"));

        welcome_screen.append ("aegis", _("Add Pad From Aegis JSON"),
            _("Add a pad using an export of an Aegis encrypted JSON vault file"));

        welcome_screen.activated.connect (welcome_screen_activated);

        title_label = new Gtk.Label (_("One Time Pad"));
        title_label.justify = Gtk.Justification.LEFT;
        title_label.hexpand = true;
        title_label.get_style_context ().add_class (Granite.STYLE_CLASS_H1_LABEL);
        title_label.visible = true;

        subtitle_label = new Gtk.Label (null);
        subtitle_label.justify = Gtk.Justification.CENTER;
        subtitle_label.hexpand = true;
        subtitle_label.wrap = true;
        subtitle_label.wrap_mode = Pango.WrapMode.WORD;
        subtitle_label.visible = true;

        var subtitle_label_context = subtitle_label.get_style_context ();
        subtitle_label_context.add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        subtitle_label_context.add_class (Granite.STYLE_CLASS_H2_LABEL);

        note_label = new Gtk.Label (null);
        note_label.justify = Gtk.Justification.CENTER;
        note_label.hexpand = true;
        note_label.wrap = true;
        note_label.wrap_mode = Pango.WrapMode.WORD;
        note_label.visible = true;

        code_remaining_progress = new Gtk.ProgressBar ();
        code_remaining_progress.show_text = true;
        code_remaining_progress.visible = true;

        var code_remaining_progress_context = code_remaining_progress.get_style_context ();
        code_remaining_progress_context.add_class ("remaining-time");

        attach (codeview_header, 0, 0);
        attach (welcome_screen, 0, 1);

        notify["pad"].connect(() => {
            on_pad_set();
        });

        var copy_button = new Gtk.Button () {
            image = new Gtk.Image.from_icon_name ("edit-copy", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Copy"),
        };

        copy_button.clicked.connect(() => {
            copy_code_to_clipboard ();
        });

        codeview_header.pack_start(copy_button);

        var export_qr_code_menu_item = new Gtk.MenuItem.with_label (_("Export as QR Code")) {
            sensitive = false
        };

        var export_aegis_vault_menu_item = new Gtk.MenuItem.with_label (_("Export this pad as Aegis Vault JSON")) {
            sensitive = false
        };

        var export_all_aegis_vault_menu_item = new Gtk.MenuItem.with_label (_("Export all pads as Aegis Vault JSON"));

        var export_menu = new Gtk.Menu ();
        export_menu.add (export_qr_code_menu_item);
        export_menu.add (export_aegis_vault_menu_item);
        export_menu.add (export_all_aegis_vault_menu_item);
        export_menu.show_all ();

        export_button = new Gtk.MenuButton () {
            image = new Gtk.Image.from_icon_name ("document-export", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Export"),
            popup = export_menu
        };

        export_qr_code_menu_item.activate.connect(() => {
           var export_window = new ExportWindow (pad);
           export_window.show_all ();
        });

        export_aegis_vault_menu_item.activate.connect(() => {
            export_pad_as_aegis (pad);
        });

        export_all_aegis_vault_menu_item.activate.connect(() => {
            export_all_pads_as_aegis ();
        });

        codeview_header.pack_end(export_button);

        delete_button = new Gtk.Button () {
            image = new Gtk.Image.from_icon_name ("edit-delete", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Delete"),
        };

        delete_button.clicked.connect(() => {
            delete_requested (pad);
            pad = null;
        });

        codeview_header.pack_end(delete_button);

        edit_button = new Gtk.Button () {
            image = new Gtk.Image.from_icon_name ("document-edit", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Edit"),
        };

        edit_button.clicked.connect(() => {
            var edit_dialog = new EditDialog (pad);
            edit_dialog.show_all ();

            edit_dialog.save_requested.connect ((pad) => {
                save_requested (pad);
                on_pad_set ();
            });
        });

        codeview_header.pack_end(edit_button);

        bind_property ("has-pad", delete_button, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", export_aegis_vault_menu_item, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", export_qr_code_menu_item, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", copy_button, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", edit_button, "sensitive", BindingFlags.SYNC_CREATE);
    }

    private void welcome_screen_activated (int index) {
        if (index == 0) {
            add_code_from_screenshot_clicked ();
        }

        if (index == 1) {
            add_code_from_aegis_clicked ();
        }
    }

    private void on_pad_set() {

        has_pad = pad != null;

        if (pad == null) {
            switch_to_welcome_screen ();
            return;
        }

        switch_to_code_display ();

        pad.bind_property ("account-name-display", title_label, "label", BindingFlags.SYNC_CREATE);

        codeview_header.subtitle = pad.issuer;
        note_label.label = pad.note;

        switch_to_code_display();
        set_otp_code_label ();

        var current_pad = pad;

        if(pad.pad_type == OneTimePadType.TOTP){

            code_remaining_progress.visible = true;

            Timeout.add(1000,() => {
                if(current_pad == pad){
                    set_otp_code_label ();
                    set_remaining_time ();
                    return true;
                } else {
                    return false;
                }
            });

            set_remaining_time();
        } else {
            code_remaining_progress.visible = false;
        }
    }

    private void set_otp_code_label () {
        get_otp_code.begin((obj,res) => {
            var code = get_otp_code.end (res);
            subtitle_label.label = code;
        });
    }

    private async string? get_otp_code() {
        var code = yield pad.get_otp_code ();

        if (pad != null) {
            code_retrieved ();
            return code;
        }

        return null;
    }

    private void set_remaining_time() {
        var remaining_time = pad.get_remaining_time();

        code_remaining_progress.text = "Code Changes In %d seconds".printf(remaining_time);

        var ratio = ((double)remaining_time) / ((double)pad.period);
        code_remaining_progress.set_fraction(ratio);
    }

    private void copy_code_to_clipboard () {
        if (clipboard == null) {
            clipboard = Gtk.Clipboard.get_default (get_display());
        }

        print("copying code to clipboard\n");

        Gtk.TargetEntry target_entry_utf8 = {"UTF8_STRING", 0, 0};
        Gtk.TargetEntry target_entry_text = {"TEXT", 0, 0};
        Gtk.TargetEntry target_entry_ctext = {"COMPOUND_TEXT", 0, 0};
        Gtk.TargetEntry target_entry_text_plain = {"text/plain", 0, 0};
        Gtk.TargetEntry target_entry_text_plain_utf8 = {"text/plain;charset=utf-8", 0, 0};

        Gtk.TargetEntry[] text_targets = {target_entry_utf8, target_entry_text, target_entry_ctext, target_entry_text_plain, target_entry_text_plain_utf8};

        var owner = new OneTimePadClipboardOwner (pad, subtitle_label.label);
        clipboard_owners.add (owner);

        owner.cancelled.connect(() => {
           clipboard_owners.remove (owner);
        });

        clipboard.set_with_owner(text_targets, clipboard_get_code, clipboard_clear, owner);
    }

    private static void clipboard_get_code (Gtk.Clipboard clipboard, Gtk.SelectionData selection_data, uint info, void* owner) {
        print ("clipboard get code called\n");

        var clipboard_owner = owner as OneTimePadClipboardOwner;

        var code = clipboard_owner.code;

        selection_data.set_text (code, -1);
    }

    private static void clipboard_clear (Gtk.Clipboard clipboard, void* owner) {
        var clipboard_owner = owner as OneTimePadClipboardOwner;
        clipboard_owner.cancel ();
    }

    private void switch_to_code_display() {
        remove (welcome_screen);
        attach (title_label, 0, 1);
        attach (subtitle_label, 0, 2);

        if (pad.note.length > 0) {
            attach (note_label, 0, 3);
        }

        attach (code_remaining_progress, 0, 4);
    }

    private void switch_to_welcome_screen() {
        remove (title_label);
        remove (subtitle_label);
        remove (code_remaining_progress);
        remove (note_label);
        attach (welcome_screen, 0, 1);
    }

    private class OneTimePadClipboardOwner : Object {

        public string code { get; private set; }

        public signal void cancelled ();

        private OneTimePad pad;
        private uint timer = -1;

        public OneTimePadClipboardOwner (OneTimePad pad, string initial_code) {
            this.pad = pad;
            this.code = initial_code;

            if (pad.pad_type == OneTimePadType.TOTP) {
                set_current_code.begin ();

                timer = Timeout.add(1000,() => {
                    set_current_code.begin ();
                    return true;
                });
            }
        }

        private async void set_current_code() {
            code = yield pad.get_otp_code ();
        }

        public void cancel () {
            if (timer > -1) {
                Source.remove (timer);
                timer = -1;
            }

            cancelled ();
        }
    }
}
