/* Binding for the opaque-bridge client library; see subprojects/opaque-bridge/include/opaque_bridge.h */
[CCode (cheader_filename = "opaque_bridge.h")]
namespace OpaqueBridge {

    [SimpleType]
    [CCode (cname = "OpaqueBuf", has_type_id = false)]
    public struct Buf {
        public uint8* ptr;
        public size_t len;
    }

    /** Releases a buffer returned by the library; safe on an empty buffer. */
    [CCode (cname = "opaque_buf_free")]
    public void buf_free (Buf buf);

    [CCode (cname = "opaque_client_registration_start")]
    public int registration_start ([CCode (array_length_type = "size_t")] uint8[] password, out Buf request, out Buf state);

    [CCode (cname = "opaque_client_registration_finish")]
    public int registration_finish (
        [CCode (array_length_type = "size_t")] uint8[] password,
        [CCode (array_length_type = "size_t")] uint8[] state,
        [CCode (array_length_type = "size_t")] uint8[] response,
        [CCode (array_length_type = "size_t")] uint8[] credential_id,
        out Buf upload, out Buf export_key);

    [CCode (cname = "opaque_client_login_start")]
    public int login_start ([CCode (array_length_type = "size_t")] uint8[] password, out Buf request, out Buf state);

    [CCode (cname = "opaque_client_login_finish")]
    public int login_finish (
        [CCode (array_length_type = "size_t")] uint8[] password,
        [CCode (array_length_type = "size_t")] uint8[] state,
        [CCode (array_length_type = "size_t")] uint8[] response,
        [CCode (array_length_type = "size_t")] uint8[] credential_id,
        out Buf finalization, out Buf session_key, out Buf export_key);
}
