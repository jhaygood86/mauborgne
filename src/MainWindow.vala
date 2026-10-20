/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Justin Haygood <jhaygood86@gmail.com>
 */

public class Mauborgne.MainWindow : Adw.ApplicationWindow {
    public MainWindow (Gtk.Application application) {
            Object (
                application: application,
                icon_name: "io.github.jhaygood86.mauborgne",
                title: _("Mauborgne")
            );
    }

    Xdp.Portal portal;
    Gtk.ListBox pad_list;
    OneTimePadLibrary otp_library;
    OneTimePadView onetimepad_view;
    KeyFile brand_mapping_file;
    Settings settings;

    construct {

        settings = new GLib.Settings ("io.github.jhaygood86.mauborgne");

        default_width = settings.get_int ("window-width");
        default_height = settings.get_int ("window-height");

        portal = new Xdp.Portal();

        otp_library = OneTimePadLibrary.get_default ();
        otp_library.changed.connect (bind_pads_to_source_list);

        var brand = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        brand.append (new Gtk.Image.from_icon_name ("io.github.jhaygood86.mauborgne") {
            pixel_size = 24
        });

        var wordmark = new Gtk.Label (_("Mauborgne"));
        wordmark.add_css_class ("pst-wordmark");
        brand.append (wordmark);

        var sidebar_header = new Adw.HeaderBar () {
            show_end_title_buttons = false,
            title_widget = brand
        };

        pad_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.SINGLE
        };
        pad_list.add_css_class ("navigation-sidebar");
        pad_list.row_selected.connect (pad_row_selected);

        var scrolledwindow = new Gtk.ScrolledWindow () {
            vexpand = true,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            child = pad_list
        };

        // A dialog rather than a popover menu: popovers stayed visible on screen after closing under WSLg
        var add_pad_button = new Gtk.Button () {
            child = new Adw.ButtonContent () {
                label = _("Add One Time Pad…"),
                icon_name = "list-add-symbolic"
            },
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 6,
            margin_end = 6
        };
        add_pad_button.add_css_class ("pst-primary");
        add_pad_button.clicked.connect (show_add_pad_dialog);

        var sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        sidebar.append (sidebar_header);
        sidebar.append (scrolledwindow);
        sidebar.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        sidebar.append (add_pad_button);
        sidebar.add_css_class ("pst-sidebar");

        onetimepad_view = new OneTimePadView ();

        onetimepad_view.add_code_from_aegis_clicked.connect(() => {
            add_codes_from_aegis_encrypted_json ();
        });

        onetimepad_view.add_code_from_qr_code_image_clicked.connect(() => {
            add_code_from_qr_code_file ();
        });

        onetimepad_view.add_code_from_setup_key_clicked.connect(() => {
            add_code_from_setup_key ();
        });

        onetimepad_view.code_retrieved.connect(() => {
            otp_library.save.begin(onetimepad_view.pad);
        });

        onetimepad_view.export_pad_as_aegis.connect((pad) => {
            otp_library.export.begin(pad, this, (obj,res) => {
                otp_library.export.end(res);
            });
        });

        onetimepad_view.export_all_pads_as_aegis.connect(() => {
            otp_library.export_all.begin(this, (obj,res) => {
                otp_library.export_all.end(res);
            });
        });

        onetimepad_view.delete_requested.connect((pad) => {
            otp_library.remove.begin(pad, (obj,res) => {
                otp_library.remove.end(res);
                bind_pads_to_source_list ();
            });
        });

        onetimepad_view.save_requested.connect((pad) => {
            otp_library.save.begin(pad, (obj,res) => {
                otp_library.save.end(res);
                bind_pads_to_source_list();
            });
        });

        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
            start_child = sidebar,
            end_child = onetimepad_view,
            resize_start_child = false,
            shrink_start_child = false,
            shrink_end_child = false
        };

        paned.position = settings.get_int ("pad-list-width");

        paned.notify["position"].connect(() => {
           settings.set_int ("pad-list-width", paned.position);
        });

        content = paned;

        brand_mapping_file = new KeyFile ();
        brand_mapping_file.load_from_data_dirs("io.github.jhaygood86.mauborgne/brand_mapping.ini", null, KeyFileFlags.NONE);

        bind_pads_to_source_list();

        close_request.connect(() => {
           settings.set_int("window-width", get_width ());
           settings.set_int("window-height", get_height ());

           return false;
        });
    }

    private void show_add_pad_dialog () {
        var dialog = new Adw.AlertDialog (_("Add One Time Pad"), null) {
            close_response = "cancel"
        };
        dialog.add_response ("cancel", _("Cancel"));
        //dialog.add_response ("screenshot", _("Add Pad From Screenshot"));
        dialog.add_response ("qr-file", _("Add Pad From QR Code Image File"));
        dialog.add_response ("aegis", _("Add Pad(s) From Aegis Encrypted JSON"));
        dialog.add_response ("setup-key", _("Add Pad From Setup Key"));

        dialog.response.connect ((response) => {
            switch (response) {
                case "qr-file":
                    add_code_from_qr_code_file ();
                    break;
                case "aegis":
                    add_codes_from_aegis_encrypted_json ();
                    break;
                case "setup-key":
                    add_code_from_setup_key ();
                    break;
            }
        });

        dialog.present (this);
    }

    private async File? choose_file (string title) {
        var dialog = new Gtk.FileDialog () {
            title = title
        };

        try {
            return yield dialog.open (this, null);
        } catch (Error e) {
            // dismissed by the user
            return null;
        }
    }

    private void add_codes_from_aegis_encrypted_json () {
        add_codes_from_aegis_encrypted_json_async.begin ();
    }

    private async void add_codes_from_aegis_encrypted_json_async () {
        var file = yield choose_file (_("Open Aegis Vault File"));

        if (file != null) {
            var vault = yield AegisManager.import_from_json_file(file.get_path (), this);

            if (vault != null) {
                foreach (var entry in vault.entries) {
                    var otp = new OneTimePad.from_aegis_vault_entry(entry);
                    otp_library.add.begin(otp);
                }
            }
        }
    }

    private void add_code_from_screenshot() {
        acquire_from_screenshot.begin((obj,res) => {
                var qr_code_uri = acquire_from_screenshot.end(res);
                print("screenshot uri: %s\n",qr_code_uri);

                if(qr_code_uri.length > 0){
                    var otp = new OneTimePad.from_uri(qr_code_uri);
                    otp_library.add.begin(otp);
                }
        });
    }

    private void add_code_from_qr_code_file () {
        add_code_from_qr_code_file_async.begin ();
    }

    private async void add_code_from_qr_code_file_async () {
        var file = yield choose_file (_("Open QR Code Image File"));

        if (file != null) {
            var qr_code_uri = acquire_from_file (file);

            if(qr_code_uri.length > 0){
                var otp = new OneTimePad.from_uri(qr_code_uri);
                otp_library.add.begin(otp);
            }
        }
    }

    private void add_code_from_setup_key () {
        var setup_key_dialog = new SetupKeyDialog ();

        setup_key_dialog.save_requested.connect ((otp) => {
            otp_library.add.begin(otp);
        });

        setup_key_dialog.present (this);
    }

    private async string acquire_from_screenshot() {
        try {
            var parent_window = Xdp.parent_new_gtk (this);
            var screenshot_uri = yield portal.take_screenshot(parent_window, Xdp.ScreenshotFlags.INTERACTIVE, null);
            
            var file = File.new_for_uri(screenshot_uri);
            return acquire_from_file (file);
        } catch (GLib.Error error) {
            return "";
        }
    }


    private string acquire_from_file (File file) {
        var file_stream = file.read ();

        var pixbuf = new Gdk.Pixbuf.from_stream (file_stream);

        var payload = QrHelpers.get_payload_from_pixbuf (pixbuf);

        print("payload: %s\n",payload);

        file_stream.close();

        return payload;
    }

    private void bind_pads_to_source_list() {
        pad_list.remove_all ();

        add_section (_("Time-based One Time Pads"), OneTimePadType.TOTP);
        add_section (_("Counter-based One Time Pads"), OneTimePadType.HOTP);
    }

    private void add_section (string title, OneTimePadType pad_type) {
        var issuers = new Gee.ArrayList<string> ();
        var pads_by_issuer = new Gee.HashMap<string, Gee.List<OneTimePad>> ();

        foreach (var pad in otp_library.get_set ()) {
            if (pad.pad_type != pad_type) {
                continue;
            }

            if (!pads_by_issuer.has_key (pad.issuer)) {
                issuers.add (pad.issuer);
                pads_by_issuer[pad.issuer] = new Gee.ArrayList<OneTimePad> ();
            }

            pads_by_issuer[pad.issuer].add (pad);
        }

        var section_label = new Gtk.Label (title.up ()) {
            xalign = 0,
            margin_top = 12,
            margin_bottom = 6,
            margin_start = 10
        };
        section_label.add_css_class ("pst-category");
        pad_list.append (create_header_row (section_label));

        foreach (var issuer in issuers) {
            pad_list.append (create_issuer_row (issuer));

            foreach (var pad in pads_by_issuer[issuer]) {
                var account_label = new Gtk.Label (pad.account_name_display) {
                    xalign = 0,
                    ellipsize = Pango.EllipsizeMode.END,
                    margin_top = 4,
                    margin_bottom = 4,
                    margin_start = 38
                };

                var row = new Gtk.ListBoxRow () {
                    child = account_label
                };
                row.set_data<OneTimePad> ("pad", pad);

                pad_list.append (row);
            }
        }
    }

    private Gtk.ListBoxRow create_header_row (Gtk.Widget child) {
        var row = new Gtk.ListBoxRow () {
            child = child,
            selectable = false,
            activatable = false
        };
        row.add_css_class ("pst-header-row");

        return row;
    }

    private Gtk.ListBoxRow create_issuer_row (string issuer) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            margin_start = 10,
            margin_top = 4,
            margin_bottom = 4
        };

        // a known brand gets its logo, everything else a coloured initials avatar
        var has_icon = false;

        if (brand_mapping_file.has_key("Brand Icons", issuer)) {
            var brand_icon_name = brand_mapping_file.get_string ("Brand Icons", issuer) + "-symbolic";

            if (has_brand_icon(brand_icon_name)) {
                box.append (new Gtk.Image.from_icon_name (brand_icon_name));
                has_icon = true;
            }
        }

        if (!has_icon) {
            box.append (Mauborgne.IssuerAvatar.create (issuer));
        }

        var issuer_label = new Gtk.Label (otp_library.get_issuer_display_name (issuer)) {
            xalign = 0,
            hexpand = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        issuer_label.add_css_class ("pst-issuer");
        box.append (issuer_label);

        var rename_button = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
            tooltip_text = _("Rename")
        };
        rename_button.add_css_class ("flat");
        rename_button.clicked.connect (() => {
            rename_issuer (issuer);
        });
        box.append (rename_button);

        return create_header_row (box);
    }

    private void rename_issuer (string issuer) {
        var entry = new Gtk.Entry () {
            text = otp_library.get_issuer_display_name (issuer),
            activates_default = true
        };

        var dialog = new Adw.AlertDialog (_("Rename Issuer"), null) {
            extra_child = entry,
            default_response = "rename",
            close_response = "cancel"
        };
        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("rename", _("Rename"));
        dialog.set_response_appearance ("rename", Adw.ResponseAppearance.SUGGESTED);

        dialog.response.connect ((response) => {
            if (response == "rename") {
                otp_library.set_issuer_display_name (issuer, entry.text);
            }
        });

        dialog.present (this);
    }

    private void pad_row_selected (Gtk.ListBoxRow? row) {
        if (row == null) {
            return;
        }

        var pad = row.get_data<OneTimePad> ("pad");

        if (pad != null) {
            onetimepad_view.pad = pad;
        }
    }

    private bool has_brand_icon (string brand_icon_name) {
        print ("has brand icon: %s\n", brand_icon_name);

        var icon_theme = Gtk.IconTheme.get_for_display (get_display ());
        return icon_theme.has_icon (brand_icon_name);
    }
}
