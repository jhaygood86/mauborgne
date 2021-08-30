[CCode (cheader_filename = "qrcodegen.h")]
namespace QrCodegen {

    [CCode (cname = "qrcodegen_VERSION_MIN")]
    public const int VERSION_MIN;

    [CCode (cname = "qrcodegen_VERSION_MAX")]
    public const int VERSION_MAX;

	[CCode (cname = "qrcodegen_Ecc", cprefix = "qrcodegen_Ecc_", has_type_id = false)]
	public enum ECC {
	// Must be declared in ascending order of error protection
	// so that an internal qrcodegen function works properly
	    LOW = 0 ,  // The QR Code can tolerate about  7% erroneous codewords
	    MEDIUM = 1  ,  // The QR Code can tolerate about 15% erroneous codewords
	    QUARTILE = 2,  // The QR Code can tolerate about 25% erroneous codewords
	    HIGH = 3      // The QR Code can tolerate about 30% erroneous codewords
    }

    [CCode (cname = "qrcodegen_Mask", cprefix = "qrcodegen_Mask_", has_type_id = false)]
    public enum Mask {
	    AUTO = -1
    }


    [CCode(cname = "qrcodegen_encodeText")]
    public bool encode_text(string text, [CCode (array_length = false)] uint8[] tempBuffer, [CCode (array_length = false)] uint8[] qrcode, ECC ecl, int min_version, int max_version, Mask mask, bool boost_ecl);

    [CCode(cname = "qrcodegen_BUFFER_LEN_FOR_VERSION")]
    public int get_buffer_length_for_version (int version);

    [CCode(cname = "qrcodegen_getSize")]
    public int get_size([CCode (array_length = false)] uint8[] qrcode);

    [CCode(cname = "qrcodegen_getModule")]
    public bool is_pixel_dark([CCode (array_length = false)] uint8[] qrcode, int x, int y);
}
