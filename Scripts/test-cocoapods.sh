#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKDOWN_PODSPEC="${MARKDOWN_PODSPEC:-$ROOT_DIR/../swift-markdown-xcframework/SwiftMarkdownBinary.podspec}"
TREE_SITTER_PODSPEC="${TREE_SITTER_PODSPEC:-$ROOT_DIR/../RichTextViewTreeSitter/RichTextViewTreeSitterBinary.podspec}"

if [[ ! -f "$MARKDOWN_PODSPEC" ]]; then
  echo "Missing SwiftMarkdownBinary podspec: $MARKDOWN_PODSPEC" >&2
  exit 1
fi
if [[ ! -f "$TREE_SITTER_PODSPEC" ]]; then
  echo "Missing RichTextViewTreeSitterBinary podspec: $TREE_SITTER_PODSPEC" >&2
  exit 1
fi

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Core \
  --include-podspecs="$TREE_SITTER_PODSPEC" \
  --allow-warnings \
  --platforms=ios \
  --verbose

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Markdown \
  --include-podspecs="$(dirname "$ROOT_DIR")/{swift-markdown-xcframework/SwiftMarkdownBinary.podspec,RichTextViewTreeSitter/RichTextViewTreeSitterBinary.podspec}" \
  --allow-warnings \
  --platforms=ios \
  --verbose
