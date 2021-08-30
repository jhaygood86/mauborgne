public class OneTimePadView : Gtk.Grid {

    public signal void add_code_from_screenshot_clicked ();
    public signal void code_retrieved ();

    public OneTimePad pad { get; set; }

    Granite.Widgets.Welcome welcome_screen;
    Gtk.Label title_label;
    Gtk.Label subtitle_label;
    Gtk.ProgressBar code_remaining_progress;
    Hdy.HeaderBar codeview_header;

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

        var export_button = new Gtk.Button () {
            image = new Gtk.Image.from_icon_name ("document-export", Gtk.IconSize.LARGE_TOOLBAR),
            tooltip_text = _("Export"),
        };

        export_button.clicked.connect(() => {
            var export_window = new ExportWindow (pad);
            export_window.show_all ();
        });

        codeview_header.pack_start(export_button);
    }

    private void welcome_screen_activated (int index) {
        if (index == 0) {
            add_code_from_screenshot_clicked ();
        }
    }

    private void on_pad_set() {
        switch_to_code_display ();

        title_label.label = pad.account_name;
        codeview_header.subtitle = pad.issuer;

        switch_to_code_display();
        subtitle_label.label = get_otp_code();

        var current_pad = pad;

        if(pad.pad_type == OneTimePadType.TOTP){

            code_remaining_progress.visible = true;

            Timeout.add(1000,() => {
                if(current_pad == pad){
                    subtitle_label.label = get_otp_code();
                    set_remaining_time();
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

    private string get_otp_code() {
        var code = pad.get_otp_code ();
        code_retrieved ();
        return code;
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
}
