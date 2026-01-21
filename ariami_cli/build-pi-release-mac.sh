#!/bin/bash
set -e

# Ariami CLI - Raspberry Pi Release Builder for Mac
# Builds ARM64 release using Docker (no Raspberry Pi needed)

VERSION="1.9.0_testing"
RELEASE_NAME="ariami-cli-raspberry-pi-arm64-v${VERSION}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Ariami CLI - Raspberry Pi Release Builder (Mac) ==="
echo "Version: ${VERSION}"
echo "Target: ARM64 (aarch64) Linux"
echo "Platform: macOS with Docker"
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

# Step 1: Clean previous builds
echo "[1/7] Cleaning previous builds..."
rm -rf build/
rm -rf "${RELEASE_NAME}"
rm -f "${RELEASE_NAME}.zip"
rm -f ariami_cli

# Step 2: Get dependencies on Mac
echo "[2/6] Getting dependencies on Mac..."
flutter pub get

# Step 3: Build web UI (natively on Mac)
echo "[3/6] Building web UI on Mac..."
flutter build web -t lib/web/main.dart

# Step 4: Compile ARM64 binary using Docker
echo "[4/6] Compiling ARM64 binary in Docker (this may take a minute)..."

# Get parent directory (contains both ariami_cli and ariami_core)
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

docker run --rm \
  -v "${PARENT_DIR}:/workspace" \
  -w /workspace/ariami_cli \
  --platform linux/arm64 \
  ghcr.io/cirruslabs/flutter:stable \
  sh -c "flutter pub get && dart compile exe bin/ariami_cli.dart -o ariami_cli"

echo "✓ ARM64 binary compiled successfully"

# Step 5: Create release directory structure
echo "[5/6] Creating release directory structure..."
mkdir -p "${RELEASE_NAME}/web"

# Step 6: Copy files and create zip
echo "[6/6] Copying files and creating zip archive..."
cp ariami_cli "${RELEASE_NAME}/"
cp -r build/web/* "${RELEASE_NAME}/web/"
cp SETUP.txt "${RELEASE_NAME}/"

zip -r -q "${RELEASE_NAME}.zip" "${RELEASE_NAME}"

# Cleanup
rm -rf "${RELEASE_NAME}"
rm -f ariami_cli

# Verify binary architecture
echo ""
echo "=== Verifying Binary ==="
unzip -q "${RELEASE_NAME}.zip"
ARCH_INFO=$(file "${RELEASE_NAME}/ariami_cli" 2>/dev/null || echo "unknown")
echo "Binary info: ${ARCH_INFO}"
rm -rf "${RELEASE_NAME}"

# Summary
echo ""
echo "=== Build Complete ==="
echo "Output: ${RELEASE_NAME}.zip"
echo "Size: $(du -h ${RELEASE_NAME}.zip | cut -f1)"
echo ""
echo "Next steps:"
echo "1. (Optional) Test on your Raspberry Pi"
echo "2. Upload ${RELEASE_NAME}.zip to GitHub releases"
echo "3. Users can download with:"
echo "   curl -L https://github.com/picccassso/Ariami/releases/download/v${VERSION}/${RELEASE_NAME}.zip -o ariami-cli.zip"
echo ""
echo "Note: Built on M2 Pro (ARM64) - no emulation needed!"
