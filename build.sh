#!/usr/bin/env bash
#
# Build Thunar with a two-row toolbar from the official source tarball and
# install the resulting binary over the system one.
#
#   ./build.sh [version]
#
# Environment:
#   WORKDIR=/tmp/...   where the source is downloaded and built
#   INSTALL=0          build only, do not touch /usr/bin/thunar
#   SRC_URL=...        use a custom source tarball URL
#
set -euo pipefail

VERSION="${1:-4.20.2}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/thunar-two-row-toolbar.patch"
WORKDIR="${WORKDIR:-/tmp/thunar-two-row-toolbar-$VERSION}"
SRC_URL="${SRC_URL:-https://deb.debian.org/debian/pool/main/t/thunar/thunar_${VERSION}.orig.tar.bz2}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

die() { echo "error: $*" >&2; exit 1; }

[ -f "$PATCH" ] || die "patch not found: $PATCH"

echo "==> checking build dependencies"
for pc in gtk+-3.0 libxfce4ui-2 libxfce4util-7 exo-2 gdk-pixbuf-2.0; do
  pkg-config --exists "$pc" || die "missing pkg-config module '$pc' (see README for the apt packages)"
done
for bin in gcc make patch tar; do
  command -v "$bin" >/dev/null || die "missing build tool: $bin"
done

MULTIARCH="$(gcc -print-multiarch 2>/dev/null || true)"
[ -n "$MULTIARCH" ] || MULTIARCH="$(uname -m)-linux-gnu"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

TARBALL="thunar_${VERSION}.orig.tar.bz2"
if [ ! -f "$TARBALL" ]; then
  echo "==> downloading $SRC_URL"
  curl -fL -o "$TARBALL" "$SRC_URL" || die "download failed (wrong version? set SRC_URL)"
fi

SRCDIR="thunar-$VERSION"
rm -rf "$SRCDIR"
echo "==> extracting"
tar xjf "$TARBALL"
[ -d "$SRCDIR" ] || die "unexpected tarball layout"

cd "$SRCDIR"
echo "==> applying patch"
patch -p1 < "$PATCH"

echo "==> configuring"
./configure --prefix=/usr \
            --libdir="/usr/lib/$MULTIARCH" \
            --sysconfdir=/etc \
            --disable-static \
            --enable-gtk-doc=no \
            --disable-debug

echo "==> building with $(nproc) jobs"
make -j"$(nproc)"

BINARY="thunar/.libs/thunar"
[ -x "$BINARY" ] || die "build did not produce $BINARY"

if [ "${INSTALL:-1}" != "1" ]; then
  echo "==> built: $WORKDIR/$SRCDIR/$BINARY (INSTALL=0, not installed)"
  exit 0
fi

if [ ! -f /usr/bin/thunar.orig ]; then
  echo "==> backing up /usr/bin/thunar -> /usr/bin/thunar.orig"
  $SUDO cp -a /usr/bin/thunar /usr/bin/thunar.orig
fi

echo "==> installing"
strip -o "$WORKDIR/thunar.stripped" "$BINARY"
$SUDO install -m 755 "$WORKDIR/thunar.stripped" /usr/bin/thunar

# keep the package manager from silently overwriting the patched binary
if command -v apt-mark >/dev/null; then
  $SUDO apt-mark hold thunar >/dev/null 2>&1 || true
fi

cat <<EOF

Done.

Restart Thunar:
  thunar -q; thunar

The original binary is at /usr/bin/thunar.orig and the package is pinned with
"apt-mark hold thunar". To revert:
  sudo cp /usr/bin/thunar.orig /usr/bin/thunar
  sudo apt-mark unhold thunar
EOF
