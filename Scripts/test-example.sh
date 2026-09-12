#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/Example"

cd "$EXAMPLE_DIR"
xcodegen generate --spec project.yml

set -o pipefail
xcodebuild build \
  -project RichTextViewExample.xcodeproj \
  -scheme RichTextViewExample \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify

set -o pipefail
xcodebuild build \
  -project RichTextViewExample.xcodeproj \
  -scheme RichTextViewExample \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify
