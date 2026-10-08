#!/bin/sh
# Run the end-to-end tests of the ibus macOS integration in one shot.
#
# The script builds the integration from this source tree, sets up the
# layered test environment of macos/test-env.sh (the pristine upstream
# base, ibus-rime and the panel component), and runs the tests layer
# by layer:
#
#   1. conversion   the NSEvent conversion unit tests of the IMK front
#                   end (offline, no daemon)
#   2. xpc-hex      the hex compose round trip through the XPC bridge
#                   and the upstream simple engine
#   3. xpc-rime     nihao -> 你好 with the real rime engine
#   4. dbus-rime    the same through the D-Bus layer client, without
#                   the XPC bridge
#   5. panel        the candidate window data flow of the panel
#
# Usage: macos/run-e2e.sh [job ...]    (the default is all the jobs)
# The exit code is non-zero when any job fails; the environment is
# always cleaned up.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build-e2e"
PREFIX="$BUILD/prefix"
BASE="${IBUS_E2E_BASE:-$BUILD/base}"
LOG_DIR="${TMPDIR:-/tmp}/ibus-e2e"
DAEMON_LOG="$LOG_DIR/daemon.log"

cleanup () {
    pkill -f "$BASE/bin/ibus-daemon" 2>/dev/null || true
    for p in ibus-engine-rime ibus-engine-simple ibus-engine-libpinyin \
             ibus-memconf ibus-ui-macospanel ibus-macos-client \
             ibus-xpc-test-client ibus-xpc-bridge; do
        pkill -f "$p" 2>/dev/null || true
    done
    if [ -n "$BRIDGE_PLIST" ] && [ -f "$BRIDGE_PLIST" ]; then
        launchctl bootout "gui/$(id -u)/org.freedesktop.IBus.xpc.e2e" \
                >/dev/null 2>&1 || true
        rm -f "$BRIDGE_PLIST"
    fi
    rm -rf "$HOME/.config/ibus/bus" "$LOG_DIR/ibus-session" || true
}
trap cleanup EXIT

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------- build
job_build () {
    printf '==> build\n'
    export PKG_CONFIG_PATH="$(
            ls -d /opt/homebrew/Cellar/at-spi2-core/*/lib/pkgconfig |
                    head -1)${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    meson setup "$BUILD" --prefix="$PREFIX" \
            -Dtests=false -Dgtk-doc=false \
            >/dev/null
    ninja -C "$BUILD" >/dev/null
    ninja -C "$BUILD" install >/dev/null
    codesign --force --sign - "$PREFIX/libexec/IBusIM.app" >/dev/null 2>&1
}

# ------------------------------------------------------------- upstream
job_env () {
    printf '==> environment\n'
    IBUS_TEST_LOG="$DAEMON_LOG" \
            sh "$ROOT/macos/test-env.sh" "$BASE" \
                    "$PREFIX/libexec/ibus-ui-macospanel" >/dev/null

    # Bootstrap the XPC bridge with a temporary LaunchAgent; the
    # machines without the installed integration package have no
    # /Library/LaunchAgents entry for it.
    # The clients connect to the well-known org.freedesktop.IBus.xpc
    # name; take it over from any installed agent for this session.
    BRIDGE_PLIST="$HOME/Library/LaunchAgents/org.freedesktop.IBus.xpc.e2e.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    sed -e "s|@libexecdir@/ibus-xpc-bridge|$PREFIX/libexec/ibus-xpc-bridge|" \
            "$PREFIX/share/ibus/org.freedesktop.IBus.xpc.plist" \
            > "$BRIDGE_PLIST"
    for svc in org.freedesktop.IBus.xpc.e2e org.freedesktop.IBus.xpc; do
        launchctl bootout "gui/$(id -u)/$svc" >/dev/null 2>&1 || true
    done
    pkill -f ibus-xpc-bridge >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$BRIDGE_PLIST" \
            >/dev/null 2>&1 || true

    # the setup is only complete when the daemon runs
    sleep 1
    pgrep -f "$BASE/bin/ibus-daemon" > /dev/null
}

# ---------------------------------------------------------------- layer 1
job_conversion () {
    printf '==> conversion\n'
    "$PREFIX/libexec/IBusIM.app/Contents/MacOS/ibus-im" --selftest \
            2>/dev/null | head -1 | grep -qx 'conversion tests OK'
}

# ---------------------------------------------------------------- layer 2
job_xpc_hex () {
    printf '==> xpc-hex\n'
    "$PREFIX/libexec/ibus-xpc-test-client" 2>/dev/null |
            grep -q 'XPC bridge round trip OK'
}

# ---------------------------------------------------------------- layer 3
job_xpc_rime () {
    printf '==> xpc-rime\n'
    # The first rime session on a fresh machine compiles the schemas
    # (the essay dictionary is ~12MB), which exceeds the client's
    # engine wait; warm it up with a throwaway run first.
    "$PREFIX/libexec/ibus-xpc-test-client" --keys rime a >/dev/null 2>&1 ||
            true
    sleep 2
    "$PREFIX/libexec/ibus-xpc-test-client" --keys rime nihao 2>/dev/null |
            grep -q '你好'
}

# ---------------------------------------------------------------- layer 4
job_dbus_rime () {
    printf '==> dbus-rime\n'
    # The D-Bus client lingers after the stdin EOF by design; drive
    # it in the background and check the committed text in the
    # daemon log instead of the client stdout.
    rm -f "$LOG_DIR/dbus-rime.out"
    ( sh -c "{ sleep 4; printf 'nihao\\n'; sleep 8; } |
            $PREFIX/libexec/ibus-macos-client rime" \
            > "$LOG_DIR/dbus-rime.out" 2>&1 ) &
    local driver=$!
    ( sleep 40; pkill -f ibus-macos-client 2>/dev/null ) &
    local guard=$!
    wait $driver 2>/dev/null
    kill $guard >/dev/null 2>&1 || true
    pkill -f ibus-macos-client 2>/dev/null || true
    grep -q '你好' "$LOG_DIR/dbus-rime.out"
}

# ---------------------------------------------------------------- layer 5
job_properties () {
    printf '==> properties\n'
    # The engine registers its properties (the rime InputMode /
    # deploy / sync) and the panel renders the status item.
    grep -q 'register properties: 3 items' "$DAEMON_LOG" &&
    grep -q 'status item updated' "$DAEMON_LOG"
}

job_panel () {
    printf '==> panel\n'
    grep -q 'focus in' "$DAEMON_LOG" &&
    grep -q 'lookup table' "$DAEMON_LOG"
}

ALL_JOBS="build env conversion xpc_hex xpc_rime dbus_rime properties panel"
JOBS="${*:-$ALL_JOBS}"

FAILED=0
for job in $JOBS; do
    if "job_$job"; then
        printf '    PASS\n'
    else
        printf '    FAIL\n'
        FAILED=1
    fi
done

exit $FAILED
