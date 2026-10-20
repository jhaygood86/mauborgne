project(
    'io.github.jhaygood86.mauborgne', 'vala', 'c',
    meson_version: '>= 1.0',
    version: '0.9.0'
)

vapi_dir = meson.current_source_dir() / 'vapi'
add_project_arguments(['--vapidir', vapi_dir], language: 'vala')

fs = import('fs')
gnome = import('gnome')
i18n = import('i18n')

add_project_arguments('-DGETTEXT_PACKAGE="@0@"'.format (meson.project_name()), language:'c')

config_data = configuration_data()
config_data.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
config_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
config_data.set_quoted('VERSION', meson.project_version())
config_file = configure_file(
    input: 'src/Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

icon_res = gnome.compile_resources(
    'mauborgne-icon-resources',
    join_paths('data', 'gresource.xml'),
    source_dir: 'data'
)

# Cloud Backup's OPAQUE client is the Rust opaque-bridge crate. Without it (or without cargo) the app
# still builds; Cloud Backup then says it is unavailable (see subprojects/opaque-bridge/README.md).
opaque_dir = meson.project_source_root() / 'subprojects' / 'opaque-bridge'
cargo = find_program('cargo', required: false)
opaque_deps = []

if fs.exists(opaque_dir / 'Cargo.toml') and cargo.found()
    opaque_lib = custom_target(
        'opaque-bridge',
        output: 'libopaque_bridge.a',
        command: [
            find_program('build-aux/build-opaque.sh'),
            opaque_dir,
            '@OUTPUT@',
            meson.current_build_dir() / 'cargo-target'
        ],
        console: true,
        build_by_default: true
    )

    opaque_deps += declare_dependency(
        sources: opaque_lib,
        link_args: [opaque_lib.full_path(), '-lm', '-ldl', '-lpthread'],
        include_directories: include_directories('subprojects/opaque-bridge/include')
    )
    opaque_deps += meson.get_compiler('vala').find_library('opaque-bridge', dirs: vapi_dir)

    add_project_arguments('--define=HAVE_OPAQUE', language: 'vala')
endif

quirc_proj = subproject('quirc')
quirc_dep = quirc_proj.get_variable('quirc_dep')

qrcodegen_proj = subproject('qrcodegen')
qrcodegen_dep = qrcodegen_proj.get_variable('qrcodegen_dep')

mauborgne_deps = opaque_deps + [
    dependency('gobject-2.0'),
    dependency('gtk4'),
    dependency('libadwaita-1', version: '>=1.5'),
    dependency('libportal'),
    dependency('libportal-gtk4'),
    dependency('cotp'),
    dependency('libsecret-1'),
    dependency('libsoup-3.0'),
    dependency('webkitgtk-6.0'),
    meson.get_compiler('vala').find_library('webkitgtk-6.0', dirs: vapi_dir),
    meson.get_compiler('vala').find_library('javascriptcore-6.0', dirs: vapi_dir),
    dependency('gee-0.8'),
    dependency('json-glib-1.0'),
    quirc_dep,
    meson.get_compiler('vala').find_library('quirc', dirs: vapi_dir),
    qrcodegen_dep,
    meson.get_compiler('vala').find_library('qrcodegen', dirs: vapi_dir),
    meson.get_compiler('c').find_library('libgcrypt'),
    meson.get_compiler('vala').find_library('gcrypt', dirs: vapi_dir)
]

# Everything except the application entry points, so the tests can build on it
mauborgne_sources = files(
    'src/QrHelpers.vala',
    'src/OneTimePad.vala',
    'src/OneTimePadLibrary.vala',
    'src/Services/AegisManager.vala',
    'src/Services/JsonHelpers.vala',
    'src/Services/Models/AegisVault.vala',
    'src/Services/Models/AegisVaultContent.vala',
    'src/CloudBackup/CloudBackupFlow.vala',
    'src/CloudBackup/CloudBackupService.vala',
    'src/CloudBackup/CloudBackupTypes.vala',
    'src/CloudBackup/CloudCrypto.vala',
    'src/CloudBackup/CloudSettings.vala',
    'src/CloudBackup/CloudSyncService.vala',
    'src/CloudBackup/LicenseService.vala',
    'src/CloudBackup/NativeOpaqueClient.vala',
    'src/CloudBackup/Opaque.vala',
    'src/CloudBackup/OpaqueFactory.vala',
    'src/CloudBackup/SyncMerge.vala',
    'src/CloudBackup/SyncSnapshot.vala',
    'src/CloudBackup/Threads.vala',
    'src/Widgets/CloudDialogs.vala',
    'src/Widgets/WebPageDialog.vala',
    'src/Widgets/CreatePasswordDialog.vala',
    'src/Widgets/EditDialog.vala',
    'src/Widgets/IssuerAvatar.vala',
    'src/Widgets/ExportWindow.vala',
    'src/Widgets/OneTimePadView.vala',
    'src/Widgets/PasswordDialog.vala',
    'src/Widgets/PasswordPromptDialog.vala',
    'src/Widgets/SetupKeyDialog.vala',
)

executable(
    meson.project_name(),
    icon_res,
    config_file,
    'src/Application.vala',
    'src/MainWindow.vala',
    mauborgne_sources,
    dependencies: mauborgne_deps,
    install: true
)

gnome.post_install(
    glib_compile_schemas: true,
    gtk_update_icon_cache: true,
    update_desktop_database: true
)

subdir('data')
subdir('po')
subdir('tests')
