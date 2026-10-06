#!/bin/sh
# Build and install the pristine upstream ibus as the base of the
# macOS integration package.
#
# The upstream master needs no source patches on macOS; the recipe
# only passes the meson options:
#
#   tests=false          the test code uses SOCK_CLOEXEC, which is
#                        not implemented on macOS
#   gtk-doc=false        the gtk-doc tools do not generate the HTML
#                        documents on macOS
#   appindicator=false   dbusmenu is not packaged for Homebrew
#   memconf=true         dconf is not available and ibus-daemon
#                        needs a config component
#   xim=disabled         the Homebrew GTK3 provides the Quartz
#                        backend only and ibus-x11 needs gdkx.h
#   ui=false             the GTK3 panel is replaced by the native
#                        macOS panel of the integration package
#   emoji-dict=false     the Unicode emoji and UCD data files are
#   unicode-dict=false   not shipped with macOS
#   x11-localedata-dir   the compose table source of the simple
#                        engine; without the X11 dependency the
#                        default path falls back to the prefix where
#                        the data does not exist
#
# Usage: macos/build-upstream.sh [ref] [prefix]
#   ref     the upstream git ref; the default is master
#   prefix  the install prefix; the default is $HOME/.local/ibus

set -e

REF="${1:-master}"
PREFIX="${2:-$HOME/.local/ibus}"
SRC="${TMPDIR:-/tmp}/ibus-upstream-src-$REF"

if [ ! -d "$SRC" ]; then
    echo "Cloning the upstream ibus ($REF)"
    git clone --depth 1 --branch "$REF" \
            https://github.com/ibus/ibus.git "$SRC" \
        || git clone --depth 1 \
            https://github.com/ibus/ibus.git "$SRC"
fi

# The Homebrew at-spi2-core provides atk.pc in the Cellar directory
# only, which the gtk3 im modules of the base require.
ATSPI_PC=$(ls /opt/homebrew/Cellar/at-spi2-core/*/lib/pkgconfig/atk.pc \
        2>/dev/null | head -1)
if [ -n "$ATSPI_PC" ]; then
    export PKG_CONFIG_PATH="$(dirname "$ATSPI_PC")${
            PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

cd "$SRC"
meson setup build \
    -Dtests=false \
    -Dgtk-doc=false \
    -Dappindicator=false \
    -Dmemconf=true \
    -Dxim=disabled \
    -Dui=false \
    -Demoji-dict=false \
    -Dunicode-dict=false \
    -Dx11-localedata-dir="$(brew --prefix)/share/X11/locale" \
    --prefix="$PREFIX"
ninja -C build install

cat <<EOF

Upstream ibus installed to $PREFIX.
Run the daemon with:
  $PREFIX/bin/ibus-daemon --replace --verbose
and assemble the integration package with macos/build-integration.sh.
EOF
