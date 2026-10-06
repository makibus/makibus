configure_file(
  input: 'org.freedesktop.IBus.xpc.plist.in',
  output: '@BASENAME@',
  configuration: {
    'libexecdir': get_option('prefix') / get_option('libexecdir'),
  },
  install: true,
  install_dir: pkgdatadir,
)

executable('ibus-xpc-bridge',
  files('main.mm'),
  dependencies: [ glib_dep, gobject_dep, gio_dep, ibus_dep ],
  include_directories: config_h_inc,
  objcpp_args: [ '-fobjc-arc' ],
  link_args: [ '-framework', 'Foundation' ],
  install: true,
  install_dir: get_option('libexecdir'),
)

executable('ibus-xpc-test-client',
  files('test-client.mm'),
  dependencies: [ glib_dep, gobject_dep, gio_dep, ibus_dep ],
  include_directories: config_h_inc,
  objcpp_args: [ '-fobjc-arc' ],
  link_args: [ '-framework', 'Foundation' ],
  install: true,
  install_dir: get_option('libexecdir'),
)
