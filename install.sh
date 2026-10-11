#!/bin/bash
# Freeflow — one-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/rohith1-p/freeflow/main/install.sh | sh
set -e

echo "⚡ Installing Freeflow..."

# 1. Create venv
FREEFLOW_HOME="$HOME/.config/freeflow"
VENV="$FREEFLOW_HOME/venv"
mkdir -p "$FREEFLOW_HOME"

if [ ! -d "$VENV" ]; then
    echo "  Creating Python environment..."
    python3 -m venv "$VENV"
fi

# 2. Install dependencies
echo "  Installing dependencies (may take 1-2 min)..."
"$VENV/bin/pip" install -q moondream pynput sounddevice \
    pyobjc-framework-Cocoa pyobjc-framework-Quartz rumps

# 3. Clone and build app
echo "  Building Freeflow.app..."
TMP=$(mktemp -d)
git clone -q https://github.com/rohith1-p/freeflow.git "$TMP/freeflow" 2>/dev/null || true
if [ -d "$TMP/freeflow" ]; then
    bash "$TMP/freeflow/scripts/build_app.sh"
else
    echo "  ERROR: Could not clone repo. Install manually from github.com/rohith1-p/freeflow"
    exit 1
fi

# 4. Download model (background — user can also do it in the app)
echo "  Downloading speech model (178MB, one time)..."
"$VENV/bin/python" -c "
import moondream as md
md.photon('moondream/parakeet-redux', device='cpu')
print('  ✓ Model ready')
" &

echo ""
echo "✓ Freeflow installed!"
echo ""
echo "  Next steps:"
echo "  1. Open Freeflow.app from /Applications"
echo "  2. Complete the setup wizard (grants permissions, ~60 seconds)"
echo "  3. Hold Control, speak, release — your words appear at your cursor"
echo ""
echo "  Note: If macOS says 'unidentified developer', right-click → Open"
echo ""

# Clear quarantine so Gatekeeper doesn't block
xattr -cr /Applications/Freeflow.app 2>/dev/null || true

wait
echo "Done!"
