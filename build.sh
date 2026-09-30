#!/bin/zsh
# Builds Dictation.app, signs it and installs it to /Applications.
#
# Signing: set SIGN_IDENTITY to pick a certificate. Otherwise it uses your first
# "Apple Development" identity if you have one (macOS then keeps the mic and
# Accessibility grants across rebuilds), or signs ad hoc ("-") if you don't.
#
#   ./build.sh               build, sign, install to /Applications
#   ./build.sh --no-install  build and sign only (output: build/Dictation.app)
set -e
cd "$(dirname "$0")"
APP=build/Dictation.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework Speech \
  -framework ServiceManagement -framework MetalKit -framework Metal -framework CoreAudio -framework ApplicationServices \
  Sources/*.swift -o $APP/Contents/MacOS/Dictation
cp Info.plist $APP/Contents/Info.plist
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns $APP/Contents/Resources/

if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
  [ -z "$SIGN_IDENTITY" ] && SIGN_IDENTITY="-"
fi
echo "signing with: $SIGN_IDENTITY"
codesign --force --options runtime --entitlements Dictation.entitlements --sign "$SIGN_IDENTITY" $APP

if [ "$1" = "--no-install" ]; then
  echo "built $APP (not installed)"
  exit 0
fi
pkill -x Dictation 2>/dev/null || true
# /Applications so it shows in Launchpad and the Applications folder, not just Spotlight.
rm -rf /Applications/Dictation.app && cp -R $APP /Applications/
echo "built + installed /Applications/Dictation.app"
