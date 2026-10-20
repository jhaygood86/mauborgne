#if HAVE_OPAQUE
/** OPAQUE over the Rust opaque-bridge static library. */
public class NativeOpaqueClient : Object, OpaqueProtocol {

    private static uint8[] copy_and_free (OpaqueBridge.Buf buf) {
        var bytes = new uint8[buf.len];

        if (buf.len > 0) {
            Memory.copy (bytes, buf.ptr, buf.len);
            // the key material must not linger in the library's allocation
            Memory.set (buf.ptr, 0, buf.len);
        }

        OpaqueBridge.buf_free (buf);

        return bytes;
    }

    private static void check (int code, string step) throws OpaqueError {
        if (code != 0) {
            throw new OpaqueError.FAILED ("%s failed (%d)", step, code);
        }
    }

    public OpaqueStart registration_start (uint8[] password) throws OpaqueError {
        OpaqueBridge.Buf request, state;
        check (OpaqueBridge.registration_start (password, out request, out state), "registration start");

        return new OpaqueStart (copy_and_free (request), copy_and_free (state));
    }

    public OpaqueRegistrationFinish registration_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
        OpaqueBridge.Buf upload, export_key;
        check (OpaqueBridge.registration_finish (password, state, response, credential_id, out upload, out export_key), "registration finish");

        return new OpaqueRegistrationFinish (copy_and_free (upload), copy_and_free (export_key));
    }

    public OpaqueStart login_start (uint8[] password) throws OpaqueError {
        OpaqueBridge.Buf request, state;
        check (OpaqueBridge.login_start (password, out request, out state), "login start");

        return new OpaqueStart (copy_and_free (request), copy_and_free (state));
    }

    public OpaqueLoginFinish login_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
        OpaqueBridge.Buf finalization, session_key, export_key;
        check (OpaqueBridge.login_finish (password, state, response, credential_id, out finalization, out session_key, out export_key), "login finish");

        return new OpaqueLoginFinish (copy_and_free (finalization), copy_and_free (session_key), copy_and_free (export_key));
    }
}
#endif
