#!/bin/sh
# Assemble the distributable macOS integration package of the ibus
# XPC bridge and the IMK front end from an installed ibus prefix.
#
# The package is self-contained except for the Homebrew glib, and is
# independent of the ibus installation: the users build and install
# the ibus daemon, the engines and the panel by themselves and only
# install this package for the macOS integration.
#
# Usage: macos/build-integration.sh <ibus-prefix> <output-dir> [version]

set -e

PREFIX="$1"
OUT="$2"
SERVICE="org.freedesktop.IBus.xpc"
VERSION="${3:-$(basename "$PREFIX")}"

if [ -z "$PREFIX" ] || [ -z "$OUT" ]; then
    echo "Usage: $0 <ibus-prefix> <output-dir> [version]" >&2
    exit 1
fi

APP="$OUT/IBusMacOS-$VERSION"
LIBIBUS="$(ls "$PREFIX"/lib/libibus-1.0.*.dylib | head -1)"
IBUS_LIBDIR="$(basename "$LIBIBUS")"

rm -rf "$APP"
mkdir -p "$APP/lib" "$APP/libexec" "$APP/LaunchAgents"

# The components.  The installed plist contains the absolute
# libexecdir of the build prefix; restore the placeholder so that
# the user side installer fills the installation path.
cp -R "$PREFIX/libexec/IBusIM.app" "$APP/"
cp "$PREFIX/libexec/ibus-xpc-bridge" "$APP/libexec/"
sed -e "s|$PREFIX/libexec/ibus-xpc-bridge|@libexecdir@/ibus-xpc-bridge|" \
        "$PREFIX/share/ibus/org.freedesktop.IBus.xpc.plist" \
        > "$APP/LaunchAgents/$SERVICE.plist"
cp "$LIBIBUS" "$APP/lib/"

# Redirect the libibus references to the packaged copy through
# @rpath, so that the binaries do not depend on the build prefix.
install_name_tool -id "@rpath/$IBUS_LIBDIR" "$APP/lib/$IBUS_LIBDIR"
install_name_tool -change "$PREFIX/lib/$IBUS_LIBDIR" \
        "@rpath/$IBUS_LIBDIR" "$APP/libexec/ibus-xpc-bridge"
install_name_tool -add_rpath "@executable_path/../lib" \
        "$APP/libexec/ibus-xpc-bridge"
install_name_tool -change "$PREFIX/lib/$IBUS_LIBDIR" \
        "@rpath/$IBUS_LIBDIR" "$APP/IBusIM.app/Contents/MacOS/ibus-im"
install_name_tool -add_rpath "@executable_path/../../../lib" \
        "$APP/IBusIM.app/Contents/MacOS/ibus-im"

# Sign the binaries; the real distributions replace the ad-hoc
# signatures with the Developer ID ones.
codesign --force --sign - "$APP/lib/$IBUS_LIBDIR" >/dev/null 2>&1
codesign --force --sign - "$APP/libexec/ibus-xpc-bridge" >/dev/null 2>&1
codesign --force --sign - "$APP/IBusIM.app" >/dev/null 2>&1

# The user side installer
sed -e "s|@IBUS_LIBDIR@|$IBUS_LIBDIR|g" \
    "$(dirname "$0")/install-integration.sh.in" > "$APP/install.sh"
chmod +x "$APP/install.sh"

echo "Assembled $APP"
echo "The package requires the Homebrew glib formula for libibus."
