#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
set -o pipefail
xcodebuild build \
  -scheme RichTextView \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify

set -o pipefail
xcodebuild build \
  -scheme RichTextView \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify

SIMULATOR_ID="${SIMULATOR_ID:-$(
  xcrun simctl list devices available -j | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices")
    iphone = devices.select { |runtime, _| runtime.include?("iOS") }
                    .values.flatten.find { |device| device.fetch("name").start_with?("iPhone") }
    abort("No available iPhone simulator") unless iphone
    puts iphone.fetch("udid")
  '
)}"

set -o pipefail
xcodebuild test \
  -scheme RichTextView \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify
