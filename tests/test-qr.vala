namespace QrTests {

    const string URI = "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example";

    public void register () {
        Test.add_func ("/qr/roundtrip", test_roundtrip);
        Test.add_func ("/qr/roundtrip_long_payload", test_roundtrip_long);
        Test.add_func ("/qr/mirrored_roundtrip", test_mirrored_roundtrip);
        Test.add_func ("/qr/blank_image", test_blank_image);
        Test.add_func ("/qr/two_codes", test_two_codes);
        Test.add_func ("/qr/pixbuf_dimensions", test_pixbuf_dimensions);
    }

    private uint8[] encode (string text, out int side) {
        var buffer_length = QrCodegen.get_buffer_length_for_version (QrCodegen.VERSION_MAX);
        var temp = new uint8[buffer_length];
        var qr_code = new uint8[buffer_length];

        assert_true (QrCodegen.encode_text (text, temp, qr_code, QrCodegen.ECC.HIGH,
            QrCodegen.VERSION_MIN, QrCodegen.VERSION_MAX, QrCodegen.Mask.AUTO, true));

        side = QrCodegen.get_size (qr_code);
        return qr_code;
    }

    /** The code image on a white background, since scanners need a quiet zone. */
    private Gdk.Pixbuf with_quiet_zone (Gdk.Pixbuf code, int border) {
        var padded = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, code.width + 2 * border, code.height + 2 * border);
        padded.fill ((uint32) 0xffffffffu);
        code.copy_area (0, 0, code.width, code.height, padded, border, border);
        return padded;
    }

    private Gdk.Pixbuf render (string text) {
        int side;
        var qr_code = encode (text, out side);

        return with_quiet_zone (QrHelpers.get_pixbuf_from_qr_code (qr_code, side), 40);
    }

    private void test_roundtrip () {
        assert_cmpstr (QrHelpers.get_payload_from_pixbuf (render (URI)), CompareOperator.EQ, URI);
    }

    // Codes exported by earlier versions were mirrored across the diagonal
    private void test_mirrored_roundtrip () {
        var mirrored = render (URI).rotate_simple (Gdk.PixbufRotation.CLOCKWISE).flip (true);

        assert_cmpstr (QrHelpers.get_payload_from_pixbuf (mirrored), CompareOperator.EQ, URI);
    }

    private void test_roundtrip_long () {
        var long_uri = URI + "&algorithm=SHA512&digits=8&period=45&note=" + string.nfill (120, 'x');

        assert_cmpstr (QrHelpers.get_payload_from_pixbuf (render (long_uri)), CompareOperator.EQ, long_uri);
    }

    private void test_blank_image () {
        var blank = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, 300, 300);
        blank.fill ((uint32) 0xffffffffu);

        assert_cmpstr (QrHelpers.get_payload_from_pixbuf (blank), CompareOperator.EQ, "");
    }

    // Only a single code is accepted; ambiguity yields nothing
    private void test_two_codes () {
        var first = render (URI);
        var second = render (URI + "&issuer=Other");

        var both = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, first.width + second.width, int.max (first.height, second.height));
        both.fill ((uint32) 0xffffffffu);
        first.copy_area (0, 0, first.width, first.height, both, 0, 0);
        second.copy_area (0, 0, second.width, second.height, both, first.width, 0);

        assert_cmpstr (QrHelpers.get_payload_from_pixbuf (both), CompareOperator.EQ, "");
    }

    private void test_pixbuf_dimensions () {
        int side;
        var qr_code = encode (URI, out side);

        var pixbuf = QrHelpers.get_pixbuf_from_qr_code (qr_code, side);

        assert_cmpint (pixbuf.width, CompareOperator.EQ, side * QrHelpers.QR_PIXEL_SIZE);
        assert_cmpint (pixbuf.height, CompareOperator.EQ, side * QrHelpers.QR_PIXEL_SIZE);
        assert_true (pixbuf.has_alpha);
    }
}
