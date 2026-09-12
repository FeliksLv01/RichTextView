#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKDOWN_PODSPEC="${MARKDOWN_PODSPEC:-$ROOT_DIR/../swift-markdown-xcframework/SwiftMarkdownBinary.podspec}"

if [[ ! -f "$MARKDOWN_PODSPEC" ]]; then
  echo "Missing SwiftMarkdownBinary podspec: $MARKDOWN_PODSPEC" >&2
  exit 1
fi

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Core \
  --allow-warnings \
  --platforms=ios \
  --verbose

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Markdown \
  --include-podspecs="$MARKDOWN_PODSPEC" \
  --allow-warnings \
  --platforms=ios \
  --verbose
