#!/bin/bash
set -euo pipefail

# Ariami CLI - Linux Release Builder for Mac
# Builds ARM64 Raspberry Pi or AMD64/x64 Linux releases using Docker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH="arm64"
if [ "$#" -gt 0 ]; then
  case "$1" in
    --arch)
      if [ "$#" -ne 2 ]; then
        echo "ERROR: --arch requires one value: arm64 or amd64"
        exit 1
      fi
      ARCH="$2"
      ;;
    --arch=*)
      if [ "$#" -ne 1 ]; then
        echo "ERROR: Unexpected arguments; use arm64, amd64, --arch arm64, or --arch amd64"
        exit 1
      fi
      ARCH="${1#--arch=}"
      ;;
    *)
      if [ "$#" -ne 1 ]; then
        echo "ERROR: Unexpected arguments; use arm64, amd64, --arch arm64, or --arch amd64"
        exit 1
      fi
      ARCH="$1"
      ;;
  esac
fi

case "${ARCH}" in
  arm64)
    RELEASE_ARCH_NAME="raspberry-pi-arm64"
    TARGET_LABEL="ARM64 (aarch64) Linux"
    DOCKER_PLATFORM="linux/arm64"
    CLI_BUNDLE_RELATIVE_DIR="build/pi-cli-bundle"
    SONIC_TARGET_DIR="/workspace/ariami_cli/build/sonic_target"
    BUILD_OUTPUT_DIR="/tmp/ariami-pi-cli"
    EXPECTED_FILE_ARCH="aarch64"
    ;;
  amd64)
    RELEASE_ARCH_NAME="linux-x64"
    TARGET_LABEL="AMD64/x64 (x86-64) Linux"
    DOCKER_PLATFORM="linux/amd64"
    CLI_BUNDLE_RELATIVE_DIR="build/x64-cli-bundle"
    SONIC_TARGET_DIR="/workspace/ariami_cli/build/x64-sonic_target"
    BUILD_OUTPUT_DIR="/tmp/ariami-x64-cli"
    EXPECTED_FILE_ARCH="x86-64"
    ;;
  *)
    echo "ERROR: Unknown arch '${ARCH}'; expected arm64 or amd64"
    exit 1
    ;;
esac

read_pubspec_version() {
  grep '^version:' "$1" | awk '{print $2}' | cut -d'+' -f1
}

read_app_version_constant() {
  sed -n "s/^const String kAriamiVersion = '\(.*\)';$/\1/p" \
    "${PARENT_DIR}/ariami_core/lib/app_version.dart"
}

CLI_VERSION="$(read_pubspec_version "${SCRIPT_DIR}/pubspec.yaml")"
CORE_VERSION="$(read_pubspec_version "${PARENT_DIR}/ariami_core/pubspec.yaml")"
CONST_VERSION="$(read_app_version_constant)"

if [ -z "${CLI_VERSION}" ] || [ -z "${CORE_VERSION}" ] || [ -z "${CONST_VERSION}" ]; then
  echo "ERROR: Could not read Ariami version from pubspec.yaml or app_version.dart"
  exit 1
fi

if [ "${CLI_VERSION}" != "${CORE_VERSION}" ] || [ "${CLI_VERSION}" != "${CONST_VERSION}" ]; then
  echo "ERROR: Ariami version mismatch — fix these before building:"
  echo "  ariami_cli/pubspec.yaml:      ${CLI_VERSION}"
  echo "  ariami_core/pubspec.yaml:     ${CORE_VERSION}"
  echo "  ariami_core/app_version.dart: ${CONST_VERSION}"
  exit 1
fi

VERSION="${CLI_VERSION}"
RELEASE_NAME="ariami-cli-${RELEASE_ARCH_NAME}-v${VERSION}"
SONIC_DIR="${PARENT_DIR}/sonic"
SONIC_LIB_RELATIVE_PATH="${SONIC_TARGET_DIR#/workspace/ariami_cli/}/release/libsonic_transcoder.so"
SONIC_LIB_LOCAL_PATH="${SCRIPT_DIR}/${SONIC_LIB_RELATIVE_PATH}"
CLI_BINARY_RELATIVE_PATH="${CLI_BUNDLE_RELATIVE_DIR}/bin/ariami_cli"
SQLITE_LIB_RELATIVE_PATH="${CLI_BUNDLE_RELATIVE_DIR}/lib/libsqlite3.so"
LAUNCHER_PATH="${SCRIPT_DIR}/ariami_cli-launcher.sh"

echo "=== Ariami CLI - Linux Release Builder (Mac) ==="
echo "Version: ${VERSION}"
echo "Target: ${TARGET_LABEL}"
echo "Platform: macOS with Docker"
echo "Release: ${RELEASE_NAME}.zip"
if [ "${ARCH}" = "amd64" ]; then
    echo "Note: linux/amd64 builds on Apple Silicon use Rosetta emulation and are slower than the native arm64 build."
fi
echo ""

# Check Docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    echo "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    echo "ERROR: Docker is not running"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

echo "✓ Docker is ready"
echo ""

# Ensure Sonic source is present (required for low/medium quality transcoding).
if [ ! -f "${SONIC_DIR}/Cargo.toml" ]; then
    echo "ERROR: Sonic source not found at ${SONIC_DIR}"
    echo "This release builder now requires the sonic/ workspace to package libsonic_transcoder.so"
    exit 1
fi

if [ ! -f "${LAUNCHER_PATH}" ]; then
    echo "ERROR: CLI launcher not found at ${LAUNCHER_PATH}"
    exit 1
fi

# Step 1: Clean previous builds
echo "[1/7] Cleaning previous builds..."
rm -rf build/
rm -rf "${RELEASE_NAME}"
rm -f "${RELEASE_NAME}.zip"
rm -f ariami_cli

# Step 2: Get dependencies on Mac
echo "[2/7] Getting dependencies on Mac..."
flutter pub get

# Step 3: Build web UI (natively on Mac)
echo "[3/7] Building web UI on Mac..."
flutter build web -t lib/web/main.dart

# Step 4: Compile Linux binary using Docker
echo "[4/7] Compiling ${TARGET_LABEL} binary in Docker (this may take a minute)..."

docker run --rm \
  -v "${PARENT_DIR}:/workspace" \
  -w /workspace/ariami_cli \
  --platform "${DOCKER_PLATFORM}" \
  ghcr.io/cirruslabs/flutter:stable \
  sh -c "flutter pub get && dart build cli -o ${BUILD_OUTPUT_DIR} && rm -rf ./${CLI_BUNDLE_RELATIVE_DIR} && cp -R ${BUILD_OUTPUT_DIR}/bundle ./${CLI_BUNDLE_RELATIVE_DIR} && chmod +x ./${CLI_BINARY_RELATIVE_PATH}"

if [ ! -f "${SCRIPT_DIR}/${CLI_BINARY_RELATIVE_PATH}" ]; then
    echo "ERROR: CLI binary was not produced at ${SCRIPT_DIR}/${CLI_BINARY_RELATIVE_PATH}"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/${SQLITE_LIB_RELATIVE_PATH}" ]; then
    echo "ERROR: SQLite native library was not produced at ${SCRIPT_DIR}/${SQLITE_LIB_RELATIVE_PATH}"
    exit 1
fi

echo "✓ ${TARGET_LABEL} binary compiled successfully"

# Step 5: Build Sonic Linux library in Docker
echo "[5/7] Building Sonic ${TARGET_LABEL} library in Docker..."
docker run --rm \
  -v "${PARENT_DIR}:/workspace" \
  -w /workspace/sonic \
  --platform "${DOCKER_PLATFORM}" \
  rust:1-bookworm \
  sh -c "CARGO_TARGET_DIR=${SONIC_TARGET_DIR} cargo build --release --features aac-fdk --lib"

if [ ! -f "${SONIC_LIB_LOCAL_PATH}" ]; then
    echo "ERROR: Sonic library was not produced at ${SONIC_LIB_LOCAL_PATH}"
    exit 1
fi
echo "✓ Sonic ${TARGET_LABEL} library built successfully"

# Step 6: Create release directory structure
echo "[6/7] Creating release directory structure..."
mkdir -p "${RELEASE_NAME}/web"
mkdir -p "${RELEASE_NAME}/bin"
mkdir -p "${RELEASE_NAME}/lib"

# Step 7: Copy files and create zip
echo "[7/7] Copying files and creating zip archive..."
cp "${CLI_BINARY_RELATIVE_PATH}" "${RELEASE_NAME}/bin/ariami_cli"
cp "${SQLITE_LIB_RELATIVE_PATH}" "${RELEASE_NAME}/lib/libsqlite3.so"
cp -r build/web/* "${RELEASE_NAME}/web/"
cp "${SONIC_LIB_RELATIVE_PATH}" "${RELEASE_NAME}/lib/libsonic_transcoder.so"
cp "${LAUNCHER_PATH}" "${RELEASE_NAME}/ariami_cli"
chmod +x "${RELEASE_NAME}/ariami_cli"
cp SETUP.txt "${RELEASE_NAME}/"

zip -r -q "${RELEASE_NAME}.zip" "${RELEASE_NAME}"

# Cleanup
rm -rf "${RELEASE_NAME}"

# Verify binary architecture
echo ""
echo "=== Verifying Binary ==="
unzip -q "${RELEASE_NAME}.zip"
ARCH_INFO=$(file "${RELEASE_NAME}/bin/ariami_cli" 2>/dev/null || echo "unknown")
echo "Binary info: ${ARCH_INFO}"
SQLITE_INFO=$(file "${RELEASE_NAME}/lib/libsqlite3.so" 2>/dev/null || echo "unknown")
echo "SQLite info: ${SQLITE_INFO}"
SONIC_INFO=$(file "${RELEASE_NAME}/lib/libsonic_transcoder.so" 2>/dev/null || echo "unknown")
echo "Sonic info: ${SONIC_INFO}"
if ! echo "${ARCH_INFO}" | grep -qi "${EXPECTED_FILE_ARCH}"; then
    echo "ERROR: CLI binary architecture mismatch; expected ${EXPECTED_FILE_ARCH}"
    exit 1
fi
if ! echo "${SQLITE_INFO}" | grep -qi "${EXPECTED_FILE_ARCH}"; then
    echo "ERROR: SQLite library architecture mismatch; expected ${EXPECTED_FILE_ARCH}"
    exit 1
fi
if ! echo "${SONIC_INFO}" | grep -qi "${EXPECTED_FILE_ARCH}"; then
    echo "ERROR: Sonic library architecture mismatch; expected ${EXPECTED_FILE_ARCH}"
    exit 1
fi
rm -rf "${RELEASE_NAME}"

# Summary
echo ""
echo "=== Build Complete ==="
echo "Output: ${RELEASE_NAME}.zip"
echo "Size: $(du -h ${RELEASE_NAME}.zip | cut -f1)"
echo ""
echo "Next steps:"
if [ "${ARCH}" = "arm64" ]; then
    echo "1. (Optional) Test on your Raspberry Pi"
else
    echo "1. (Optional) Test on your linux amd64 server"
fi
echo "2. Upload ${RELEASE_NAME}.zip to GitHub releases"
echo "3. Users can download with:"
echo "   curl -L https://github.com/picccassso/Ariami/releases/download/v${VERSION}/${RELEASE_NAME}.zip -o ariami-cli.zip"
echo ""
if [ "${ARCH}" = "arm64" ]; then
    echo "Note: Built on M2 Pro (ARM64) - no emulation needed!"
else
    echo "Note: Built for linux/amd64 via emulation; this is slower than the native arm64 build."
fi
