#!/bin/bash

# Bootable USB Utility Build Script
# This script builds the macOS application

set -e

echo "🔨 Building Bootable USB Utility..."

# Change to project directory
cd "$(dirname "$0")"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
xcodebuild clean -project BootableUSBUtility.xcodeproj -scheme BootableUSBUtility

# Build the application
echo "🏗️  Building application..."
xcodebuild build -project BootableUSBUtility.xcodeproj -scheme BootableUSBUtility -configuration Release

# Create app bundle in Applications folder
echo "📦 Creating application bundle..."
APP_PATH="$(xcodebuild -project BootableUSBUtility.xcodeproj -scheme BootableUSBUtility -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | cut -d' ' -f3)/BootableUSBUtility.app"

if [ -d "$APP_PATH" ]; then
    echo "✅ Build successful!"
    echo "📱 Application created at: $APP_PATH"
    echo ""
    echo "To install system-wide, run:"
    echo "sudo cp -R '$APP_PATH' /Applications/"
    echo ""
    echo "To run the application:"
    echo "open '$APP_PATH'"
else
    echo "❌ Build failed!"
    exit 1
fi
