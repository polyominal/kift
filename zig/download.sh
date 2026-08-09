#!/usr/bin/env sh

# adapted from
# <https://github.com/tigerbeetle/tigerbeetle/blob/97c7a8ef385270ebe0e1b75959d3d21d134629df/zig/download.sh>

set -eu

# to move to a newer nightly, update ZIG_RELEASE and the checksums below
# from <https://ziglang.org/download/index.json>, then re-run this script
ZIG_MIRROR="https://ziglang.org/builds"
ZIG_RELEASE="0.17.0-dev.1609+11e2bb391"
ZIG_CHECKSUMS=$(cat<<EOF
${ZIG_MIRROR}/zig-aarch64-macos-${ZIG_RELEASE}.tar.xz 7b1e292828d33c4f1fc2ca042c84b6bd980b56e0fb638f31f111809d243d728e
${ZIG_MIRROR}/zig-x86_64-macos-${ZIG_RELEASE}.tar.xz eab2350d8f09504ce0a12dc38ec4f7690a0accd16df030327e37bd4a884f9aeb
${ZIG_MIRROR}/zig-aarch64-linux-${ZIG_RELEASE}.tar.xz c6c25da2308723fa2d956c9f2100237d69aadd3297c286851ec928a2fc309b54
${ZIG_MIRROR}/zig-x86_64-linux-${ZIG_RELEASE}.tar.xz be19b234c47af01f0333fcb7212a59840c2ba3531ed9374cd79b3695c48a66c9
EOF
)

# determine arch
if [ "$(uname -m)" = 'arm64' ] || [ "$(uname -m)" = 'aarch64' ]; then
    ZIG_ARCH="aarch64"
else
    ZIG_ARCH="x86_64"
fi

# determine OS
case "$(uname)" in
    Darwin)
        ZIG_OS="macos"
        ;;
    Linux)
        ZIG_OS="linux"
        ;;
    *)
        echo "unknown OS"
        exit 1
        ;;
esac

# only the host tuples we test against are supported; anything else fails
# fast here instead of with a confusing curl/checksum error below
case "${ZIG_ARCH}-${ZIG_OS}" in
    aarch64-macos | x86_64-linux) ;;
    *)
        echo "unsupported host tuple: ${ZIG_ARCH}-${ZIG_OS}"
        echo "supported: aarch64-macos, x86_64-linux"
        exit 1
        ;;
esac

ZIG_EXTENSION=".tar.xz"

ZIG_URL="${ZIG_MIRROR}/zig-${ZIG_ARCH}-${ZIG_OS}-${ZIG_RELEASE}${ZIG_EXTENSION}"
ZIG_CHECKSUM_EXPECTED=$(echo "$ZIG_CHECKSUMS" | grep -F "$ZIG_URL" | cut -d ' ' -f 2)

ZIG_ARCHIVE="./zig/cache/$(basename "$ZIG_URL")"
ZIG_DIRECTORY=$(basename "$ZIG_ARCHIVE" "$ZIG_EXTENSION")
ZIG_EXTRACT="./zig/extract"

# returns 0 iff the given file exists and SHA-256 checks out
checksum_valid() {
    [ -f "$ZIG_ARCHIVE" ] || return 1
    ZIG_CHECKSUM_ACTUAL=""
    if command -v sha256sum > /dev/null; then
        ZIG_CHECKSUM_ACTUAL=$(sha256sum "$ZIG_ARCHIVE" | cut -d ' ' -f 1)
    elif command -v shasum > /dev/null; then
        ZIG_CHECKSUM_ACTUAL=$(shasum -a 256 "$ZIG_ARCHIVE" | cut -d ' ' -f 1)
    else
        echo "neither sha256sum nor shasum available"
        exit 1
    fi
    [ "$ZIG_CHECKSUM_ACTUAL" = "$ZIG_CHECKSUM_EXPECTED" ]
}

if checksum_valid; then
    echo "skip downloading Zig $ZIG_RELEASE"
else
    echo "downloading Zig $ZIG_RELEASE ..."
    mkdir -p ./zig/cache
    curl --fail --location --silent --show-error --output "$ZIG_ARCHIVE" "$ZIG_URL"

    if ! checksum_valid; then
        echo "checksum mismatch"
        exit 1
    fi
fi

echo "extracting $ZIG_ARCHIVE ..."
rm -rf "$ZIG_EXTRACT"
mkdir -p "$ZIG_EXTRACT"
tar -xf "$ZIG_ARCHIVE" -C "$ZIG_EXTRACT"

rm -rf zig/doc
rm -rf zig/lib
mv "$ZIG_EXTRACT/$ZIG_DIRECTORY/LICENSE" zig/
mv "$ZIG_EXTRACT/$ZIG_DIRECTORY/README.md" zig/
mv "$ZIG_EXTRACT/$ZIG_DIRECTORY/doc" zig/
mv "$ZIG_EXTRACT/$ZIG_DIRECTORY/lib" zig/
mv "$ZIG_EXTRACT/$ZIG_DIRECTORY/zig" zig/

rmdir "$ZIG_EXTRACT/$ZIG_DIRECTORY"
rmdir "$ZIG_EXTRACT"

# it's up to the user to add this to their path if they want to
ZIG_BIN="$(pwd)/zig/zig"
echo "downloading completed ($ZIG_BIN)!"
