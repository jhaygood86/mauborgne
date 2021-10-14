install_data('test_qr_code.png')

icon_sizes = ['128']

foreach i : icon_sizes
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i, 'apps'),
        rename: meson.project_name() + '.svg'
    )
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i + '@2', 'apps'),
        rename: meson.project_name() + '.svg'
    )
endforeach

i18n.merge_file(
    input: 'io.github.jhaygood86.mauborgne.desktop.in',
    output: 'io.github.jhaygood86.mauborgne.desktop',
    po_dir: join_paths(meson.source_root(), 'po'),
    type: 'desktop',
    install: true,
    install_dir: join_paths(get_option('datadir'), 'applications')
)

i18n.merge_file(
    input: 'io.github.jhaygood86.mauborgne.appdata.xml.in',
    output: 'io.github.jhaygood86.mauborgne.appdata.xml',
    po_dir: join_paths(meson.source_root(), 'po'),
    type: 'xml',
    install: true,
    install_dir: join_paths(get_option('datadir'), 'metainfo'),
)
