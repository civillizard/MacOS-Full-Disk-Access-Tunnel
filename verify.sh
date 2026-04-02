#!/bin/bash
# verify.sh — Check if an FDA tunnel binary can access TCC-protected paths
#
# Usage:
#   ./verify.sh                          # Tests ~/.local/bin/fda-python3
#   ./verify.sh ~/.local/bin/fda-node    # Tests a specific binary
#   ./verify.sh --all                    # Tests all fda-* binaries in ~/.local/bin/

set -euo pipefail

if [ -t 1 ]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

PASS=0
FAIL=0
SKIP=0

# TCC-protected paths that FDA unlocks
declare -a TCC_PATHS=(
    "$HOME/Library/Safari/History.db"
    "$HOME/Library/Safari/Bookmarks.plist"
    "$HOME/Library/Cookies/Cookies.binarycookies"
    "$HOME/Library/Mail"
    "$HOME/Library/Messages/chat.db"
    "$HOME/Library/Calendars"
    "$HOME/Library/Suggestions/snippets.db"
)

declare -a TCC_LABELS=(
    "Safari History"
    "Safari Bookmarks"
    "Cookies"
    "Mail"
    "Messages"
    "Calendars"
    "Siri Suggestions"
)

test_binary() {
    local binary="$1"
    local name
    name=$(basename "$binary")

    echo -e "${BOLD}Testing: $name${RESET}"
    echo "  Path: $binary"
    echo ""

    if [ ! -f "$binary" ]; then
        echo -e "  ${RED}Binary not found${RESET}"
        FAIL=$((FAIL + 1))
        return
    fi

    if [ ! -x "$binary" ]; then
        echo -e "  ${RED}Binary not executable${RESET}"
        FAIL=$((FAIL + 1))
        return
    fi

    # Detect interpreter type for the read test
    local file_type
    file_type=$(file "$binary")

    local interpreter=""
    if echo "$name" | grep -qi "python"; then
        interpreter="python"
    elif echo "$name" | grep -qi "node"; then
        interpreter="node"
    elif echo "$name" | grep -qi "ruby"; then
        interpreter="ruby"
    elif echo "$name" | grep -qi "perl"; then
        interpreter="perl"
    fi

    for i in "${!TCC_PATHS[@]}"; do
        local path="${TCC_PATHS[$i]}"
        local label="${TCC_LABELS[$i]}"

        if [ ! -e "$path" ]; then
            printf "  %-20s ${YELLOW}SKIP${RESET} (path doesn't exist on this system)\n" "$label"
            SKIP=$((SKIP + 1))
            continue
        fi

        # Build a read test command based on interpreter type
        local test_cmd=""
        local result=""

        case "$interpreter" in
            python)
                test_cmd="import os; print('OK' if os.access('$path', os.R_OK) else 'DENIED')"
                result=$("$binary" -c "$test_cmd" 2>/dev/null) || result="ERROR"
                ;;
            node)
                test_cmd="const fs=require('fs');try{fs.accessSync('$path',fs.constants.R_OK);console.log('OK')}catch(e){console.log('DENIED')}"
                result=$("$binary" -e "$test_cmd" 2>/dev/null) || result="ERROR"
                ;;
            ruby)
                test_cmd="puts File.readable?('$path') ? 'OK' : 'DENIED'"
                result=$("$binary" -e "$test_cmd" 2>/dev/null) || result="ERROR"
                ;;
            perl)
                test_cmd="print -r '$path' ? 'OK' : 'DENIED'"
                result=$("$binary" -e "$test_cmd" 2>/dev/null) || result="ERROR"
                ;;
            *)
                # Generic: just try to read with the binary itself, or fall back to test
                if [ -r "$path" ]; then
                    result="OK"
                else
                    result="DENIED"
                fi
                ;;
        esac

        if [ "$result" = "OK" ]; then
            printf "  %-20s ${GREEN}PASS${RESET}\n" "$label"
            PASS=$((PASS + 1))
        elif [ "$result" = "DENIED" ]; then
            printf "  %-20s ${RED}FAIL${RESET} (access denied)\n" "$label"
            FAIL=$((FAIL + 1))
        else
            printf "  %-20s ${RED}FAIL${RESET} (error running test)\n" "$label"
            FAIL=$((FAIL + 1))
        fi
    done

    echo ""
}

# --- Main ---
echo ""
echo -e "${BOLD}FDA Tunnel Verification${RESET}"
echo ""

if [ "${1:-}" = "--all" ]; then
    # Test all fda-* binaries
    found=0
    for bin in "$HOME/.local/bin"/fda-*; do
        [ -f "$bin" ] || continue
        test_binary "$bin"
        found=$((found + 1))
    done
    if [ "$found" -eq 0 ]; then
        echo "No fda-* binaries found in ~/.local/bin/"
        echo "Run setup.sh first."
        exit 1
    fi
elif [ $# -ge 1 ]; then
    test_binary "$1"
else
    # Default: test fda-python3
    DEFAULT="$HOME/.local/bin/fda-python3"
    if [ -f "$DEFAULT" ]; then
        test_binary "$DEFAULT"
    else
        echo "Usage: $0 [binary-path|--all]"
        echo ""
        echo "No default fda-python3 found. Specify a path or run setup.sh first."
        exit 1
    fi
fi

# --- Summary ---
TOTAL=$((PASS + FAIL + SKIP))
echo -e "${BOLD}Results:${RESET} ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}, ${YELLOW}$SKIP skipped${RESET} (of $TOTAL checks)"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failed checks mean FDA is not granted (or not granted to this binary)."
    echo ""
    echo "Fix: System Settings > Privacy & Security > Full Disk Access"
    echo "     Add or re-add the binary, then try again."
    exit 1
fi
