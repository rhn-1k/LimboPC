#!/bin/bash
set -e 

# 1. Setup Basic Variables
PROJECT_ROOT=$(pwd)
NDK_ZIP="android-ndk-r14b-linux-x86_64.zip"
NDK_DIR="android-ndk-r14b"
NDK_URL="https://dl.google.com/android/repository/${NDK_ZIP}"
JNI_DIR="limbo-android-lib/src/main/jni"
QEMU_VERSION="5.1.0" 

echo "========================================"
echo "Starting Limbo x86 Emulator Build for ARM64 Host (QEMU ${QEMU_VERSION})"
echo "========================================"

# 2. Install Required Dependencies and Fix Linking Issues
echo "Installing required dependencies and fixing Ncurses linking..."
sudo apt-get update
sudo apt-get install -y make autoconf automake git binutils libtool-bin pkg-config flex bison gettext texinfo rsync python3 patch gtk-doc-tools libncurses-dev

# FIX: Create symlink for libncurses.so.5 to point to the modern libncurses.so.6
# This fixes the BFD linking error during native compilation (Step 6).
echo "Creating symlink for libncurses.so.5 to fix NDK linker issue..."
if [ -f /usr/lib/x86_64-linux-gnu/libncurses.so.6 ]; then
    sudo ln -s /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
elif [ -f /lib/x86_64-linux-gnu/libncurses.so.6 ]; then
    sudo ln -s /lib/x86_64-linux-gnu/libncurses.so.6 /lib/x86_64-linux-gnu/libncurses.so.5
fi

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
QEMU_FILE="qemu-${QEMU_VERSION}.tar.xz"
wget -q --show-progress http://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz
tar -xJf $QEMU_FILE
mv qemu-${QEMU_VERSION} qemu
rm $QEMU_FILE

# glib 2.56.1
GLIB_FILE="glib-2.56.1.tar.xz"
wget -q --show-progress https://ftp.gnome.org/pub/GNOME/sources/glib/2.56/glib-2.56.1.tar.xz
tar -xJf $GLIB_FILE
mv glib-2.56.1 glib
rm $GLIB_FILE

# libffi 3.3
LIBFFI_FILE="libffi-3.3.tar.gz"
wget -q --show-progress https://sourceware.org/pub/libffi/libffi-3.3.tar.gz
tar -xzf $LIBFFI_FILE
mv libffi-3.3 libffi
rm $LIBFFI_FILE

# pixman 0.40.0
PIXMAN_FILE="pixman-0.40.0.tar.gz"
wget -q --show-progress https://www.cairographics.org/releases/pixman-0.40.0.tar.gz
tar -xzf $PIXMAN_FILE
mv pixman-0.40.0 pixman
rm $PIXMAN_FILE

# SDL2 2.0.8
SDL2_FILE="SDL2-2.0.8.tar.gz"
wget -q --show-progress https://www.libsdl.org/release/SDL2-2.0.8.tar.gz
tar -xzf $SDL2_FILE
mv SDL2-2.0.8 SDL2
rm $SDL2_FILE

# 5. Apply Patches
echo "Applying patches..."
cd qemu
patch -p1 < ../patches/qemu-${QEMU_VERSION}.patch
cd ..
cd glib
patch -p1 < ../patches/glib-2.56.1.patch
cd ..
cd SDL2
patch -p1 < ../patches/sdl2-2.0.8.patch
cd ..

# 6. Build Native Libraries
echo "Starting native libraries build for ARM64 Host..."
cd $PROJECT_ROOT
export NDK_ROOT=$PROJECT_ROOT/$NDK_DIR
export USE_GCC=true
export USE_QEMU_VERSION=$QEMU_VERSION
export BUILD_HOST=arm64-v8a 
export BUILD_GUEST=x86_64-softmmu 
export USE_AAUDIO=false 
cd $JNI_DIR
make limbo

# 7. Build APK using Gradle
echo "Starting APK build using Gradle..."
cd $PROJECT_ROOT
export ANDROID_SDK_ROOT=/usr/local/lib/android/sdk

# FIX (Crucial): Force creation/update of Gradle Wrapper 6.5. 
# This fixes the incompatibility between AGP 4.1.1 and the current Gradle 7.0.2 (as found in properties file).
if [ ! -f "gradlew" ]; then
    echo "Creating Gradle Wrapper compatible with AGP 4.1.1 (Gradle 6.5)..."
    gradle wrapper --gradle-version 6.5
else
    # Also update the existing wrapper if it exists (to fix the 7.0.2 issue)
    echo "Updating existing Gradle Wrapper to 6.5 to ensure compatibility..."
    gradle wrapper --gradle-version 6.5
fi
chmod +x gradlew
./gradlew :limbo-android-x86:assembleRelease

echo "========================================"
echo "Build completed successfully. APK is located in limbo-android-x86/build/outputs/apk/release/"
echo "========================================"
