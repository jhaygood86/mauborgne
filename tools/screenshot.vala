/*
 * Renders the main window with a few made-up pads to a PNG, for the README and the website.
 *
 *   mauborgne-screenshot <output.png> [width height]
 *
 * It only ever shows sample pads: it points the app at a throw-away data directory and an in-memory
 * settings store, and refuses to run if the library holds anything but the sample pads. The sample
 * secrets do pass through the keyring (the app reads them from there), under made-up accounts,
 * and are removed again when it is done.
 */
namespace Screenshot {

    private const string SECRET = "JBSWY3DPEHPK3PXP";

    private struct Demo {
        public string issuer;
        public string account;
        public OneTimePadType type;
    }

    private const int SETTLE_MS = 2500;

    private Demo[] demos () {
        return {
            { "GitHub", "ada@example.com", OneTimePadType.TOTP },
            { "Google", "ada@example.com", OneTimePadType.TOTP },
            { "Amazon Web Services", "ada-admin", OneTimePadType.TOTP },
            { "Dropbox", "ada@example.com", OneTimePadType.TOTP },
            { "Roblox", "ada_builds", OneTimePadType.TOTP },
            { "Carta", "ada@example.com", OneTimePadType.TOTP },
            { "Hardware Token", "office-vpn", OneTimePadType.HOTP }
        };
    }

    private void find_rows (Gtk.Widget widget, Gee.List<Gtk.ListBoxRow> rows) {
        if (widget is Gtk.ListBoxRow && ((Gtk.ListBoxRow) widget).get_data<OneTimePad> ("pad") != null) {
            rows.add ((Gtk.ListBoxRow) widget);
        }

        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            find_rows (child, rows);
        }
    }

    private Gtk.ListBox? find_list (Gtk.Widget widget) {
        if (widget is Gtk.ListBox && widget.has_css_class ("navigation-sidebar")) {
            return (Gtk.ListBox) widget;
        }

        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
            var found = find_list (child);

            if (found != null) {
                return found;
            }
        }

        return null;
    }

    private void save (Gtk.Window window, string path) {
        var paintable = new Gtk.WidgetPaintable (window);
        var snapshot = new Gtk.Snapshot ();
        paintable.snapshot (snapshot, window.get_width (), window.get_height ());

        var node = snapshot.free_to_node ();
        var texture = window.get_native ().get_renderer ().render_texture (node, null);

        if (!texture.save_to_png (path)) {
            warning ("Could not write %s", path);
        }
    }

    private async void clear_secrets () {
        foreach (var demo in demos ()) {
            var pad = new OneTimePad.from_secret_key (demo.issuer, demo.account, SECRET, "");
            yield pad.clear_secret ();
        }
    }

    int main (string[] args) {
        if (args.length < 2) {
            printerr ("usage: %s <output.png> [width height]\n", args[0]);
            return 2;
        }

        var output = args[1];
        var width = args.length > 3 ? int.parse (args[2]) : 1100;
        var height = args.length > 3 ? int.parse (args[3]) : 680;

        var data_dir = Path.build_filename (DirUtils.make_tmp ("mauborgne-screenshot-XXXXXX"), "data");
        DirUtils.create_with_parents (data_dir, 0700);
        Environment.set_variable ("XDG_DATA_HOME", data_dir, true);
        Environment.set_variable ("GSETTINGS_BACKEND", "memory", true);

        // pads for the library to find, with their secrets in the keyring
        var library_setup = new MainLoop ();
        var made = 0;

        foreach (var demo in demos ()) {
            var pad = new OneTimePad.from_secret_key (demo.issuer, demo.account, SECRET, "");
            pad.pad_type = demo.type;
            pad.modified_at = 1;

            try {
                pad.to_keyfile ().save_to_file (Path.build_filename (data_dir, pad.get_file_name ()));
            } catch (Error e) {
                error ("%s", e.message);
            }

            pad.save_secret.begin ((obj, res) => {
                pad.save_secret.end (res);

                if (++made == demos ().length) {
                    library_setup.quit ();
                }
            });
        }

        library_setup.run ();

        // Never photograph real data: the library must be reading the throw-away directory and
        // holding nothing but the pads made above.
        var expected = new Gee.HashSet<string> ();

        foreach (var demo in demos ()) {
            expected.add (demo.issuer + ":" + demo.account);
        }

        var library = OneTimePadLibrary.get_default ();
        var real_data = Environment.get_user_data_dir () != data_dir || library.get_set ().size != expected.size;

        foreach (var pad in library.get_set ()) {
            real_data = real_data || !expected.contains (pad.identity);
        }

        if (real_data) {
            printerr ("screenshot: refusing to run, the library holds something other than the sample pads\n");
            clear_secrets.begin ((obj, res) => { clear_secrets.end (res); });
            return 3;
        }

        var exit_code = 1;
        var app = new MauborgneApp ();
        // another instance may be running; this one is separate
        app.flags = ApplicationFlags.NON_UNIQUE;

        app.activate.connect_after (() => {
            var window = app.active_window;
            printerr ("screenshot: window %s\n", window == null ? "missing" : "up");
            window.set_default_size (width, height);

            Timeout.add (SETTLE_MS / 2, () => {
                var list = find_list (window);
                var rows = new Gee.ArrayList<Gtk.ListBoxRow> ();
                find_rows (list, rows);

                // the first pad shows its code
                foreach (var row in rows) {
                    if (row.get_data<OneTimePad> ("pad").issuer == "GitHub") {
                        list.select_row (row);
                        break;
                    }
                }

                return Source.REMOVE;
            });

            Timeout.add (SETTLE_MS, () => {
                save (window, output);
                exit_code = 0;

                clear_secrets.begin ((obj, res) => {
                    clear_secrets.end (res);
                    app.quit ();
                });

                return Source.REMOVE;
            });
        });

        var status = app.run ({ args[0] });
        printerr ("screenshot: app finished with %d\n", status);

        return exit_code;
    }
}
