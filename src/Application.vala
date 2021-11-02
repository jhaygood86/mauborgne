/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Justin Haygood <jhaygood86@gmail.com>
 */

public class MauborgneApp : Gtk.Application {

    private Mauborgne.Portal.Settings? portal_settings;

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

        var preferred_color_scheme = granite_settings.prefers_color_scheme;

        if (preferred_color_scheme == Granite.Settings.ColorScheme.NO_PREFERENCE && Environment.get_variable ("XDG_CURRENT_DESKTOP") == "GNOME") {
            portal_settings = Mauborgne.Portal.Settings.get ();
            var theme_name = portal_settings.read ("org.gnome.desktop.interface", "gtk-theme").get_variant ().get_string ();

            gtk_settings.gtk_application_prefer_dark_theme = theme_name.has_suffix ("-dark");

            portal_settings.setting_changed.connect ((scheme, key, value) => {

                if (scheme == "org.gnome.desktop.interface" && key == "gtk-theme") {
                    gtk_settings.gtk_application_prefer_dark_theme = value.get_string ().has_suffix ("-dark");
                }
            });

        } else {
            gtk_settings.gtk_application_prefer_dark_theme = preferred_color_scheme == Granite.Settings.ColorScheme.DARK;

            granite_settings.notify["prefers-color-scheme"].connect (() => {
                gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            });
        }
        
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
