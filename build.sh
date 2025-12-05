#!/bin/bash
set -e # Exit immediately if any command fails

# 1. Setup Basic Variables
PROJECT_ROOT=$(pwd)
NDK_ZIP="android-ndk-r14b-linux-x86_64.zip"
NDK_DIR="android-ndk-r14b"
NDK_URL="https://dl.google.com/android/repository/${NDK_ZIP}"
JNI_DIR="limbo-android-lib/src/main/jni"
QEMU_VERSION="5.1.0" # Target QEMU 5.1.0

echo "========================================"
echo "Starting Limbo x86 Emulator Build for ARM64 Host (QEMU ${QEMU_VERSION})"
echo "========================================"

# 2. Install Required Dependencies (Confirmed for ubuntu-latest)
echo "Installing required dependencies..."
sudo apt-get update
# FIX: Installing libncurses-dev to resolve linking error during native compilation.
sudo apt-get install -y make autoconf automake git binutils libtool-bin pkg-config flex bison gettext texinfo rsync python3 patch gtk-doc-tools libncurses-dev

# 3. Setup Android NDK r14b
echo "Downloading and extracting Android NDK r14b..."
wget -q --show-progress $NDK_URL
unzip -q $NDK_ZIP
rm $NDK_ZIP

export NDK_ROOT=$PROJECT_ROOT/$NDK_DIR
echo "NDK_ROOT set to: $NDK_ROOT"

# 4. Download and Extract External Libraries
mkdir -p $JNI_DIR
cd $JNI_DIR

echo "Downloading and extracting external libraries (QEMU, glib, libffi, pixman, SDL2)..."

# QEMU 5.1.0
wget -q --show-progress http://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz
tar -xJf qemu-${QEMU_VERSION}.tar.xz
mv qemu-${QEMU_VERSION} qemu
rm qemu-${QEMU_VERSION}.tar.xz

# glib 2.56.1
wget -q --show-progress https://ftp.gnome.org/pub/GNOME/sources/glib/2.56/glib-2.56.1.tar.xz
tar -xJf glib-2.56.1.tar.xz
mv glib-2.56.1 glib
rm glib-2.56.1.tar.xz

# libffi 3.3
wget -q --show-progress https://sourceware.org/pub/libffi/libffi-3.3.tar.gz
tar -xzf libffi-3.3.tar.gz
mv libffi-3.3 libffi
rm libffi-3.3.tar.gz

# pixman 0.40.0
wget -q --show-progress https://www.cairographics.org/releases/pixman-0.40.0.tar.gz
tar -xzf /tmp/pixman-0.40.0.tar.gz
mv pixman-0.40.0 pixman
rm pixman-0.40.0.tar.gz

# SDL2 2.0.8
wget -q --show-progress https://www.libsdl.org/release/SDL2-2.0.8.tar.gz
tar -xzf SDL2-2.0.8.tar.gz
mv SDL2-2.0.8 SDL2
rm SDL2-2.0.8.tar.gz

# 5. Apply Patches
echo "Applying patches..."

# QEMU Patch
cd qemu
patch -p1 < ../patches/qemu-${QEMU_VERSION}.patch
cd ..

# glib Patch
cd glib
patch -p1 < ../patches/glib-2.56.1.patch
cd ..

# SDL2 Patch
cd SDL2
patch -p1 < ../patches/sdl2-2.0.8.patch
cd ..

# 6. Build Native Libraries
echo "Starting native libraries build for ARM64 Host..."

# Return to project root to set NDK_ROOT correctly
cd $PROJECT_ROOT

# Set environment variables for the build
export NDK_ROOT=$PROJECT_ROOT/$NDK_DIR
export USE_GCC=true
export USE_QEMU_VERSION=$QEMU_VERSION
export BUILD_HOST=arm64-v8a # Target ARM64 phones (most common modern device)
export BUILD_GUEST=x86_64-softmmu # Target x86 emulation (as requested)
export USE_AAUDIO=false 

# Enter JNI directory and start the build
cd $JNI_DIR
make limbo

# 7. Build APK using Gradle
echo "Starting APK build using Gradle..."

# Return to project root
cd $PROJECT_ROOT

# Set environment variables for Gradle
export ANDROID_SDK_ROOT=/usr/local/lib/android/sdk

# FIX: Force creation of Gradle Wrapper 6.5 to be compatible with AGP 4.1.1, 
# which solves the persistent 'forUseAtConfigurationTime' error.
if [ ! -f "gradlew" ]; then
    echo "Creating Gradle Wrapper compatible with AGP 4.1.1 (Gradle 6.5)..."
    gradle wrapper --gradle-version 6.5
fi
# Ensure execute permission is set on the script
chmod +x gradlew

# Execute the build
./gradlew :limbo-android-x86:assembleRelease

echo "========================================"
echo "Build completed successfully. APK is located in limbo-android-x86/build/outputs/apk/release/"
echo "========================================"
