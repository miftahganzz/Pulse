#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Packaging Pulse DMGs ==="
mkdir -p app-build

BASE_APP="app-build/Pulse.app"
rm -rf "${BASE_APP}"
cp -R build/Pulse.app "${BASE_APP}"

build_arch_dmg() {
    local ARCH="$1"
    local BIN_SRC="$2"
    local BG_TIFF="$3"
    local OUT_DMG="$4"

    echo "--- Building ${OUT_DMG} (${ARCH}) ---"
    local STAGING_DIR="app-build/staging_${ARCH}"
    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}"
    
    cp -R "${BASE_APP}" "${STAGING_DIR}/Pulse.app"
    cp "${BIN_SRC}" "${STAGING_DIR}/Pulse.app/Contents/MacOS/Pulse"
    install_name_tool -add_rpath @executable_path/../Frameworks "${STAGING_DIR}/Pulse.app/Contents/MacOS/Pulse" 2>/dev/null || true
    codesign --force --deep -s - "${STAGING_DIR}/Pulse.app"

    rm -f "app-build/${OUT_DMG}"
    create-dmg \
      --volname "Pulse" \
      --volicon "Resources/AppIcon.icns" \
      --background "dmg-assets/dmg_minimal.tiff" \
      --window-pos 200 120 \
      --window-size 600 360 \
      --icon-size 120 \
      --text-size 12 \
      --icon "Pulse.app" 160 170 \
      --hide-extension "Pulse.app" \
      --app-drop-link 440 170 \
      --no-internet-enable \
      "app-build/${OUT_DMG}" \
      "${STAGING_DIR}"

    rm -rf "${STAGING_DIR}"
    echo "✓ Finished app-build/${OUT_DMG}"
}

# 1. Universal 2
build_arch_dmg "universal" ".build/apple/Products/Release/Pulse" "dmg_minimal.tiff" "Pulse-1.0.2-Universal.dmg"

# 2. Apple Silicon ARM64
build_arch_dmg "arm64" ".build/apple/Intermediates.noindex/Pulse.build/Release/Pulse.build/Objects-normal/arm64/Binary/Pulse" "dmg_minimal.tiff" "Pulse-1.0.2-arm64.dmg"

# 3. Intel x86_64
build_arch_dmg "x86_64" ".build/apple/Intermediates.noindex/Pulse.build/Release/Pulse.build/Objects-normal/x86_64/Binary/Pulse" "dmg_minimal.tiff" "Pulse-1.0.2-x86_64.dmg"

# 4. Standard default link
cp "app-build/Pulse-1.0.2-Universal.dmg" "app-build/Pulse-1.0.2.dmg"
rm -f "app-build/test-*.dmg"

echo "=== All DMGs created successfully! ==="
ls -lh app-build/*.dmg
