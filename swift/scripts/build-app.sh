#!/usr/bin/env bash
# Builds LaunchdUI.app, signs it, and optionally notarizes it.
#
#   ./scripts/build-app.sh                       # ad-hoc signature
#   SIGN_IDENTITY="Apple Development: You (TEAMID)" ./scripts/build-app.sh
#   SIGN_IDENTITY="Developer ID Application: You (TEAMID)" NOTARIZE=1 \
#     NOTARY_PROFILE=my-profile ./scripts/build-app.sh
#
# The signing identity is the only thing that changes between a local ad-hoc build and a
# distributable one, so it is a single variable rather than a separate code path.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
# PRODUCT is the SwiftPM product and the Mach-O filename inside the bundle; it must
# match CFBundleExecutable. APP_NAME is only the user-visible bundle name, so the two
# differ and cannot be collapsed into one variable.
PRODUCT="LaunchdUI"
APP_NAME="Launchd UI"
BUNDLE="$ROOT/build/$APP_NAME.app"

# "-" is codesign's ad-hoc identity: valid signature, no certificate required.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"

# --- Preflight -------------------------------------------------------------------------
# SwiftUI's @State is a macro whose plugin (libSwiftUIMacros.dylib) ships only inside
# Xcode. Command Line Tools alone cannot compile the app target, so fail early and clearly.
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    cat >&2 <<'MSG'
error: this build needs a full Xcode install.

  SwiftUI's @State is a macro and its plugin (libSwiftUIMacros.dylib) ships only with
  Xcode, not with Command Line Tools. The UI target cannot compile without it.

  Install Xcode, then point the toolchain at it:
    sudo xcode-select -s /Applications/Xcode.app

  The UI-independent core does build and verify without Xcode:
    (cd Core && swift run CoreChecks)
MSG
    exit 1
fi

# --- Build -----------------------------------------------------------------------------
echo "==> Building $PRODUCT (release)"
cd "$ROOT/App"
swift build -c release --product "$PRODUCT"
BINARY="$(swift build -c release --product "$PRODUCT" --show-bin-path)/$PRODUCT"
cd "$ROOT"

[ -f "$BINARY" ] || { echo "error: binary not found at $BINARY" >&2; exit 1; }

# --- Assemble the bundle ---------------------------------------------------------------
echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/$PRODUCT"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"

# --- Sign ------------------------------------------------------------------------------
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Signing ad-hoc (no certificate)"
    echo "    Runs on this Mac only; Gatekeeper will warn elsewhere."
else
    echo "==> Signing as: $SIGN_IDENTITY"
fi

# --options=runtime enables the hardened runtime, which notarization requires and which
# is harmless for ad-hoc builds.
codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --options=runtime \
    --entitlements "$ROOT/Resources/$PRODUCT.entitlements" \
    --timestamp"$([ "$SIGN_IDENTITY" = "-" ] && echo "=none")" \
    "$BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

# spctl only passes for notarized or Developer ID builds; report without failing the build.
if spctl --assess --type execute --verbose=4 "$BUNDLE" 2>&1; then
    echo "    Gatekeeper: accepted"
else
    echo "    Gatekeeper: rejected (expected for ad-hoc and Development signatures)"
fi

# --- Notarize --------------------------------------------------------------------------
if [ "$NOTARIZE" = "1" ]; then
    : "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"
    echo "==> Notarizing"
    ZIP="$ROOT/build/$PRODUCT.zip"
    ditto -c -k --keepParent "$BUNDLE" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUNDLE"
    echo "==> Stapled"
fi

echo
echo "Built: $BUNDLE"
echo "Run:   open '$BUNDLE'"
