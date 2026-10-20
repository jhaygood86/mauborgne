int main (string[] args) {
    // Keep the tests away from the real pads: the library reads and writes
    // the user data dir, which glib caches on first use.
    var tmp_dir = DirUtils.make_tmp ("mauborgne-test-XXXXXX");
    var data_dir = Path.build_filename (tmp_dir, "data");
    DirUtils.create_with_parents (data_dir, 0700);
    Environment.set_variable ("XDG_DATA_HOME", data_dir, true);

    Test.init (ref args);

    // A headless builder (xvfb, no session bus) makes GTK and IBus warn that they cannot reach D-Bus.
    // That says nothing about the code under test, so those warnings are not failures; all others are.
    Test.log_set_fatal_handler ((domain, level, message) => {
        return !TestSupport.is_missing_bus_warning (domain, message);
    });

    TestSupport.write_library_fixtures ();

    OtpTests.register ();
    AegisTests.register ();
    QrTests.register ();
    LibraryTests.register ();
    CloudTests.register ();
    CloudServiceTests.register ();
    OpaqueTests.register ();
    UiTests.register ();

    return Test.run ();
}
