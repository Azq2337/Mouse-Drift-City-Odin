#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
odin run src/main -debug
