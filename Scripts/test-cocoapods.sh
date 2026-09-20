#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY_ROOT="${BINARY_ROOT:-$ROOT_DIR/../RichTextViewBinaries}"
MARKDOWN_PODSPEC="$BINARY_ROOT/Components/Markdown/SwiftMarkdownBinary.podspec"
TREE_SITTER_PODSPEC="$BINARY_ROOT/Components/TreeSitter/RichTextViewTreeSitterBinary.podspec"
MATH_PODSPEC="$BINARY_ROOT/Components/Math/RichTextViewMathBinary.podspec"
CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$CACHE_DIR"' EXIT

prepare_binary() {
  local framework="$1"
  local destination="$2"
  local url="$3"
  local archive="$CACHE_DIR/$(basename "$url")"
  [[ -d "$destination/$framework" ]] && return
  curl --fail --location --output "$archive" "$url"
  ditto -x -k "$archive" "$destination"
}

if [[ ! -f "$MARKDOWN_PODSPEC" ]]; then
  echo "Missing SwiftMarkdownBinary podspec: $MARKDOWN_PODSPEC" >&2
  exit 1
fi
if [[ ! -f "$TREE_SITTER_PODSPEC" ]]; then
  echo "Missing RichTextViewTreeSitterBinary podspec: $TREE_SITTER_PODSPEC" >&2
  exit 1
fi
if [[ ! -f "$MATH_PODSPEC" ]]; then
  echo "Missing RichTextViewMathBinary podspec: $MATH_PODSPEC" >&2
  exit 1
fi

prepare_binary \
  'Markdown.xcframework' \
  "$BINARY_ROOT/Components/Markdown" \
  'https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/swift-markdown-0.8.0-patch.1/Markdown.xcframework.zip'
prepare_binary \
  'Artifacts/TreeSitter.xcframework' \
  "$BINARY_ROOT/Components/TreeSitter" \
  'https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/tree-sitter-0.25.10.2/RichTextViewTreeSitter.xcframeworks.zip'
prepare_binary \
  'iosMath.xcframework' \
  "$BINARY_ROOT/Components/Math" \
  'https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/iosMath-2.5.0.2/iosMath.xcframework.zip'

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Core \
  --include-podspecs="$BINARY_ROOT/Components/{TreeSitter/RichTextViewTreeSitterBinary.podspec,Math/RichTextViewMathBinary.podspec}" \
  --allow-warnings \
  --platforms=ios \
  --verbose

ruby -e 'require "cocoapods"; Pod::Command.plugin_prefixes = []; Pod::Command.run(ARGV)' -- \
  lib lint "$ROOT_DIR/RichTextView.podspec" \
  --subspec=Markdown \
  --include-podspecs="$BINARY_ROOT/Components/{Markdown/SwiftMarkdownBinary.podspec,TreeSitter/RichTextViewTreeSitterBinary.podspec,Math/RichTextViewMathBinary.podspec}" \
  --allow-warnings \
  --platforms=ios \
  --verbose
