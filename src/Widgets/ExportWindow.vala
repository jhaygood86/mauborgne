public class ExportWindow : Adw.Dialog {

    public OneTimePad pad { get; construct; }

    public ExportWindow (OneTimePad pad) {
        title = _("Export: %s").printf(pad.account_name);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (new Adw.HeaderBar ());
        child = toolbar_view;

        var qrcode_buffer_length = QrCodegen.get_buffer_length_for_version(QrCodegen.VERSION_MAX);

        print("%d\n",qrcode_buffer_length);

        var tmp_buffer = new uint8[qrcode_buffer_length];
        var qr_code = new uint8[qrcode_buffer_length];

        pad.to_uri.begin((obj,res) => {

            var uri = pad.to_uri.end(res);

            print("uri: %s\n",uri);

            var generated = QrCodegen.encode_text(uri, tmp_buffer, qr_code, QrCodegen.ECC.HIGH, QrCodegen.VERSION_MIN, QrCodegen.VERSION_MAX, QrCodegen.Mask.AUTO, true);

            if (generated) {
                print("code generated\n");
            } else {
                print("code generation failed\n");
            }

            var qr_code_side_length = QrCodegen.get_size(qr_code);

            print("side length: %d\n",qr_code_side_length);

            var pixbuf = QrHelpers.get_pixbuf_from_qr_code(qr_code,qr_code_side_length);

            var picture = new Gtk.Picture.for_paintable(Gdk.Texture.for_pixbuf(pixbuf)) {
                margin_top = 15 * 4,
                margin_bottom = 15 * 4,
                margin_start = 15 * 4,
                margin_end = 15 * 4,
                can_shrink = false
            };
            toolbar_view.content = picture;

            toolbar_view.add_css_class("export-window");
        });

    }
}
