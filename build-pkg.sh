#!/bin/bash
set -euo pipefail

# PKG Installer Build Script for SVP System Support
# Builds the Xcode project and creates a .pkg installer

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="SVPSystemSupport"
SCHEME="SVPSystemSupport"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"
PKG_DIR="${BUILD_DIR}/pkg"
APP_BUNDLE="SVPSystemSupport.app"
PKG_OUTPUT="${BUILD_DIR}/SVPSystemSupport.pkg"
IDENTIFIER="com.cueit.svp-system-support"
VERSION="1.0"

echo "=== SVP System Support PKG Build ==="
echo "Project: ${PROJECT_DIR}"
echo "Configuration: ${CONFIGURATION}"
echo ""

# Clean previous build artifacts
echo "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build the Xcode project
echo ""
echo "Building Xcode project..."
xcodebuild \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -destination 'generic/platform=macOS' \
    build \
    CODE_SIGN_STYLE=Automatic

# Find the built app
BUILT_APP=$(find "${BUILD_DIR}/DerivedData" -name "${APP_BUNDLE}" -type d | head -1)

if [ -z "${BUILT_APP}" ] || [ ! -d "${BUILT_APP}" ]; then
    echo "ERROR: Could not find built ${APP_BUNDLE}"
    exit 1
fi

echo ""
echo "Found built app: ${BUILT_APP}"

# Prepare staging area
echo "Preparing staging area..."
mkdir -p "${PKG_DIR}/Applications"
cp -R "${BUILT_APP}" "${PKG_DIR}/Applications/"

# Build the pkg
echo ""
echo "Building PKG installer..."
pkgbuild \
    --root "${PKG_DIR}" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --install-location "/" \
    --scripts "${PROJECT_DIR}/scripts" \
    "${PKG_OUTPUT}"

if [ $? -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESSFUL ==="
    echo "PKG installer: ${PKG_OUTPUT}"
    echo ""
    echo "To install: sudo installer -pkg '${PKG_OUTPUT}' -target /"
else
    echo "=== BUILD FAILED ==="
    exit 1
fi
