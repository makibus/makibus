cask "ibus-macos" do
  # Homebrew Cask of the ibus macOS integration.
  #
  # The cask carries the installer package built by
  # macos/build-pkg.sh; the installation layout and the postinstall
  # logic live in the package itself:
  #
  #   IBusIM.app                    -> /Library/Input Methods
  #   bridge, panel and libibus     -> /usr/local/ibus-macos
  #   LaunchAgent                   -> /Library/LaunchAgents
  #
  # The upstream ibus base (meson options recipe:
  # macos/build-upstream.sh) and the Homebrew glib formula are
  # expected to be installed already.
  version "1.5.35"
  sha256 :no_check

  # Replace with the release URL for the real distributions, e.g.
  # url "https://github.com/<org>/ibus/releases/download/#{version}/IBusMacOS-#{version}.pkg"
  url "file:///tmp/IBusMacOS-#{version}.pkg"
  name "IBus macOS integration"
  desc "XPC bridge, IMK front end and native panel for ibus on macOS"
  homepage "https://github.com/ibus/ibus"

  pkg "IBusMacOS-#{version}.pkg"

  uninstall_preflight do
    # The package keeps no uninstall receipt mapping for the
    # registered component; clean it up explicitly.
    FileUtils.rm_f "/opt/homebrew/share/ibus/component/macospanel.xml"
    FileUtils.rm_f "/usr/local/share/ibus/component/macospanel.xml"
  end
  uninstall delete: [
    "/Library/Input Methods/IBusIM.app",
    "/Library/LaunchAgents/org.freedesktop.IBus.xpc.plist",
  ],
  rmdir: [
    "/usr/local/ibus-macos",
  ]
end
