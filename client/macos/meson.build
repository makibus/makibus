ibus_macos_client_sources = files(
  'main.mm',
)

executable('ibus-macos-client',
  ibus_macos_client_sources,
  dependencies: [ glib_dep, gobject_dep, gio_dep, ibus_dep ],
  include_directories: config_h_inc,
  install: true,
  install_dir: get_option('libexecdir'),
)
