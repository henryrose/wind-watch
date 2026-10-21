#!/bin/sh
# Build helpers for the Apple targets. Run from anywhere; paths resolve to this directory.
#   ./build.sh gen     regenerate WindWatch.xcodeproj from project.yml
#   ./build.sh ios     build the iPhone app for the iPhone 18 Pro simulator
#   ./build.sh watch   build the watch app (+ complications) for the Apple Watch Series 12 (46mm) simulator
#   ./build.sh test    run the WindCore package tests on macOS
#   ./build.sh all     gen + test + ios + watch
# Simulator builds skip code signing, so no team id is needed on this machine.
set -eu
cd "$(dirname "$0")"

PROJECT=WindWatch.xcodeproj
DERIVED=build/DerivedData
IOS_DEST="${WW_IOS_DEST:-platform=iOS Simulator,name=iPhone 18 Pro}"
WATCH_DEST="${WW_WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)}"

run() {
  echo "+ $*"
  "$@"
}

xcb() {
  scheme=$1; dest=$2
  run xcodebuild -project "$PROJECT" -scheme "$scheme" -configuration Debug \
    -destination "$dest" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
}

case "${1:-}" in
  gen)   run xcodegen generate --spec project.yml ;;
  ios)   xcb WindWatch "$IOS_DEST" ;;
  watch) xcb WindWatchWatch "$WATCH_DEST" ;;
  test)  (cd WindCore && run swift test) ;;
  all)   "$0" gen && "$0" test && "$0" ios && "$0" watch ;;
  *)     sed -n '2,8p' "$0"; exit 2 ;;
esac
