#!/bin/sh
# Build an EnGenius IPQ807x OpenWrt tree: clone the pinned base, apply this
# overlay's patch series, wire up the NSS feed. Nothing here vendors upstream
# code -- the patches are the only content.
#
# Usage: ./setup.sh [target-dir]      (default: ./build-tree)
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/BASE"
TREE=${1:-$HERE/build-tree}

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

if [ -e "$TREE" ]; then
    echo "refusing to touch existing path: $TREE" >&2
    echo "remove it, or pass a different target directory." >&2
    exit 1
fi

echo "==> cloning pinned base into $TREE"
mkdir -p "$TREE"
git -C "$TREE" init -q
git -C "$TREE" remote add origin "$BASE_REPO"
# single-commit fetch; GitHub allows fetching a bare SHA
git -C "$TREE" fetch -q --depth 1 origin "$BASE_COMMIT"
git -C "$TREE" checkout -q FETCH_HEAD
git -C "$TREE" checkout -q -b engenius-ipq807x

echo "==> applying $(ls "$HERE"/patches/*.patch | wc -l | tr -d ' ') patches"
git -C "$TREE" am --keep-non-patch "$HERE"/patches/*.patch

echo "==> configuring feeds"
cp "$TREE/feeds.conf.default" "$TREE/feeds.conf"
printf 'src-git nss %s;%s\n' "$NSS_FEED_URL" "$NSS_FEED_BRANCH" >> "$TREE/feeds.conf"
( cd "$TREE" && ./scripts/feeds update -a && ./scripts/feeds install -a )

cat <<DONE

Tree ready: $TREE

Next:
  cd $TREE
  make menuconfig     # Target: qualcommax / ipq807x, then a DEVICE_engenius_* profile
  make -j\$(nproc)

Profiles: engenius_ecw336, engenius_ews377ap-v3, engenius_ecw230v3, engenius_ews377-fit

After ANY change that can move a kernel CONFIG symbol, delete the kernel build
tree before rebuilding -- a stale out-of-tree kmod does not fail to load, it
corrupts. See the README.
DONE
