#!/usr/bin/env bash
# Installs the official Sentry Godot SDK addon into addons/sentry (git-ignored).
#
#   tools/sentry/install_sentry_addon.sh            # pinned version below
#   SENTRY_GODOT_VERSION=2.5.0 tools/sentry/install_sentry_addon.sh
#
# The game runs fine WITHOUT the addon (CrashReporter.gd checks for it), so tests and fresh
# checkouts never depend on this download. CI runs it before tests and before every export.
# Requires Godot 4.5+ (Sentry SDK 1.x/2.x minimum). Docs: https://docs.sentry.io/platforms/godot/
set -euo pipefail

VERSION="${SENTRY_GODOT_VERSION:-2.4.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/addons/sentry"
STAMP="$DEST/.installed_version"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$VERSION" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "Sentry addon $VERSION already installed at addons/sentry"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading Sentry Godot SDK $VERSION"
if command -v gh >/dev/null 2>&1 && [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
    # The addon-only zip is "sentry-godot-<version>.zip" (the demo and debug-symbol zips are skipped).
    gh release download "$VERSION" -R getsentry/sentry-godot -D "$TMP" -p "sentry-godot-[0-9]*.zip"
else
    curl -fSL -o "$TMP/sentry-godot-$VERSION.zip" \
        "https://github.com/getsentry/sentry-godot/releases/download/$VERSION/sentry-godot-$VERSION.zip"
fi

ZIP="$(ls "$TMP"/sentry-godot-*.zip | head -1)"
unzip -q "$ZIP" -d "$TMP/x"
SRC="$(find "$TMP/x" -type d -path "*addons/sentry" | head -1)"
if [ -z "$SRC" ]; then
    echo "::error::addons/sentry not found inside $(basename "$ZIP")" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$ROOT/addons"
cp -R "$SRC" "$DEST"
if [ -n "${KEEP_PLATFORMS:-}" ]; then
    # CI: KEEP_PLATFORMS="android linux" drops the other platforms' binaries (keeps the APK lean).
    for dir in "$DEST"/bin/*/; do
        name="$(basename "$dir")"
        case " $KEEP_PLATFORMS " in *" $name "*) ;; *) rm -rf "$dir"; echo "    pruned bin/$name" ;; esac
    done
fi
echo "$VERSION" > "$STAMP"
echo "==> Installed Sentry addon $VERSION -> addons/sentry"
du -sh "$DEST" | sed 's/^/    size: /'
