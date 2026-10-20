/**
 * A circular initials avatar for an issuer. The colour is picked from the
 * brand palette by hashing the issuer name, the same way as the Windows and
 * Android apps, so an issuer looks the same on every platform.
 */
namespace Mauborgne.IssuerAvatar {

    // number of avatar-N colours in application.css
    private const int PALETTE_SIZE = 8;

    public string initials (string? issuer) {
        if (issuer == null || issuer.strip () == "") {
            return "?";
        }

        var trimmed = issuer.strip ();
        var parts = new Gee.ArrayList<string> ();
        var current = new StringBuilder ();

        unichar c;
        int index = 0;

        while (trimmed.get_next_char (ref index, out c)) {
            if (c == ' ' || c == '-' || c == '_' || c == '.') {
                if (current.len > 0) {
                    parts.add (current.str);
                    current.truncate (0);
                }
            } else {
                current.append_unichar (c);
            }
        }

        if (current.len > 0) {
            parts.add (current.str);
        }

        if (parts.size >= 2) {
            return first_char (parts[0]).up () + first_char (parts[1]).up ();
        }

        // single word: its first two characters
        var word = trimmed;
        var count = word.char_count ();

        if (count >= 2) {
            return word.substring (0, word.index_of_nth_char (2)).up ();
        }

        return word.up ();
    }

    private string first_char (string text) {
        return text.substring (0, text.index_of_nth_char (1));
    }

    /** Stable index into the palette for this issuer. */
    public int color_index (string? issuer) {
        uint32 hash = 0;

        if (issuer != null) {
            unichar c;
            int index = 0;

            while (issuer.get_next_char (ref index, out c)) {
                hash = (hash * 31 + (uint32) c) & 0x7FFFFFFF;
            }
        }

        return (int) (hash % PALETTE_SIZE);
    }

    public Gtk.Widget create (string? issuer) {
        var label = new Gtk.Label (initials (issuer)) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            width_chars = 2
        };
        label.add_css_class ("pst-avatar");
        label.add_css_class ("pst-avatar-%d".printf (color_index (issuer)));

        return label;
    }
}
