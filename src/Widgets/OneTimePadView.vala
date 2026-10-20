public class OneTimePadView : Gtk.Box {

    public signal void add_code_from_screenshot_clicked ();
    public signal void add_code_from_aegis_clicked ();
    public signal void add_code_from_qr_code_image_clicked ();
    public signal void add_code_from_setup_key_clicked ();

    public signal void code_retrieved ();
    public signal void delete_requested (OneTimePad pad);
    public signal void save_requested (OneTimePad pad);

    public signal void export_pad_as_aegis (OneTimePad pad);
    public signal void export_all_pads_as_aegis ();

    public OneTimePad? pad { get; set; }

    Gtk.Stack stack;
    Gtk.Label title_label;
    Gtk.Label subtitle_label;
    Gtk.Label note_label;
    Gtk.ProgressBar code_remaining_progress;
    Gtk.Button edit_button;
    Gtk.Button delete_button;
    Adw.WindowTitle header_title;
    Adw.HeaderBar codeview_header;

    Gee.List<OneTimePadClipboardOwner> clipboard_owners;

    // the code as generated, without the display grouping
    string current_code = "";

    public bool has_pad { get; set; default = false; }

    construct {
        orientation = Gtk.Orientation.VERTICAL;

        clipboard_owners = new Gee.ArrayList<OneTimePadClipboardOwner> ();

        header_title = new Adw.WindowTitle ("Mauborgne", "");

        codeview_header = new Adw.HeaderBar () {
            title_widget = header_title
        };

        var welcome_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE,
            halign = Gtk.Align.CENTER
        };
        welcome_list.add_css_class ("boxed-list");

        //add_welcome_row (welcome_list, "screenshot", _("Add Pad From Screenshot"),
        //    _("Add a pad using a screenshot of a QR code"));

        add_welcome_row (welcome_list, "aegis", _("Add Pad From Aegis JSON"),
            _("Add a pad using an export of an Aegis encrypted JSON vault file"));

        add_welcome_row (welcome_list, "image-x-generic", _("Add Pad From QR Code Image File"),
            _("Add a pad using an image file that contains a QR Code"));

        add_welcome_row (welcome_list, "dialog-password", _("Add Pad From Setup Key"),
            _("Add a pad using a setup key"));

        welcome_list.row_activated.connect ((row) => welcome_screen_activated (row.get_index ()));

        var welcome_screen = new Adw.StatusPage () {
            title = _("Add a One Time Pad"),
            description = _("Add a one time pad from a provider"),
            icon_name = "io.github.jhaygood86.mauborgne",
            child = welcome_list,
            vexpand = true
        };

        title_label = new Gtk.Label (_("One Time Pad")) {
            justify = Gtk.Justification.LEFT,
            hexpand = true
        };
        title_label.add_css_class ("title-1");

        subtitle_label = new Gtk.Label (null) {
            justify = Gtk.Justification.CENTER,
            hexpand = true,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD,
            selectable = false
        };
        subtitle_label.add_css_class ("pst-code");

        note_label = new Gtk.Label (null) {
            justify = Gtk.Justification.CENTER,
            hexpand = true,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD
        };

        code_remaining_progress = new Gtk.ProgressBar () {
            show_text = true
        };
        code_remaining_progress.add_css_class ("remaining-time");

        var code_view = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            valign = Gtk.Align.CENTER,
            vexpand = true
        };
        code_view.append (title_label);
        code_view.append (subtitle_label);
        code_view.append (note_label);
        code_view.append (code_remaining_progress);

        stack = new Gtk.Stack ();
        stack.add_named (welcome_screen, "welcome");
        stack.add_named (code_view, "code");
        stack.vexpand = true;

        append (codeview_header);
        append (stack);

        notify["pad"].connect(() => {
            on_pad_set();
        });

        var copy_button = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
            tooltip_text = _("Copy"),
        };

        copy_button.clicked.connect(() => {
            copy_code_to_clipboard ();
        });

        codeview_header.pack_start(copy_button);

        // A dialog rather than a popover: the popover stayed visible on screen after closing under WSLg
        var export_button = new Gtk.Button.from_icon_name ("document-send-symbolic") {
            tooltip_text = _("Export")
        };

        export_button.clicked.connect(() => {
            var dialog = new Adw.AlertDialog (_("Export"), null) {
                close_response = "cancel"
            };
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("qr", _("Export as QR Code"));
            dialog.add_response ("aegis", _("Export this pad as Aegis Vault JSON"));
            dialog.add_response ("aegis-all", _("Export all pads as Aegis Vault JSON"));

            dialog.set_response_enabled ("qr", has_pad);
            dialog.set_response_enabled ("aegis", has_pad);

            dialog.response.connect ((response) => {
                switch (response) {
                    case "qr":
                        new ExportWindow (pad).present (this);
                        break;
                    case "aegis":
                        export_pad_as_aegis (pad);
                        break;
                    case "aegis-all":
                        export_all_pads_as_aegis ();
                        break;
                }
            });

            dialog.present (this);
        });

        codeview_header.pack_end(export_button);

        delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
            tooltip_text = _("Delete"),
        };

        delete_button.clicked.connect(() => {
            delete_requested (pad);
            pad = null;
        });

        codeview_header.pack_end(delete_button);

        edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
            tooltip_text = _("Edit"),
        };

        edit_button.clicked.connect(() => {
            var edit_dialog = new EditDialog (pad);

            edit_dialog.save_requested.connect ((pad) => {
                save_requested (pad);
                on_pad_set ();
            });

            edit_dialog.present (this);
        });

        codeview_header.pack_end(edit_button);

        bind_property ("has-pad", delete_button, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", copy_button, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", edit_button, "sensitive", BindingFlags.SYNC_CREATE);
    }

    private void add_welcome_row (Gtk.ListBox list, string icon_name, string title, string subtitle) {
        var row = new Adw.ActionRow () {
            title = title,
            subtitle = subtitle,
            activatable = true
        };
        row.add_prefix (new Gtk.Image.from_icon_name (icon_name));
        row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));

        list.append (row);
    }

    private void welcome_screen_activated (int index) {
        //if (index == 0) {
        //    add_code_from_screenshot_clicked ();
        //}

        if (index == 0) {
            add_code_from_aegis_clicked ();
        }

        if (index == 1) {
            add_code_from_qr_code_image_clicked ();
        }

        if (index == 2) {
            add_code_from_setup_key_clicked ();
        }
    }

    private void on_pad_set() {

        has_pad = pad != null;

        if (pad == null) {
            switch_to_welcome_screen ();
            return;
        }

        var library = OneTimePadLibrary.get_default ();

        library.issuer_display_name_changed.connect(() => {
            header_title.subtitle = library.get_issuer_display_name(pad.issuer);
        });

        pad.bind_property ("account-name-display", title_label, "label", BindingFlags.SYNC_CREATE);

        header_title.subtitle = library.get_issuer_display_name(pad.issuer);
        note_label.label = pad.note;
        note_label.visible = pad.note.length > 0;

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

    // the code turns peach when it is about to change
    private const int EXPIRING_SECONDS = 5;

    /** Splits a code into readable groups: "123456" becomes "123 456". */
    internal static string group_code (string code) {
        var length = code.length;

        if (length < 6 || length > 10) {
            return code;
        }

        // even lengths split in half, odd lengths put the shorter group first
        var first = length / 2;

        return code.substring (0, first) + " " + code.substring (first);
    }

    private void set_otp_code_label () {
        get_otp_code.begin((obj,res) => {
            var code = get_otp_code.end (res);
            current_code = code ?? "";
            subtitle_label.label = group_code (current_code);
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

        code_remaining_progress.text = ngettext ("Code changes in %d second", "Code changes in %d seconds", remaining_time).printf (remaining_time);

        if (remaining_time <= EXPIRING_SECONDS) {
            subtitle_label.add_css_class ("pst-code-expiring");
        } else {
            subtitle_label.remove_css_class ("pst-code-expiring");
        }

        var ratio = ((double)remaining_time) / ((double)pad.period);
        code_remaining_progress.set_fraction(ratio);
    }

    private void copy_code_to_clipboard () {
        print("copying code to clipboard\n");

        var owner = new OneTimePadClipboardOwner (pad, current_code);
        clipboard_owners.add (owner);

        owner.cancelled.connect(() => {
           clipboard_owners.remove (owner);
        });

        get_clipboard ().set_content (owner);
    }

    private void switch_to_code_display() {
        stack.visible_child_name = "code";
    }

    private void switch_to_welcome_screen() {
        header_title.subtitle = "";
        stack.visible_child_name = "welcome";
    }

    private class OneTimePadClipboardOwner : Gdk.ContentProvider {

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

        public override Gdk.ContentFormats ref_formats () {
            return new Gdk.ContentFormats.for_gtype (typeof (string));
        }

        public override bool get_value (ref Value value) throws Error {
            if (value.holds (typeof (string))) {
                value.set_string (code);
                return true;
            }

            return false;
        }

        // called when another clipboard owner replaces this one
        public override void detach_clipboard (Gdk.Clipboard clipboard) {
            cancel ();
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
