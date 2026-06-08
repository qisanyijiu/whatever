#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

THRESHOLD="${1:-95}"
PROFILE_DIR="$ROOT_DIR/.build/coverage"
PROFILE_DATA="$PROFILE_DIR/coverage.profdata"
REPORT_FILE="$PROFILE_DIR/coverage-report.txt"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

mkdir -p "$PROFILE_DIR"
rm -f "$PROFILE_DIR"/*.profraw "$PROFILE_DATA" "$REPORT_FILE"

swift build --enable-code-coverage --product EnglishClozeCoachUnitTests
BUILD_DIR="$(swift build --show-bin-path)"
TEST_BINARY="$BUILD_DIR/EnglishClozeCoachUnitTests"

LLVM_PROFILE_FILE="$PROFILE_DIR/EnglishClozeCoachUnitTests-%p.profraw" "$TEST_BINARY"
xcrun llvm-profdata merge -sparse "$PROFILE_DIR"/*.profraw -o "$PROFILE_DATA"

xcrun llvm-cov report "$TEST_BINARY" \
  -instr-profile="$PROFILE_DATA" \
  -ignore-filename-regex='/.build/|/Tests/|/Views/|/Support/|/Services/(KeychainService|ScriptTextDownloader|ShadowingRecorderService|SpeechService|StudyReminderService|TEDTranscriptDownloader)\.swift' \
  | tee "$REPORT_FILE"

LINE_COVERAGE="$(
  awk '/^TOTAL/ { value=$10; gsub("%", "", value); print value }' "$REPORT_FILE"
)"

awk -v coverage="$LINE_COVERAGE" -v threshold="$THRESHOLD" '
  BEGIN {
    if (coverage + 0 < threshold + 0) {
      printf("Line coverage %.2f%% is below %.2f%%\n", coverage, threshold)
      exit 1
    }
    printf("Line coverage %.2f%% meets %.2f%% threshold\n", coverage, threshold)
  }
'
