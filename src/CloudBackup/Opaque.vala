/**
 * Client half of OPAQUE (RFC 9807). The service only sees this interface so the protocol
 * code stays testable without the native library: the app uses the Rust opaque-bridge crate
 * (the same code the Worker runs, so both sides always agree on the ciphersuite and
 * stretching parameters), the tests can use a stand-in.
 */
public errordomain OpaqueError {
    /** Wrong password, or the response was not valid. Deliberately coarse: it never says why. */
    FAILED,
    /** The native OPAQUE library is not part of this build. */
    UNAVAILABLE
}

public class OpaqueStart : Object {
    /** Sent to the server. */
    public uint8[] request;
    /** Kept locally until the finish step. */
    public uint8[] state;

    public OpaqueStart (owned uint8[] request, owned uint8[] state) {
        this.request = (owned) request;
        this.state = (owned) state;
    }
}

public class OpaqueRegistrationFinish : Object {
    public uint8[] upload;
    /** Never leaves the device. */
    public uint8[] export_key;

    public OpaqueRegistrationFinish (owned uint8[] upload, owned uint8[] export_key) {
        this.upload = (owned) upload;
        this.export_key = (owned) export_key;
    }
}

public class OpaqueLoginFinish : Object {
    public uint8[] finalization;
    public uint8[] session_key;
    public uint8[] export_key;

    public OpaqueLoginFinish (owned uint8[] finalization, owned uint8[] session_key, owned uint8[] export_key) {
        this.finalization = (owned) finalization;
        this.session_key = (owned) session_key;
        this.export_key = (owned) export_key;
    }
}

public interface OpaqueProtocol : Object {
    public abstract OpaqueStart registration_start (uint8[] password) throws OpaqueError;

    public abstract OpaqueRegistrationFinish registration_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError;

    public abstract OpaqueStart login_start (uint8[] password) throws OpaqueError;

    /** Fails with OpaqueError.FAILED for a wrong password, before the server learns anything about the attempt. */
    public abstract OpaqueLoginFinish login_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError;
}
