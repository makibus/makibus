configure_file(
  input: 'macospanel.xml.in',
  output: '@BASENAME@',
  configuration: {
    'VERSION': meson.project_version(),
    'libexecdir': get_option('prefix') / get_option('libexecdir'),
  },
  install: true,
  install_dir: pkgdatadir / 'component',
)

executable('ibus-ui-macospanel',
  files('main.mm'),
  dependencies: [ glib_dep, gobject_dep, gio_dep, ibus_dep ],
  include_directories: config_h_inc,
  c_args: [ '-DG_LOG_DOMAIN="IBUS"' ],
  objcpp_args: [ '-fobjc-arc', '-DG_LOG_DOMAIN="IBUS"' ],
  link_args: [ '-framework', 'Foundation', '-framework', 'AppKit' ],
  install: true,
  install_dir: get_option('libexecdir'),
)
