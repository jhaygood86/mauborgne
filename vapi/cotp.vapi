[CCode (cheader_filename = "cotp.h")]
namespace Cotp {
    
    [CCode (cname = "int", cprefix = "", has_type_id = false)]
    public enum Algorithm {
        SHA1,
        SHA256,
        SHA512
    }
    
    [CCode (cname = "cotp_error_t", cprefix = "", has_type_id = false)]
    public enum Error {
        VALID = 0,
        GCRYPT_VERSION_MISMATCH = 1,
        INVALID_B32_INPUT       = 2,
        INVALID_ALGO            = 3,
        INVALID_OTP             = 4,
        INVALID_DIGITS          = 5,
        INVALID_PERIOD          = 6
    }
    
    [CCode (cname = "get_totp")]
    public string get_totp(string base32_encoded_secret, int digits, int period, Algorithm algorithm, out Error error);
}
