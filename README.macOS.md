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

   The bridge runs at load and is kept alive by launchd with the
   LaunchAgent plist installed at
   `share/ibus/org.freedesktop.IBus.xpc.plist`, and reconnects to the
   ibus-daemon automatically when the daemon is restarted.  The
   requests which arrive before the D-Bus connection is established
   are buffered until the connection is ready:

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

 * `IBusIM.app` (`client/imk/`) - the Input Method Kit (IMK) front
   end.  `IBusInputController` receives the key events with
   `handleEvent:client:`, converts the NSEvent to the ibus key event
   with the macOS virtual keycode table (`ibus-mac-keycode.h`), and
   applies the engine outputs with the IMK text input APIs:
   `setMarkedText` for the pre-edit text and `insertText` for the
   committed text.  The modifier transitions are forwarded as the
   individual ibus key events from the NSFlagsChanged events, which
   the compose sequences like Ctrl+Shift+U rely on.  The candidates
   and the auxiliary texts are rendered by the native ibus panel
   instead of the IMK front end, and the input method menu lists the
   ibus engines to switch the global engine.

   Install the input method and enable it in System Settings ->
   Keyboard -> Input Sources:

   ```sh
   cp -R $prefix/libexec/IBusIM.app ~/Library/Input\ Methods/
   # Log out and log in again, then add "IBus" in Input Sources.
   ```

   Verify the XPC round trip of the front end executable without
   enabling it:

   ```sh
   ~/Library/Input\ Methods/IBusIM.app/Contents/MacOS/ibus-im --selftest
   ```

   The App Sandbox was verified to work with the XPC bridge: a
   sandboxed .app re-signed with `com.apple.security.app-sandbox`
   completed the hex compose round trip, provided the
   `com.apple.security.temporary-exception.mach-lookup.global-name`
   entitlement for `org.freedesktop.IBus.xpc` (see
   `client/xpc/ibus-xpc-sandbox.entitlements`).  Note that a plain
   binary cannot enable the sandbox at all - it aborts in
   `_libsecinit_appsandbox` during the dyld initialization - and that
   the mach-lookup temporary exception may not be accepted by the App
   Store review; the Developer ID and the local distributions work.

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

## Distribute the macOS integration package

The XPC bridge and the IMK front end can be distributed
independently of the ibus installation, as a single package:

 * IBusIM.app is self-contained and only links the system
   frameworks; the ibus keysyms of the front end come from the
   `ibus-keys.h` header instead of libibus.
 * The ibus-xpc-bridge links libibus, whose only transitive
   dependency beyond the system libraries is the Homebrew glib
   formula, and the packaged libibus copy is loaded through @rpath.

Build and install the ibus daemon, the engines and the panel from
the source, then assemble the package from the installed prefix:

```sh
meson setup build --prefix=$HOME/ibus-prefix   # -Dxpc-bridge=true -Dimk=true
ninja -C build && ninja -C build install
macos/build-integration.sh $HOME/ibus-prefix . 1.5.35
```

The users install the package for their own user, which requires
the Homebrew glib formula:

```sh
brew install glib
./install.sh    # in the unpacked IBusMacOS-<version> directory
```

The installer copies the bridge and libibus to
`~/.local/lib/ibus-macos`, IBusIM.app to `~/Library/Input Methods`
and the LaunchAgent to `~/Library/LaunchAgents`, and loads the
agent.  Replace the ad-hoc code signatures with the Developer ID
signatures for the real distributions.

## Known issues

 * The `/ibus/async-apis` test in `ibus-bus` can be flaky on macOS
   due to the timing of the address file monitoring with the file
   system events.

 * The socket path falls back to `/tmp` because
   `$XDG_CACHE_HOME/ibus` is only used on Linux.

 * The machine ID fallback in `ibus_get_local_machine_id()` is used
   since `/var/lib/dbus/machine-id` does not exist on macOS.

 * The IMK front end (`client/imk/`) is a prototype: the key events,
   the pre-edit and the commit texts work through the XPC bridge and
   the selftest also covers the NSEvent conversion, but it has not
   been polished for the daily use yet, e.g. the autorepeat handling
   and the dead keys of the macOS layouts.
