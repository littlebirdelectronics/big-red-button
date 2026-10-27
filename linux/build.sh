#!/usr/bin/env bash
# Cross-compiles static bigredbutton binaries into dist/.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
rm -rf dist && mkdir -p dist

build() { # name goarch [goarm]
  echo "building $1"
  CGO_ENABLED=0 GOOS=linux GOARCH="$2" GOARM="${3:-}" \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o "dist/$1" .
}
build bigredbutton-linux-arm64 arm64
build bigredbutton-linux-armv6 arm 6   # every Raspberry Pi, including Zero and Pi 1
build bigredbutton-linux-amd64 amd64

(cd dist && shasum -a 256 bigredbutton-linux-* > SHA256SUMS 2>/dev/null || sha256sum bigredbutton-linux-* > SHA256SUMS)
ls -l dist
