#!/usr/bin/env bash
# Fetches the GUT test framework into addons/gut/.
#
# GUT is not vendored: it is a third-party addon with its own release cadence,
# and keeping it out of the tree means `git log` stays about Aphelion. CI runs
# this before the test job; run it once locally to test from the editor.
#
# Two routes are tried. The tarball is faster and is what CI normally uses, but
# some sandboxed environments allow `git` through a proxy while blocking
# GitHub's archive endpoints, so a shallow clone is kept as a fallback.
set -euo pipefail

GUT_VERSION="${GUT_VERSION:-9.7.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/addons/gut"

if [ -d "$DEST" ] && [ -f "$DEST/plugin.cfg" ]; then
  echo "GUT already present at $DEST (delete it to re-fetch)."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_from() {
  local src="$1"
  [ -d "$src" ] || return 1
  mkdir -p "$ROOT/addons"
  rm -rf "$DEST"
  cp -R "$src" "$DEST"
  echo "Installed GUT ${GUT_VERSION} to $DEST"
}

URL="https://github.com/bitwes/Gut/archive/refs/tags/v${GUT_VERSION}.tar.gz"
echo "Fetching GUT ${GUT_VERSION} from ${URL}"
if curl -fsSL "$URL" -o "$TMP/gut.tar.gz" 2>/dev/null \
   && tar -xzf "$TMP/gut.tar.gz" -C "$TMP" 2>/dev/null \
   && install_from "$TMP/Gut-${GUT_VERSION}/addons/gut"; then
  exit 0
fi

echo "Archive download unavailable; falling back to a shallow clone."
if git clone --depth 1 --branch "v${GUT_VERSION}" \
     https://github.com/bitwes/Gut.git "$TMP/gut" >/dev/null 2>&1 \
   && install_from "$TMP/gut/addons/gut"; then
  exit 0
fi

echo "error: could not fetch GUT ${GUT_VERSION} by either route." >&2
echo "       Check network access, or install it manually into addons/gut/." >&2
exit 1
