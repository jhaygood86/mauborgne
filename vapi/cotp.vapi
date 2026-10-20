[CCode (cheader_filename = "cotp.h")]
namespace Cotp {
    
    [CCode (cname = "int", cprefix = "COTP_", has_type_id = false)]
    public enum Algorithm {
        SHA1,
        SHA256,
        SHA512
    }
    
    [CCode (cname = "cotp_error_t", cprefix = "", has_type_id = false)]
    public enum Error {
        NO_ERROR = 0,
        VALID,
        WCRYPT_VERSION_MISMATCH,
        INVALID_B32_INPUT,
        INVALID_ALGO,
        INVALID_DIGITS,
        INVALID_PERIOD,
        MEMORY_ALLOCATION_ERROR,
        INVALID_USER_INPUT,
        EMPTY_STRING,
        MISSING_LEADING_ZERO,
        INVALID_COUNTER,
        WHMAC_ERROR,
        INVALID_YAOTP_SECRET_LENGTH,
        INVALID_YAOTP_SECRET_CRC,
        INVALID_YAOTP_PIN
    }
    
    [CCode (cname = "get_totp")]
    public string get_totp(string base32_encoded_secret, int digits, int period, Algorithm algorithm, out Error error);

    [CCode (cname = "get_totp_at")]
    public string get_totp_at(string base32_encoded_secret, long time, int digits, int period, Algorithm algorithm, out Error error);

    [CCode (cname = "get_hotp")]
    public string get_hotp(string base32_encoded_secret, long counter, int digits, Algorithm algorithm, out Error error);
}
