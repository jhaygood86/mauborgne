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
    Granite.Widgets.Welcome welcome_screen;
    Gtk.Label title_label;
    Gtk.Label subtitle_label;
    Gtk.Grid codeview_grid;
    Gtk.ProgressBar code_remaining_progress;
    
    construct {
        portal = new Xdp.Portal();
        
        otp_library = new OneTimePadLibrary();
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
        
        var add_pad_popover = new Gtk.Popover (null);
        add_pad_popover.add (add_pad_grid);
        
        add_pad_grid.attach (add_pad_screenshot_button, 0, 0);
        add_pad_grid.show_all ();
        
        var add_pad_button = new Gtk.MenuButton () {
            label = _("Add One Time Pad…"),
            image = new Gtk.Image.from_icon_name ("list-add-symbolic", Gtk.IconSize.SMALL_TOOLBAR),
            always_show_image = true,
            popover = add_pad_popover
        };
        
        add_pad_screenshot_button.clicked.connect(acquire_from_screenshot_clicked);

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
        
        var codeview_header = new Hdy.HeaderBar () {
            has_subtitle = false,
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
        title_label.justify = Gtk.Justification.CENTER;
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
        
        get_style_context ().add_class ("unread-message");
        
        codeview_grid = new Gtk.Grid ();
        codeview_grid.attach (codeview_header, 0, 0);
        codeview_grid.attach (welcome_screen, 0, 1);
        
        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
        paned.pack1 (sidebar, false, false);
        paned.pack2 (codeview_grid, true, false);
        
        add (paned);
        
        bind_pads_to_source_list();
    }
    
    private void welcome_screen_activated (int index) {
        if (index == 0) {
            add_code_from_screenshot ();
        }
    }
    
    private void acquire_from_screenshot_clicked(Gtk.Button button) {
        add_code_from_screenshot ();
    }
    
    private void add_code_from_screenshot() {
        acquire_from_screenshot.begin((obj,res) => {
                var qr_code_uri = acquire_from_screenshot.end(res);
                print("screenshot uri: %s\n",qr_code_uri);
                
                if(qr_code_uri.length > 0){
                    var otp = new OneTimePad.from_uri(qr_code_uri);
                    otp_library.add(otp);
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
            
            var payload = QrRecognizer.get_payload_from_pixbuf (pixbuf);
            
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
            
            title_label.label = pad.account_name;
            
            switch_to_code_display();
            subtitle_label.label = pad.get_otp_code();
            
            Timeout.add(1,() => {
                if(source_list.selected == item){
                    subtitle_label.label = pad.get_otp_code();
                    set_remaining_time();
                    return true;
                } else {
                    return false;
                }
            });
            
            set_remaining_time();
        }
    }
    
    private void set_remaining_time() {
        var item = source_list.selected;
        
         if(item is Granite.Widgets.SourceList.Item && !(item is Granite.Widgets.SourceList.ExpandableItem)){
            var account_name = item.name;
            var issuer_name = item.parent.name;
            
            var pad = otp_library.get_pad(issuer_name,account_name);
            
            var remaining_time = pad.get_remaining_time();
            
            code_remaining_progress.text = "Code Changes In %d seconds".printf(remaining_time);
            
            var ratio = ((double)remaining_time) / ((double)pad.period);
            code_remaining_progress.set_fraction(ratio); 
         }
    }
        
    private void switch_to_code_display() {
        codeview_grid.remove(welcome_screen);
        codeview_grid.attach(title_label, 0, 1);
        codeview_grid.attach(subtitle_label, 0, 2);
        codeview_grid.attach(code_remaining_progress, 0, 3);
    }
}

