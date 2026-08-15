#!/usr/bin/env bash
set -euo pipefail

BUILD_ARCH="$(dpkg-architecture -qDEB_BUILD_ARCH)"

chmod +x debian/rules

if [[ "$BUILD_ARCH" == "arm64" ]]; then
	echo "Building natively for arm64"
	exec dpkg-buildpackage -us -uc -b
fi

if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
	echo "ARM64 cross compiler is missing." >&2
	echo "Install it with: sudo apt install crossbuild-essential-arm64" >&2
	exit 1
fi

echo "Cross-building arm64 package on $BUILD_ARCH"
exec dpkg-buildpackage -us -uc -b -aarm64
