#!/bin/bash
# setup.sh — Create an FDA tunnel for any interpreter binary
#
# Usage:
#   ./setup.sh python3          # Finds python3 via `which`, resolves to real binary
#   ./setup.sh node             # Same for Node.js
#   ./setup.sh ruby             # Same for Ruby
#   ./setup.sh /full/path/bin   # Use an explicit path
#
# What it does:
#   1. Finds the real binary (resolves Homebrew symlinks)
#   2. Copies it to ~/.local/bin/fda-<name>
#   3. Pins the Homebrew package (if applicable) to prevent upgrades breaking the path
#   4. Prints instructions for the one manual step: granting FDA in System Settings
#
# What it does NOT do:
#   - Grant FDA automatically (requires GUI interaction — macOS enforces this)

set -euo pipefail

# --- Colors (skip if not a terminal) ---
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

info()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
error() { echo -e "${RED}[x]${RESET} $*" >&2; }
step()  { echo -e "${CYAN}[>]${RESET} $*"; }

# --- Parse arguments ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <interpreter>"
    echo ""
    echo "Examples:"
    echo "  $0 python3"
    echo "  $0 node"
    echo "  $0 ruby"
    echo "  $0 /opt/homebrew/bin/python3.12"
    exit 1
fi

INPUT="$1"
INSTALL_DIR="$HOME/.local/bin"

# --- Resolve the real binary path ---
resolve_binary() {
    local input="$1"
    local bin_path

    # If it's an absolute path, use it directly
    if [[ "$input" == /* ]]; then
        bin_path="$input"
    else
        bin_path=$(which "$input" 2>/dev/null) || {
            error "'$input' not found in PATH"
            exit 1
        }
    fi

    # Resolve symlinks to the real binary
    # macOS doesn't have readlink -f, so we follow the chain manually
    local resolved="$bin_path"
    while [ -L "$resolved" ]; do
        local target
        target=$(readlink "$resolved")
        # Handle relative symlink targets
        if [[ "$target" != /* ]]; then
            target="$(dirname "$resolved")/$target"
        fi
        resolved="$target"
    done

    # Normalize the path
    resolved=$(cd "$(dirname "$resolved")" && echo "$(pwd -P)/$(basename "$resolved")")
    echo "$resolved"
}

REAL_BINARY=$(resolve_binary "$INPUT")

if [ ! -f "$REAL_BINARY" ]; then
    error "Resolved path does not exist: $REAL_BINARY"
    exit 1
fi

if [ ! -x "$REAL_BINARY" ]; then
    error "Resolved path is not executable: $REAL_BINARY"
    exit 1
fi

# Verify it's a Mach-O binary, not a script or shim
FILE_TYPE=$(file "$REAL_BINARY")
if ! echo "$FILE_TYPE" | grep -q "Mach-O"; then
    error "Not a native binary (FDA only works on Mach-O executables):"
    error "  $REAL_BINARY"
    error "  Type: $FILE_TYPE"
    error ""
    error "If this is a shim or wrapper script, find the real binary it calls."
    exit 1
fi

# --- Determine the FDA binary name ---
# Extract a clean name: python3 → fda-python3, node → fda-node
if [[ "$INPUT" == /* ]]; then
    BIN_NAME=$(basename "$INPUT")
else
    BIN_NAME="$INPUT"
fi
FDA_NAME="fda-${BIN_NAME}"
FDA_PATH="${INSTALL_DIR}/${FDA_NAME}"

echo ""
info "Interpreter:   $INPUT"
info "Real binary:   $REAL_BINARY"
info "FDA copy:      $FDA_PATH"
echo ""

# --- Check if already set up ---
if [ -f "$FDA_PATH" ]; then
    EXISTING_TYPE=$(file "$FDA_PATH")
    warn "FDA binary already exists at $FDA_PATH"
    warn "  Type: $EXISTING_TYPE"
    echo ""

    # Compare checksums
    EXISTING_SUM=$(shasum -a 256 "$FDA_PATH" | awk '{print $1}')
    SOURCE_SUM=$(shasum -a 256 "$REAL_BINARY" | awk '{print $1}')

    if [ "$EXISTING_SUM" = "$SOURCE_SUM" ]; then
        info "Checksums match — already up to date"
        echo ""
    else
        warn "Checksums differ — source binary may have been updated"
        warn "  Existing: $EXISTING_SUM"
        warn "  Source:   $SOURCE_SUM"
        echo ""
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Keeping existing binary"
            echo ""
        else
            cp "$REAL_BINARY" "$FDA_PATH"
            chmod 755 "$FDA_PATH"
            info "Updated $FDA_PATH"
            echo ""
            warn "IMPORTANT: If you previously granted FDA to the old binary at this path,"
            warn "macOS should recognize the new one automatically (same path)."
            warn "But if it stops working, remove and re-add it in System Settings."
            echo ""
        fi
    fi
else
    # --- Create the FDA binary ---
    mkdir -p "$INSTALL_DIR"
    step "Copying binary..."
    cp "$REAL_BINARY" "$FDA_PATH"
    chmod 755 "$FDA_PATH"
    info "Created $FDA_PATH"
    echo ""
fi

# --- Pin Homebrew package if applicable ---
if echo "$REAL_BINARY" | grep -q "Cellar"; then
    # Extract the formula name from the Cellar path
    # /opt/homebrew/Cellar/python@3.12/3.12.12_2/... → python@3.12
    FORMULA=$(echo "$REAL_BINARY" | sed -n 's|.*/Cellar/\([^/]*\)/.*|\1|p')
    if [ -n "$FORMULA" ] && command -v brew &>/dev/null; then
        step "Pinning Homebrew formula: $FORMULA"
        brew pin "$FORMULA" 2>/dev/null && info "Pinned $FORMULA (prevents upgrades from breaking the Cellar path)" || warn "Could not pin $FORMULA (may already be pinned)"
        echo ""
    fi
fi

# --- Manual step: Grant FDA ---
echo -e "${BOLD}=== One manual step remaining ===${RESET}"
echo ""
echo "macOS requires you to grant Full Disk Access through the GUI."
echo "A script cannot do this for you — Apple enforces it."
echo ""
echo "Steps:"
echo "  1. Open System Settings > Privacy & Security > Full Disk Access"
echo "  2. Click the + button (or drag-and-drop from Finder)"
echo "  3. Navigate to: $FDA_PATH"
echo ""
echo "Tip: The file picker may grey out non-.app files."
echo "     Workaround: open a Finder window to $(dirname "$FDA_PATH"),"
echo "     then DRAG the file onto the Full Disk Access list."
echo ""
echo "  To open Finder to the right folder:"
echo "    open $(dirname "$FDA_PATH")"
echo ""

read -p "Open System Settings to Full Disk Access now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    open "$(dirname "$FDA_PATH")"
    info "Opened System Settings and Finder. Drag ${FDA_NAME} onto the FDA list."
fi

echo ""
echo -e "${BOLD}=== After granting FDA ===${RESET}"
echo ""
echo "Verify it works:"
echo "  ./verify.sh $FDA_PATH"
echo ""
# Map interpreter to file extension for the usage hint
case "$BIN_NAME" in
    python*) EXT="py" ;;
    node*)   EXT="js" ;;
    ruby*)   EXT="rb" ;;
    perl*)   EXT="pl" ;;
    php*)    EXT="php" ;;
    *)       EXT="sh" ;;
esac

echo "Use it in your scripts:"
echo "  $FDA_PATH your_script.$EXT"
echo ""
echo "Use it in launchd plists:"
echo "  <key>ProgramArguments</key>"
echo "  <array>"
echo "    <string>$FDA_PATH</string>"
echo "    <string>/path/to/your_script.$EXT</string>"
echo "  </array>"
echo ""
