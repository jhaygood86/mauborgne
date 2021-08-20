[CCode (cheader_filename = "quirc.h")]
namespace Quirc {

    [CCode(cname = "struct quirc", free_function = "quirc_destroy")]
    [Compact]
    public class Recognizer {
        [CCode(cname = "quirc_new")]
        public Recognizer ();
        
        [CCode(cname = "quirc_version")]
        public string version();
        
        [CCode(cname = "quirc_resize")]
        public int resize(int w, int h);
        
        [CCode(cname = "quirc_begin", array_length = false)]
        public unowned uint8[] begin(out int w, out int h);
        
        [CCode(cname = "quirc_end")]
        public void end();
        
        [CCode(cname = "quirc_count")]
        public int count();
        
        [CCode(cname = "quirc_extract")]
        public void extract(int index, out Code code);
    }
    
    [CCode (cname = "quirc_point", has_type_id = false)]
    public struct Point {
	    int	x;
	    int	y;
    }
    
    [CCode (cname = "quirc_decode_error_t", cprefix = "QUIRC_", has_type_id = false)]
    public enum DecodeError {
	    SUCCESS = 0,
	    ERROR_INVALID_GRID_SIZE,
	    ERROR_INVALID_VERSION,
	    ERROR_FORMAT_ECC,
	    ERROR_DATA_ECC,
	    ERROR_UNKNOWN_DATA_TYPE,
	    ERROR_DATA_OVERFLOW,
	    ERROR_DATA_UNDERFLOW
    }
    
    [CCode (cname = "struct quirc_code", has_type_id = false, destroy_function = "")]
    public struct Code {
	    Point[]	corners;
        int size;
	    uint8[] cell_bitmap;
	    
        [CCode (cname = "quirc_decode")]
        public DecodeError decode (out Data data);
    }
    
    [CCode (cname = "struct quirc_data", has_type_id = false, destroy_function = "")]
    public struct Data {
        int	version;
	    int	ecc_level;
	    int	mask;
	    int	data_type;
	    
	    [CCode (array_length_cname = "payload_len", array_length_type = "int")]
	    uint8[] payload;
	    int	payload_len;
	    uint32 eci;
    }
}
