namespace QrHelpers {

    public static string get_payload_from_pixbuf(Gdk.Pixbuf pixbuf) {
        var width = pixbuf.width;
        var height = pixbuf.height;

        print("pixbuf size: %d x %d\n", width, height);

        var qr_pixels = pixbuf.get_pixels_with_length ();

        var qr_recognizer = new Quirc.Recognizer ();
        qr_recognizer.resize(width, height);

        unowned var qr_pixel_dst = qr_recognizer.begin(null, null);

        convert_rgba32_to_grayscale(qr_pixels, qr_pixel_dst);

        qr_recognizer.end();

        var count = qr_recognizer.count();

        print("recognized qr codes: %d\n",count);

        if (count == 1) {
            Quirc.Code code;
            Quirc.Data data;
            Quirc.DecodeError err;

            qr_recognizer.extract(0, out code);
            err = code.decode(out data);

            string payload = (string)data.payload;

            print("qr code payload: %s\n",payload);

            return payload;
        }

        return "";
    }

    private static void convert_rgba32_to_grayscale(uint8[] src, uint8[] dst) {

        int j = 0;

        for(var i = 0; i < src.length; i += 4){
            int total = src[i] + src[i+1] + src[i+2];
            dst[j++] = (uint8)(total / 3);
        }
    }

    public const int QR_PIXEL_SIZE = 10;

    private static void convert_qrcode_to_rgba32(uint8[] qr_code, int side_length, uint8[] dst, int target_length) {

        int k = 0;

        for(var i = 0; i < side_length; i ++){
            for(var r = 0; r < QR_PIXEL_SIZE; r++){
                for(var j = 0; j < side_length; j++){
                    var is_pixel_dark = QrCodegen.is_pixel_dark(qr_code,i,j);

                    var pixel_value = is_pixel_dark ? 0 : 255;

                    for(var r2 = 0; r2 < QR_PIXEL_SIZE; r2++){
                        dst[k++] = pixel_value;
                        dst[k++] = pixel_value;
                        dst[k++] = pixel_value;
                        dst[k++] = 255;
                    }
                }
            }
        }
    }

    public Gdk.Pixbuf get_pixbuf_from_qr_code(uint8[] qrcode, int side_length) {
        var target_length = (side_length * QR_PIXEL_SIZE);
        var pixbuf_size = target_length * target_length * 4;
        var pixbuf_buffer = new uint8[pixbuf_size];

        convert_qrcode_to_rgba32 (qrcode, side_length, pixbuf_buffer, target_length);

        var rowstride = Gdk.Pixbuf.calculate_rowstride(Gdk.Colorspace.RGB, true, 8, target_length, target_length);
        var pixbuf = new Gdk.Pixbuf.from_data(pixbuf_buffer, Gdk.Colorspace.RGB, true, 8, target_length, target_length, rowstride);

        return pixbuf;
    }
}
