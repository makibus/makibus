# The Input Method Kit (IMK) front end is assembled into an .app
# bundle so that it can be copied to ~/Library/Input Methods/.

ibus_im_conf = configuration_data()
ibus_im_conf.set('VERSION', meson.project_version())

ibus_im_sources = files(
  'IBusInputController.mm',
  'IBusKeyConvert.mm',
  'IBusXpcClient.mm',
  'main.mm',
)

ibus_im_deps = [
  glib_dep,
  gobject_dep,
  gio_dep,
  ibus_dep,
]

executable('ibus-im',
  ibus_im_sources,
  dependencies: ibus_im_deps,
  include_directories: [ config_h_inc,
                         include_directories('../xpc') ],
  objcpp_args: [ '-fobjc-arc' ],
  link_args: [
    '-framework', 'Foundation',
    '-framework', 'AppKit',
    '-framework', 'InputMethodKit',
    '-framework', 'Carbon',
  ],
  install: true,
  install_dir: get_option('libexecdir') / 'IBusIM.app' / 'Contents' / 'MacOS',
)

configure_file(
  input: 'Info.plist.in',
  output: 'Info.plist',
  configuration: ibus_im_conf,
  install: true,
  install_dir: get_option('libexecdir') / 'IBusIM.app' / 'Contents',
)
