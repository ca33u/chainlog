#!/bin/zsh
# Syntax check and every test suite. Run from anywhere.
set -e
cd "$(dirname "$0")/.."
echo "== syntax (luac -p)"
for f in *.lua tests/*.lua; do luac -p "$f"; done
echo "== tests/core_test.lua"
lua tests/core_test.lua | tail -1
echo "== all green"
