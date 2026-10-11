#!/bin/bash
# Build Freeflow.app from source
set -e

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="/Applications/Freeflow.app"
CONTENTS="$APP_DIR/Contents"

echo "Building Freeflow.app..."

# Create bundle structure
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy Info.plist
cp "$SRC_DIR/app/Info.plist" "$CONTENTS/Info.plist"

# Copy launcher
cp "$SRC_DIR/app/Freeflow" "$CONTENTS/MacOS/Freeflow"
chmod +x "$CONTENTS/MacOS/Freeflow"

# Copy source code into Resources
mkdir -p "$CONTENTS/Resources/freeflow"
cp -r "$SRC_DIR/src/freeflow/"*.py "$CONTENTS/Resources/freeflow/"

# Copy icon
if [ -f "$SRC_DIR/app/AppIcon.icns" ]; then
    cp "$SRC_DIR/app/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# Create a python path setup so freeflow is importable
cat > "$CONTENTS/Resources/freeflow_path.py" << 'PYEOF'
import sys
import os
resources = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, resources)
PYEOF

# Ad-hoc codesign (prevents "damaged" flag)
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "✓ Freeflow.app built at /Applications/Freeflow.app"
echo "  Note: first open will show 'unidentified developer' — right-click → Open"
