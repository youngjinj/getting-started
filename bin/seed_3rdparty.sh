#!/bin/bash
# Temporary workaround for GitHub 504 errors when downloading CUBRID 3rd-party libs.
# Seeds a build tree's 3rdparty/Download dir from a local cache so the build is offline.
#
# Usage:
#   ./seed_3rdparty.sh [SRC_DIR] [PRESET]
#     SRC_DIR : CUBRID source dir (default: current dir)
#     PRESET  : debug | release   (default: debug)
#
# Run AFTER `cmake --preset <preset>` and BEFORE `cmake --build ... --target install`.

set -e
CACHE="${CUBRID_3RDPARTY_CACHE:-$HOME/.cubrid_3rdparty_cache}"
SRC_DIR="${1:-$(pwd)}"
PRESET="${2:-debug}"
DEST="$SRC_DIR/build_preset_${PRESET}/3rdparty/Download"

[ -d "$CACHE" ]   || { echo "ERROR: cache not found: $CACHE"; exit 1; }
[ -d "$DEST" ]    || mkdir -p "$DEST"

echo "Seeding $DEST from $CACHE"
copied=0
cd "$CACHE"
find . -name "*.tar.gz" -size +0c | while read -r f; do
  mkdir -p "$DEST/$(dirname "$f")"
  # overwrite only if dest is missing or empty (don't clobber a valid existing file)
  if [ ! -s "$DEST/$f" ]; then
    cp -f "$f" "$DEST/$f"
    echo "  + $f"
  fi
done

echo "Done. Now run:"
echo "  cmake --build --preset ${PRESET} --target install"
