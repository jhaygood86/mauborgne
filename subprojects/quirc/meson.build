project(
    'quirc', 'c',
    meson_version: '>= 0.49',
    version: '1.1'
)

add_project_arguments('-DQUIRC_MAX_REGIONS=65534', language:'c')

inc = include_directories('.')

cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required : false)

quirc = shared_library('quirc',
    'decode.c',
    'identify.c',
    'quirc.c',
    'version_db.c',
    dependencies: m_dep,
    install: true
)

quirc_dep = declare_dependency(include_directories : inc, link_with : quirc)
