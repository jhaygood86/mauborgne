/**
 * Base for the Aegis vault password dialogs. The dialog stays open after the
 * user submits so the caller can report an error and wait again; the caller
 * closes it with force_close () once it is done.
 */
public abstract class PasswordPromptDialog : Adw.Dialog {

    public signal void submitted ();

    public string heading { get; construct; }
    public string body { get; construct; }
    public string action_label { get; construct; }

    public string password {
        get {
            return password_entry.text;
        }
    }

    protected Gtk.PasswordEntry password_entry;
    protected Gtk.Box entries_box;

    private Gtk.Label feedback_label;
    private bool presented = false;

    construct {
        content_width = 420;

        password_entry = new Gtk.PasswordEntry () {
            show_peek_icon = true,
            placeholder_text = _("Password"),
            hexpand = true
        };
        password_entry.activate.connect (submit);

        entries_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        entries_box.append (password_entry);

        feedback_label = new Gtk.Label (null) {
            wrap = true,
            max_width_chars = 40,
            xalign = 0,
            visible = false
        };
        feedback_label.add_css_class ("error");

        var heading_label = new Gtk.Label (heading) {
            wrap = true,
            xalign = 0
        };
        heading_label.add_css_class ("title-2");

        var body_label = new Gtk.Label (body) {
            wrap = true,
            xalign = 0
        };

        var cancel_button = new Gtk.Button.with_label (_("Cancel"));
        cancel_button.clicked.connect (() => close ());

        var action_button = new Gtk.Button.with_label (action_label);
        action_button.add_css_class ("suggested-action");
        action_button.clicked.connect (submit);

        var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            margin_top = 12
        };
        button_box.append (cancel_button);
        button_box.append (action_button);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 24,
            margin_end = 24
        };
        box.append (heading_label);
        box.append (body_label);
        box.append (entries_box);
        box.append (feedback_label);
        box.append (button_box);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (new Adw.HeaderBar ());
        toolbar_view.content = box;

        title = heading;
        child = toolbar_view;
        default_widget = action_button;
        focus_widget = password_entry;
    }

    /** Returns an error message if the input is not acceptable, otherwise null. */
    protected virtual string? validate () {
        return null;
    }

    public void show_error (string error) {
        password_entry.add_css_class ("error");
        feedback_label.label = error;
        feedback_label.visible = true;
    }

    public void clear_error () {
        password_entry.remove_css_class ("error");
        feedback_label.visible = false;
    }

    private void submit () {
        clear_error ();

        var error = validate ();

        if (error != null) {
            show_error (error);
            return;
        }

        submitted ();
    }

    /** Presents the dialog if needed and waits; true if submitted, false if dismissed. */
    public async bool wait_for_response (Gtk.Widget parent) {
        if (!presented) {
            presented = true;
            present (parent);
        }

        var accepted = false;

        var submitted_id = submitted.connect (() => {
            accepted = true;
            wait_for_response.callback ();
        });

        var closed_id = closed.connect (() => {
            accepted = false;
            wait_for_response.callback ();
        });

        yield;

        disconnect (submitted_id);
        disconnect (closed_id);

        return accepted;
    }
}
