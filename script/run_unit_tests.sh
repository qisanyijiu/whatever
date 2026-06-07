#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

swift run EnglishClozeCoachUnitTests
