#!/bin/bash
# Download CUBRID 3rd-party tarballs into the local cache, verifying SHA256.
# Use this to (re)build $HOME/.cubrid_3rdparty_cache from scratch when you have
# working network access to GitHub. Once the cache exists, seed_3rdparty.sh
# fills any build tree offline (works even while GitHub returns 504).
#
# Usage: ./fetch_3rdparty_cache.sh
#
# name|subdir|url|sha256
LIBS=(
"csql_v1.2.tar.gz|libedit|https://github.com/CUBRID/libedit/archive/refs/tags/csql_v1.2.tar.gz|140312cd2dd22b4981d22448f02ef215fd7685ca57bb90b1427e496234d2d7da"
"expat-2.6.4.tar.gz|libexpat|https://github.com/CUBRID/3rdparty/raw/develop/expat/expat-2.6.4.tar.gz|fd03b7172b3bd7427a3e7a812063f74754f24542429b634e0db6511b53fb2278"
"jansson-2.10.tar.gz|libjansson|https://github.com/CUBRID/3rdparty/raw/develop/jansson/jansson-2.10.tar.gz|78215ad1e277b42681404c1d66870097a50eb084be9d771b1d15576575cf6447"
"unixODBC-2.3.9.tar.gz|libodbc|https://github.com/CUBRID/3rdparty/raw/develop/unixODBC/unixODBC-2.3.9.tar.gz|52833eac3d681c8b0c9a5a65f2ebd745b3a964f208fc748f977e44015a31b207"
"openssl-1.1.1w.tar.gz|libopenssl|https://github.com/CUBRID/3rdparty/raw/develop/openssl/openssl-1.1.1w.tar.gz|cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
"v2021.11.0.tar.gz|libtbb|https://github.com/CUBRID/3rdparty/raw/develop/tbb/v2021.11.0.tar.gz|782ce0cab62df9ea125cdea253a50534862b563f1d85d4cda7ad4e77550ac363"
"v1.9.4.tar.gz|lz4|https://github.com/CUBRID/3rdparty/raw/develop/lz4/v1.9.4.tar.gz|0b0e3aa07c8c063ddf40b082bdf7e37a1562bda40a0ff5272957f3e987e0e54b"
"v1.1.0.tar.gz|rapidjson|https://github.com/CUBRID/3rdparty/raw/develop/rapidjson/v1.1.0.tar.gz|bf7ced29704a1e696fbccf2a2b4ea068e7774fa37f6d7dd4039d0787f8bed98e"
"2022-06-01.tar.gz|re2|https://github.com/CUBRID/3rdparty/raw/develop/re2/2022-06-01.tar.gz|f89c61410a072e5cbcf8c27e3a778da7d6fd2f2b5b1445cd4f4508bee946ab0f"
)

CACHE="${CUBRID_3RDPARTY_CACHE:-$HOME/.cubrid_3rdparty_cache}"
mkdir -p "$CACHE"
fail=0
for row in "${LIBS[@]}"; do
  IFS='|' read -r file sub url sha <<< "$row"
  dst="$CACHE/$sub/$file"
  mkdir -p "$CACHE/$sub"
  if [ -s "$dst" ] && [ "$(sha256sum "$dst" | cut -d' ' -f1)" = "$sha" ]; then
    echo "OK (cached) $sub/$file"; continue
  fi
  echo "Downloading $sub/$file ..."
  if curl -fsSL --retry 3 --connect-timeout 20 -o "$dst.tmp" "$url"; then
    act=$(sha256sum "$dst.tmp" | cut -d' ' -f1)
    if [ "$act" = "$sha" ]; then
      mv -f "$dst.tmp" "$dst"; echo "  OK $sub/$file"
    else
      echo "  HASH MISMATCH $sub/$file (got $act)"; rm -f "$dst.tmp"; fail=1
    fi
  else
    echo "  DOWNLOAD FAILED $sub/$file ($url)"; rm -f "$dst.tmp"; fail=1
  fi
done
[ "$fail" = 0 ] && echo "All cached at $CACHE" || { echo "Some downloads failed (network/GitHub?)."; exit 1; }
