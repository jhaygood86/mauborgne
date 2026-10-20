/*
 * The native OPAQUE client. The protocol itself is covered by the Rust crate's own round-trip tests
 * (subprojects/opaque-bridge/tests), which have the server half; here the binding is checked: the
 * calls work, the buffers come back intact, and bad input is refused instead of crashing.
 */
namespace OpaqueTests {

    public void register () {
#if HAVE_OPAQUE
        Test.add_func ("/cloud/opaque_native_start_messages", test_start_messages);
        Test.add_func ("/cloud/opaque_native_messages_are_random", test_random);
        Test.add_func ("/cloud/opaque_native_rejects_garbage", test_garbage);
        Test.add_func ("/cloud/opaque_native_empty_password", test_empty_password);
#endif
    }

#if HAVE_OPAQUE
    private void test_start_messages () {
        var client = Mauborgne.OpaqueFactory.create ();
        var password = Mauborgne.CloudCrypto.password_bytes ("correct horse battery");

        try {
            var registration = client.registration_start (password);
            assert_true (registration.request.length > 0);
            assert_true (registration.state.length > 0);

            var login = client.login_start (password);
            assert_true (login.request.length > 0);
            assert_true (login.state.length > 0);
        } catch (Error e) {
            Test.message ("%s", e.message);
            Test.fail ();
        }
    }

    // fresh blinding every time, so the server cannot link two attempts by their request
    private void test_random () {
        var client = Mauborgne.OpaqueFactory.create ();
        var password = Mauborgne.CloudCrypto.password_bytes ("correct horse battery");

        try {
            var first = client.login_start (password);
            var second = client.login_start (password);

            assert_cmpstr (AegisManager.bytes_to_hex (first.request), CompareOperator.NE, AegisManager.bytes_to_hex (second.request));
        } catch (Error e) {
            Test.fail ();
        }
    }

    // a response that is not a valid OPAQUE message must fail cleanly, as a wrong password does
    private void test_garbage () {
        var client = Mauborgne.OpaqueFactory.create ();
        var password = Mauborgne.CloudCrypto.password_bytes ("correct horse battery");
        var id = "credential".data;

        try {
            var login = client.login_start (password);
            client.login_finish (password, login.state, "not an opaque response".data, id);
            Test.fail ();
        } catch (Error e) {
            assert_true (e is OpaqueError.FAILED);
        }

        try {
            var registration = client.registration_start (password);
            client.registration_finish (password, registration.state, new uint8[0], id);
            Test.fail ();
        } catch (Error e) {
            assert_true (e is OpaqueError.FAILED);
        }

        try {
            client.login_finish (password, new uint8[0], new uint8[0], id);
            Test.fail ();
        } catch (Error e) {
            assert_true (e is OpaqueError.FAILED);
        }
    }

    private void test_empty_password () {
        var client = Mauborgne.OpaqueFactory.create ();

        // never a crash, whichever way the library treats it
        try {
            client.login_start (new uint8[0]);
        } catch (Error e) {
            assert_true (e is OpaqueError.FAILED);
        }
    }
#endif
}
