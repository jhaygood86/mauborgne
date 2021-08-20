namespace QrRecognizer {
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
}
