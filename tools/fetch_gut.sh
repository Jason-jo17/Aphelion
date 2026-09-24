#!/usr/bin/env bash
# Fetches the GUT test framework into addons/gut/.
#
# GUT is not vendored: it is a third-party addon with its own release cadence,
# and keeping it out of the tree means `git log` stays about Aphelion. CI runs
# this before the test job; run it once locally to test from the editor.
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

URL="https://github.com/bitwes/Gut/archive/refs/tags/v${GUT_VERSION}.tar.gz"
echo "Fetching GUT ${GUT_VERSION} from ${URL}"
curl -fsSL "$URL" -o "$TMP/gut.tar.gz"
tar -xzf "$TMP/gut.tar.gz" -C "$TMP"

SRC="$TMP/Gut-${GUT_VERSION}/addons/gut"
if [ ! -d "$SRC" ]; then
  echo "error: the archive did not contain addons/gut — has the layout changed?" >&2
  exit 1
fi

mkdir -p "$ROOT/addons"
cp -R "$SRC" "$DEST"
echo "Installed GUT ${GUT_VERSION} to $DEST"
