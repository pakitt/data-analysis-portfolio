#!/bin/bash
# Bumps the build number, builds Release, and produces dist/FireflyDash.zip.
# Run this (not raw xcodebuild) whenever a new distributable is needed, so
# every build gets a distinct, visible Version/Build shown in Settings → About.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

PROJECT="FireflyDash.xcodeproj/project.pbxproj"

# Increment every CURRENT_PROJECT_VERSION occurrence (Debug + Release configs)
# in place, regardless of their current value, so the two configs can't drift.
perl -pi -e 's/(CURRENT_PROJECT_VERSION = )(\d+);/$1 . ($2+1) . ";"/ge' "$PROJECT"

BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT" | grep -oE '[0-9]+')
MARKETING=$(grep -m1 "MARKETING_VERSION" "$PROJECT" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
echo "Building version $MARKETING (build $BUILD)…"

xcodebuild -scheme FireflyDash -configuration Release -quiet build

BUILT_PRODUCTS_DIR=$(xcodebuild -scheme FireflyDash -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP_PATH="$BUILT_PRODUCTS_DIR/FireflyDash.app"

if [ ! -d "$APP_PATH" ]; then
    echo "error: build product not found at $APP_PATH" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP_PATH"

mkdir -p dist
rm -f dist/FireflyDash.zip
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" dist/FireflyDash.zip

echo "✓ dist/FireflyDash.zip — version $MARKETING (build $BUILD)"
