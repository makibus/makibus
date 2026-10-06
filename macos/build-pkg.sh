#!/bin/sh
# Build the installer package (.pkg) of the ibus macOS integration.
#
# The package installs everything machine-wide, which avoids the
# per-user quirks of the Installer:
#
#   IBusIM.app                       -> /Library/Input Methods
#   ibus-xpc-bridge, macospanel      -> /usr/local/ibus-macos/bin
#   libibus copy                     -> /usr/local/ibus-macos/lib
#   LaunchAgent                      -> /Library/LaunchAgents
#   macospanel component template    -> /usr/local/ibus-macos
#
# The postinstall script registers the panel component in the ibus
# component directory of the installed ibus base and bootstraps the
# LaunchAgent for the console user.
#
# Usage: macos/build-pkg.sh <integration-package-dir> <output.pkg> [version]
#   <integration-package-dir>  the IBusMacOS-<version> directory
#                              assembled by build-integration.sh

set -e

# Avoid the AppleDouble files (._*) of the extended attributes in
# the staging tree.
export COPYFILE_DISABLE=1

PKGDIR="$1"
COMPONENT_PLIST="$(mktemp -d)/components.plist"
OUT="${2:-IBusMacOS.pkg}"
VERSION="${3:-1.5.35}"

if [ -z "$PKGDIR" ] || [ ! -d "$PKGDIR" ]; then
    echo "Usage: $0 <integration-package-dir> [output.pkg] [version]" >&2
    exit 1
fi

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$(mktemp -d)/root"
SCRIPTS="$(mktemp -d)"
trap 'rm -rf "$(dirname "$STAGING")" "$SCRIPTS"' EXIT

BASE=/usr/local/ibus-macos
SERVICE=org.freedesktop.IBus.xpc

# The machine-wide layout; bin/../lib keeps the @rpath of the
# packaged binaries working.
mkdir -p "$STAGING/Library/Input Methods" \
         "$STAGING$BASE/bin" "$STAGING$BASE/lib" \
         "$STAGING/Library/LaunchAgents"

cp -R "$PKGDIR/IBusIM.app" "$STAGING/Library/Input Methods/"
cp "$PKGDIR/libexec/ibus-xpc-bridge" "$STAGING$BASE/bin/"
cp "$PKGDIR/libexec/ibus-ui-macospanel" "$STAGING$BASE/bin/"
cp "$PKGDIR/lib/"libibus-*.dylib "$STAGING$BASE/lib/"

# The install paths are known at the build time; fill the
# placeholders directly.
sed -e "s|@libexecdir@/ibus-xpc-bridge|$BASE/bin/ibus-xpc-bridge|" \
        "$PKGDIR/LaunchAgents/$SERVICE.plist" \
        > "$STAGING/Library/LaunchAgents/$SERVICE.plist"
sed -e "s|@libexecdir@/ibus-ui-macospanel|$BASE/bin/ibus-ui-macospanel|" \
        "$PKGDIR/macospanel.xml" \
        > "$STAGING$BASE/macospanel.xml"

# The postinstall script
sed -e "s|@BASE@|$BASE|g" \
        "$SCRIPTDIR/pkg-postinstall.sh.in" > "$SCRIPTS/postinstall"
chmod +x "$SCRIPTS/postinstall"

# pkgbuild turns the extended attributes into the AppleDouble
# files; drop them (the code signatures live in the binaries and the
# CodeResources files, not in the attributes).
xattr -rc "$STAGING" 2>/dev/null || true
find "$STAGING" -name '._*' -delete

# Disable the relocation of the app bundle: the macOS Installer
# upgrades an existing app with the same bundle identifier in place,
# which on a development machine would divert the installation to
# the build output copy instead of /Library/Input Methods.
pkgbuild --analyze --root "$STAGING" "$COMPONENT_PLIST" >/dev/null
plutil -replace     "0.RootRelativeBundlePath" -string "Library/Input Methods/IBusIM.app" \
    "$COMPONENT_PLIST" >/dev/null 2>&1 || true
python3 - "$COMPONENT_PLIST" <<'PYEOF2'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    comps = plistlib.load(f)
for c in comps:
    if c.get("RootRelativeBundlePath", "").endswith(".app"):
        c["IsRelocatable"] = False
with open(sys.argv[1], "wb") as f:
    plistlib.dump(comps, f)
PYEOF2

pkgbuild \
    --root "$STAGING" \
    --identifier org.freedesktop.IBus.macos \
    --version "$VERSION" \
    --scripts "$SCRIPTS" \
    --component-plist "$COMPONENT_PLIST" \
    --install-location / \
    "$OUT"

echo "Built $OUT"
echo "Install with: sudo installer -pkg $OUT -target /"
