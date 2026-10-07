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

# The front end is self-contained so that it can be distributed
# independently of the ibus installation: the ibus keysyms and the
# modifier masks come from ibus-keys.h instead of libibus.
ibus_im_deps = []

executable('ibus-im-register',
  files('ibus-im-register.mm'),
  dependencies: ibus_im_deps,
  include_directories: [ config_h_inc,
                         include_directories('../xpc') ],
  objcpp_args: [ '-fobjc-arc' ],
  link_args: [
    '-framework', 'Foundation',
    '-framework', 'Carbon',
  ],
  install: true,
  install_dir: get_option('libexecdir') / 'IBusIM.app' / 'Contents' / 'MacOS',
)

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

install_data(
  'ibus.icns',
  install_dir: get_option('libexecdir') / 'IBusIM.app' / 'Contents' / 'Resources',
)
