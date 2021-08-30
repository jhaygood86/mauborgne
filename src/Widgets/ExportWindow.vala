public class ExportWindow : Gtk.Window {

    public OneTimePad pad { get; construct; }

    public ExportWindow (OneTimePad pad) {
        title = "Export : %s".printf(pad.account_name);

        var qrcode_buffer_length = QrCodegen.get_buffer_length_for_version(QrCodegen.VERSION_MAX);

        print("%d\n",qrcode_buffer_length);

        var tmp_buffer = new uint8[qrcode_buffer_length];
        var qr_code = new uint8[qrcode_buffer_length];

        var uri = pad.to_uri();
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

        var image = new Gtk.Image.from_pixbuf(pixbuf);
        image.visible = true;
        image.margin = 15 * 4;
        child = image;

        var context = get_style_context();
        context.add_class("export-window");
    }
}
