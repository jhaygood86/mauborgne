test_exe = executable(
    'test-mauborgne',
    'main.vala',
    'support.vala',
    'test-otp.vala',
    'test-aegis.vala',
    'test-qr.vala',
    'test-library.vala',
    'test-cloud.vala',
    'test-cloud-service.vala',
    'test-opaque.vala',
    'test-ui.vala',
    config_file,
    mauborgne_sources,
    dependencies: mauborgne_deps,
    install: false
)

# Each suite is a GLib test path; run a single one with `meson test otp`
foreach suite : ['otp', 'aegis', 'qr', 'library', 'cloud', 'ui']
    test(suite, test_exe,
        args: ['-p', '/' + suite],
        # no input method daemon and no accessibility bus are needed (or present) on a headless builder
        env: {
            'MAURBORGNE_TEST': '1',
            'GTK_IM_MODULE': 'gtk-im-context-simple',
            'GTK_A11Y': 'none'
        },
        timeout: 120
    )
endforeach
