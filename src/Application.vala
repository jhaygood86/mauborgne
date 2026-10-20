/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Justin Haygood <jhaygood86@gmail.com>
 */

public class MauborgneApp : Adw.Application {

    public MauborgneApp () {
        Object (
            application_id: "io.github.jhaygood86.mauborgne",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    protected override void startup () {
        base.startup ();

        // the brand theme is light only, like the Windows and Android apps
        Adw.StyleManager.get_default ().color_scheme = Adw.ColorScheme.FORCE_LIGHT;

        var display = Gdk.Display.get_default ();

        Gtk.IconTheme.get_for_display (display).add_resource_path ("/io/github/jhaygood86/mauborgne/");

        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/io/github/jhaygood86/mauborgne/application.css");
        Gtk.StyleContext.add_provider_for_display (display, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    protected override void activate () {
        var main_window = active_window;

        if (main_window == null) {
            main_window = new Mauborgne.MainWindow (this);
        }

        main_window.present ();
    }
}
