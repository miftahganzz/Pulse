#!/bin/bash
set -e

APP_NAME="Pulse"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

echo "Building Universal 2 binary..."
swift build -c release --arch arm64 --arch x86_64

echo "Creating ${APP_NAME}.app bundle..."
rm -rf build
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

cp .build/apple/Products/Release/Pulse "${MACOS_DIR}/${APP_NAME}"
install_name_tool -add_rpath @executable_path/../Frameworks "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/"
fi

# Embed Sparkle.framework if available in build artifacts
SPARKLE_FW=$(find .build -name "Sparkle.framework" -type d | head -n 1)
if [ -n "${SPARKLE_FW}" ] && [ -d "${SPARKLE_FW}" ]; then
    echo "Embedding Sparkle framework from ${SPARKLE_FW}..."
    cp -R "${SPARKLE_FW}" "${FRAMEWORKS_DIR}/"
fi

cat << 'PLIST' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Pulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.pulse.Pulse</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Pulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.6</string>
    <key>CFBundleVersion</key>
    <string>107</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Pulse Contributors. Released under MIT License.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.pulse.Pulse.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pulse</string>
            </array>
        </dict>
    </array>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/miftahganzz/Pulse/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>kxhjPNnUe3JUBmZ3JRH2a88QDG17T6ITWWRu1m/QYaE=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

echo "App bundle created successfully at macos/${BUNDLE_DIR}"

# Sign with Apple Development certificate if available, otherwise ad-hoc
SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "Signing bundle with '${SIGN_IDENTITY}'..."
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${BUNDLE_DIR}"
else
    echo "Signing bundle (ad-hoc)..."
    codesign --force --deep -s - "${BUNDLE_DIR}"
fi
echo "✅ Pulse.app bundle created in ${BUNDLE_DIR}"
printf "   Size: "
du -sh "${BUNDLE_DIR}" | cut -f1
