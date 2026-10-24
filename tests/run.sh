#!/usr/bin/env bash
# Headless checks for CopyAvatar.lua.
#
# Requires (all open source):
#   - Luau CLI        https://github.com/luau-lang/luau
#   - Selene          https://github.com/Kampfkarren/selene
#
# Usage:
#   LUAU=luau LUAU_COMPILE=luau-compile SELENE=selene ./tests/run.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LUAU="${LUAU:-luau}"
LUAU_COMPILE="${LUAU_COMPILE:-luau-compile}"
SELENE="${SELENE:-selene}"

mkdir -p build

echo "== selene (Roblox std) =="
"$SELENE" --display-style quiet src/CopyAvatar.lua

echo "== luau-compile =="
"$LUAU_COMPILE" src/CopyAvatar.lua > /dev/null
echo "  ok   src/CopyAvatar.lua compiles"

for mode in mobile desktop; do
    if [ "$mode" = "mobile" ]; then
        flag=true
    else
        flag=false
    fi

    target="build/test_$mode.luau"
    {
        printf 'TEST_MOBILE = %s\n' "$flag"
        cat tests/mock_roblox.luau
        cat src/CopyAvatar.lua
        cat tests/spec.luau
    } > "$target"

    echo "== headless run ($mode) =="
    "$LUAU" "$target"
done
