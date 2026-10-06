# IBus on macOS

IBus can be built and run natively on macOS since 1.5.35.  The
ibus-daemon, the simple (xkb) engines, the config module (memconf) and
the GTK3/GTK4 IM modules work with the Homebrew libraries, and two
native components are added for macOS:

 * `ibus-macos-client` (`client/macos/`) - a test purpose client which
   sends the characters in the standard input to the current engine
   through the ibus-daemon and prints the engine outputs, e.g. the
   pre-edit text and the committed text.  It also provides the macOS
   virtual keycode (kVK_ANSI_*) to XKB keycode conversion table, which
   can be reused by a real macOS integration implemented with Input
   Method Kit (IMK).

 * `ibus-ui-macospanel` (`ui/macospanel/`) - the native candidate
   window panel which implements the `org.freedesktop.IBus.Panel`
   D-Bus service with `IBusPanelService` and renders the candidates
   with AppKit.  It replaces the GTK3 panel, which can be built back
   with `-Dmacospanel=false`.

 * `ibus-xpc-bridge` (`client/xpc/`) - the XPC bridge for the
   sandboxed clients, e.g. the Input Method Kit (IMK) input methods
   distributed in the App Store.  It exposes the ibus input context
   as the launchd Mach service `org.freedesktop.IBus.xpc` and talks
   to the ibus-daemon through the regular D-Bus protocol:

   ```
   sandboxed client --XPC--> ibus-xpc-bridge --D-Bus--> ibus-daemon
                                                             |
                                                         engines
   ```

   The bridge is launched by launchd on demand with the LaunchAgent
   plist installed at `share/ibus/org.freedesktop.IBus.xpc.plist`:

   ```sh
   cp $prefix/share/ibus/org.freedesktop.IBus.xpc.plist \
      ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) \
      ~/Library/LaunchAgents/org.freedesktop.IBus.xpc.plist
   ```

   The environment of the launchd agents is not inherited from the
   shell, so the `IBUS_ADDRESS_FILE` of the ibus-daemon must be
   published with `launchctl setenv IBUS_ADDRESS_FILE <path>` (or use
   the default address file location without `IBUS_ADDRESS_FILE`).
   On macOS 13+ the connections can be restricted to the signed
   clients with the code signing requirement language by setting
   `IBUS_XPC_CODE_SIGNING_REQUIREMENT` in the launchd environment,
   e.g. `launchctl setenv IBUS_XPC_CODE_SIGNING_REQUIREMENT 'identifier
   "com.example.ime"'`.  `ibus-xpc-test-client` verifies the round
   trip with the hex compose sequence, which commits "A" if the
   daemon is started with `IBUS_ENABLE_CTRL_SHIFT_U=1`.

Both components are enabled by default on macOS and cannot be built on
other platforms (`-Dmacos-client=false` / `-Dmacospanel=false` to
disable them explicitly).

## Build

```sh
brew install meson ninja pkg-config \
    glib dbus vala libnotify gtk+3 gtk4 iso-codes xkeyboard-config \
    libx11 gobject-introspection pygobject3 at-spi2-core gettext

# atk.pc is installed in the Cellar directory only.
export PKG_CONFIG_PATH=$(brew --prefix)/Cellar/at-spi2-core/*/lib/pkgconfig

meson setup build --prefix=$HOME/ibus-prefix
ninja -C build
ninja -C build install
```

Notes:

 * The GTK3 and GTK4 formulae in Homebrew provide the Quartz backend
   only, so the XIM (ibus-x11) and Wayland frontends are disabled
   automatically.  The GTK IM modules are still built for the Homebrew
   GTK applications.

 * The emoji and Unicode dictionaries are disabled automatically
   because their data files are not shipped with macOS.  Point
   `-Dunicode-emoji-dir=`, `-Demoji-annotation-dir=` and `-Ducd-dir=`
   to the data files to enable them.

 * dconf is not available on macOS and the memconf config module is
   enabled by default for the ibus-daemon config component.

 * gtk-doc does not generate the HTML documents on macOS; configure
   with `-Dgtk-doc=false` when `meson install` fails in the docs
   target.

## Run

macOS does not provide a session D-Bus and the Homebrew dbus formula
listens through launchd by default, so start a private session bus
with an explicit address:

```sh
mkdir -p /tmp/ibus-session
export DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork \
    --print-address=1 --address=unix:tmpdir=/tmp/ibus-session)
```

Then run the ibus-daemon.  It starts the memconf config module and
the native macOS panel automatically:

```sh
export PATH=$HOME/ibus-prefix/bin:$PATH
ibus-daemon --replace --verbose
```

The test client sends the input lines to the current engine.  Note
that the xkb engines work in the "disabled IM" mode and let the plain
ASCII key events pass through to the client application (see the
RH#769133 comment in `src/ibusenginesimple.c`), so the commit texts
are only printed for the engine outputs, e.g. the compose sequences.
Type `quit` to exit:

```sh
$HOME/ibus-prefix/libexec/ibus-macos-client
```

The hex compose sequence (`Ctrl+Shift+U`, hex digits, `Space`) can be
used to verify the whole input method round trip if the daemon is
started with `IBUS_ENABLE_CTRL_SHIFT_U=1`:

```sh
IBUS_ENABLE_CTRL_SHIFT_U=1 ibus-daemon --replace --verbose
```

## Known issues

 * The `/ibus/async-apis` test in `ibus-bus` can be flaky on macOS
   due to the timing of the address file monitoring with the file
   system events.

 * The socket path falls back to `/tmp` because
   `$XDG_CACHE_HOME/ibus` is only used on Linux.

 * The machine ID fallback in `ibus_get_local_machine_id()` is used
   since `/var/lib/dbus/machine-id` does not exist on macOS.

 * The real macOS integration with Input Method Kit (IMK), which
   converts the NSEvent key events to the ibus key events and commits
   texts through the IMK APIs, is not implemented yet.  The XPC
   bridge provides the transport for it; the sandboxed IMK app would
   connect to the `org.freedesktop.IBus.xpc` Mach service, export the
   engine output callbacks and drive the input context with the
   `IBusXpcInputContext` protocol in `client/xpc/main.mm`.
