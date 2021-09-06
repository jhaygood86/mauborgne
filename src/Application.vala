/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Justin Haygood <jhaygood86@gmail.com>
 */

public class MauborgneApp : Gtk.Application {
    public MauborgneApp () {
        Object (
            application_id: "io.github.jhaygood86.mauborgne",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }
    
    protected override void activate () {
        init_theme ();

        weak Gtk.IconTheme default_theme = Gtk.IconTheme.get_default ();
        default_theme.add_resource_path ("/io/github/jhaygood86/mauborgne/");
    
        var main_window = new Mauborgne.MainWindow (this);
        
        var granite_settings = Granite.Settings.get_default ();
        var gtk_settings = Gtk.Settings.get_default ();

        gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;

        granite_settings.notify["prefers-color-scheme"].connect (() => {
            gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        });
        
        main_window.show_all ();
        
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/io/github/jhaygood86/mauborgne/application.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
    
    private void init_theme () {
         GLib.Value value = GLib.Value (GLib.Type.STRING);
         Gtk.Settings.get_default ().get_property ("gtk-theme-name", ref value);
         if (!value.get_string ().has_prefix ("io.elementary.")) {
             Gtk.Settings.get_default ().set_property ("gtk-icon-theme-name", "elementary");
             Gtk.Settings.get_default ().set_property ("gtk-theme-name", "io.elementary.stylesheet.blueberry");
         }
    }

    public static int main (string[] args) {
        return new MauborgneApp ().run (args);
    }
}
