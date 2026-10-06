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
  objcpp_args: [ '-fobjc-arc' ],
  link_args: [ '-framework', 'Foundation', '-framework', 'AppKit' ],
  install: true,
  install_dir: get_option('libexecdir'),
)
