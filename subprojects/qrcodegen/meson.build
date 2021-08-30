project(
    'qrcodegen', 'c',
    meson_version: '>= 0.49',
    version: '1.7.0'
)

inc = include_directories('.')

cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required : false)

qrcodegen = shared_library('qrcodegen',
    'qrcodegen.c',
    dependencies: m_dep,
    install: true
)

qrcodegen_dep = declare_dependency(include_directories : inc, link_with : qrcodegen)
