public class OneTimePadView : Gtk.Grid {

    public signal void add_code_from_screenshot_clicked ();
    public signal void add_code_from_aegis_clicked ();

    public signal void code_retrieved ();
    public signal void delete_requested (OneTimePad pad);

    public signal void export_pad_as_aegis (OneTimePad pad);
    public signal void export_all_pads_as_aegis ();

    public OneTimePad? pad { get; set; }

    Granite.Widgets.Welcome welcome_screen;
    Gtk.Label title_label;
    Gtk.Label subtitle_label;
    Gtk.ProgressBar code_remaining_progress;
    Gtk.Button export_button;
    Gtk.Button delete_button;
    Hdy.HeaderBar codeview_header;

    public bool has_pad { get; set; default = false; }

    construct {
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

        codeview_header.pack_start(export_button);

        delete_button = new Gtk.Button () {
            image = new Gtk.Image.from_icon_name ("edit-delete", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Delete"),
        };

        delete_button.clicked.connect(() => {
            delete_requested (pad);
            pad = null;
        });

        codeview_header.pack_start(delete_button);

        bind_property ("has-pad", delete_button, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", export_aegis_vault_menu_item, "sensitive", BindingFlags.SYNC_CREATE);
        bind_property ("has-pad", export_qr_code_menu_item, "sensitive", BindingFlags.SYNC_CREATE);
    }

    private async void export_to_aegis_format () {
        AegisVaultContent vault_content = new AegisVaultContent ();
        vault_content.version = 1;
        vault_content.entries = new Gee.ArrayList<AegisVaultContent.AegisVaultEntry> ();

        var aegis_vault_entry = yield pad.to_aegis_vault_entry ();
        vault_content.entries.add (aegis_vault_entry);

        var exported_json = AegisManager.export_to_json_string((Gtk.Window)get_toplevel(), vault_content);

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

        title_label.label = pad.account_name;
        codeview_header.subtitle = pad.issuer;

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

    private void switch_to_code_display() {
        remove(welcome_screen);
        attach(title_label, 0, 1);
        attach(subtitle_label, 0, 2);
        attach(code_remaining_progress, 0, 3);
    }

    private void switch_to_welcome_screen() {
        remove(title_label);
        remove(subtitle_label);
        remove(code_remaining_progress);
        attach (welcome_screen, 0, 1);

        export_button.sensitive = false;
        delete_button.sensitive = false;
    }
}
