/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Justin Haygood <jhaygood86@gmail.com>
 */

public class Mauborgne.MainWindow : Hdy.ApplicationWindow {
    public MainWindow (Gtk.Application application) {
            Object (
                application: application,
                icon_name: "com.github.jhaygood86.mauborgne",
                title: _("Mauborgne")
            );
    }
    
    static construct {
        Hdy.init ();
    }
    
    Xdp.Portal portal;
    Granite.Widgets.SourceList source_list;
    OneTimePadLibrary otp_library;
    OneTimePadView onetimepad_view;

    construct {
        portal = new Xdp.Portal();
        
        otp_library = OneTimePadLibrary.get_default ();
        otp_library.changed.connect (bind_pads_to_source_list);
    
        var sidebar_header = new Hdy.HeaderBar () {
            decoration_layout = "close:",
            has_subtitle = false,
            show_close_button = true
        };
        
        unowned Gtk.StyleContext sidebar_header_context = sidebar_header.get_style_context ();
        sidebar_header_context.add_class ("default-decoration");
        sidebar_header_context.add_class (Gtk.STYLE_CLASS_FLAT);
        
        var scrolledwindow = new Gtk.ScrolledWindow (null, null) {
            expand = true,
            hscrollbar_policy = Gtk.PolicyType.NEVER
        };
        
        source_list = new Granite.Widgets.SourceList();
        source_list.item_selected.connect(pad_item_selected);
    
        scrolledwindow.add(source_list);
        
        var add_pad_grid = new Gtk.Grid () {
            margin_top = 3,
            margin_bottom = 3,
            row_spacing = 3
        };

        var add_pad_screenshot_button = new Gtk.ModelButton () {
            label = _("Add Pad From Screenshot")
        };
        
        var add_pad_camera_button = new Gtk.ModelButton () {
            label = _("Add Pad From Camera")
        };
        
        var add_pad_token_button = new Gtk.ModelButton () {
            label = _("Add Pad From Token")
        };
        
        var add_pad_from_aegis_vault = new Gtk.ModelButton () {
            label = _("Add Pad(s) From Aegis Encrypted JSON")
        };

        var add_pad_popover = new Gtk.Popover (null);
        add_pad_popover.add (add_pad_grid);
        
        add_pad_grid.attach (add_pad_screenshot_button, 0, 0);
        add_pad_grid.attach (add_pad_from_aegis_vault, 0, 1);
        add_pad_grid.show_all ();
        
        var add_pad_button = new Gtk.MenuButton () {
            label = _("Add One Time Pad…"),
            image = new Gtk.Image.from_icon_name ("list-add-symbolic", Gtk.IconSize.SMALL_TOOLBAR),
            always_show_image = true,
            popover = add_pad_popover
        };
        
        add_pad_screenshot_button.clicked.connect(acquire_from_screenshot_clicked);
        add_pad_from_aegis_vault.clicked.connect(acquire_from_aegis_encrypted_vault_clicked);

        var actionbar = new Gtk.ActionBar ();
        actionbar.add (add_pad_button);
        
        unowned Gtk.StyleContext actionbar_style_context = actionbar.get_style_context ();
        actionbar_style_context.add_class (Gtk.STYLE_CLASS_FLAT);
        
        var sidebar = new Gtk.Grid ();
        sidebar.attach (sidebar_header, 0, 0);
        sidebar.attach (scrolledwindow, 0, 1);
        sidebar.attach (actionbar, 0, 2);
        
        unowned Gtk.StyleContext sidebar_style_context = sidebar.get_style_context ();
        sidebar_style_context.add_class (Gtk.STYLE_CLASS_SIDEBAR);

        onetimepad_view = new OneTimePadView ();
        
        onetimepad_view.add_code_from_screenshot_clicked.connect(() => {
            add_code_from_screenshot ();
        });
        
        onetimepad_view.add_code_from_aegis_clicked.connect(() => {
            add_codes_from_aegis_encrypted_json ();
        });

        onetimepad_view.code_retrieved.connect(() => {
            otp_library.save(onetimepad_view.pad);
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

        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
        paned.pack1 (sidebar, false, false);
        paned.pack2 (onetimepad_view, true, false);
        
        add (paned);
        
        bind_pads_to_source_list();
    }
    
    private void acquire_from_screenshot_clicked(Gtk.Button button) {
        add_code_from_screenshot ();
    }
    
    private void acquire_from_aegis_encrypted_vault_clicked(Gtk.Button button) {
        add_codes_from_aegis_encrypted_json ();
    }

    private void add_codes_from_aegis_encrypted_json () {
        var chooser = new Gtk.FileChooserNative ("Open Aegis Vault File", this, Gtk.FileChooserAction.OPEN, null, null);

        var response = chooser.run ();

        if (response == Gtk.ResponseType.ACCEPT) {
            var file = chooser.get_filename ();

            var vault = AegisManager.import_from_json_file(file, this);

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
    
    private async string acquire_from_screenshot() {
        try {
            var parent_window = Xdp.ParentWindow.new_gtk (this);
            var screenshot_uri = yield portal.take_screenshot(parent_window, Xdp.ScreenshotFlags.INTERACTIVE);
            
            var file = File.new_for_uri(screenshot_uri);
            var file_stream = file.read ();
            
            var pixbuf = new Gdk.Pixbuf.from_stream (file_stream);
            
            var payload = QrHelpers.get_payload_from_pixbuf (pixbuf);
            
            print("payload: %s\n",payload);
            
            file_stream.close();
            
            return payload;
                
        } catch (GLib.Error error) {
            return "";
        }
    }
    
    private void bind_pads_to_source_list() {
  
        var issuers = new Gee.HashMap<string, Granite.Widgets.SourceList.ExpandableItem>();
        
        foreach(var pad in otp_library.get_set()) {
            
            if(!issuers.keys.contains(pad.issuer)) {
                var item = new Granite.Widgets.SourceList.ExpandableItem(pad.issuer);
                issuers[pad.issuer] = item;
            }
            
            var issuer_item = issuers[pad.issuer];
            
            var account_item = new Granite.Widgets.SourceList.Item(pad.account_name);
            issuer_item.add(account_item);
        }
        
        source_list.root.clear();
        
        foreach(var issuer_item in issuers.values) {
            source_list.root.add(issuer_item);
        }
        
        source_list.root.expand_all();
    }
    
    private void pad_item_selected(Granite.Widgets.SourceList source_list, Granite.Widgets.SourceList.Item? item){
        if(item is Granite.Widgets.SourceList.Item && !(item is Granite.Widgets.SourceList.ExpandableItem)){
            var account_name = item.name;
            var issuer_name = item.parent.name;
            
            var pad = otp_library.get_pad(issuer_name,account_name);
            
            onetimepad_view.pad = pad;
        }
    }
}

