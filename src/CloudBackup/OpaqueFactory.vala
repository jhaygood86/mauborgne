/** The OPAQUE client this build uses: the native one when the Rust library was built in. */
namespace Mauborgne.OpaqueFactory {

    public OpaqueProtocol create () {
#if HAVE_OPAQUE
        return new NativeOpaqueClient ();
#else
        return new UnavailableOpaqueClient ();
#endif
    }

    /** Stands in when the native library is not part of the build, so Cloud Backup says so instead of crashing. */
    public class UnavailableOpaqueClient : Object, OpaqueProtocol {
        public OpaqueStart registration_start (uint8[] password) throws OpaqueError {
            throw new OpaqueError.UNAVAILABLE ("Cloud Backup is not available in this build");
        }

        public OpaqueRegistrationFinish registration_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
            throw new OpaqueError.UNAVAILABLE ("Cloud Backup is not available in this build");
        }

        public OpaqueStart login_start (uint8[] password) throws OpaqueError {
            throw new OpaqueError.UNAVAILABLE ("Cloud Backup is not available in this build");
        }

        public OpaqueLoginFinish login_finish (uint8[] password, uint8[] state, uint8[] response, uint8[] credential_id) throws OpaqueError {
            throw new OpaqueError.UNAVAILABLE ("Cloud Backup is not available in this build");
        }
    }
}
