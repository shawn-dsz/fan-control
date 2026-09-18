#!/bin/zsh
set -euo pipefail

# Install a built Fan Control.app into ~/Applications, clear Gatekeeper
# quarantine from copies, and re-sign adhoc so it can launch on this Mac.

project_dir=${0:A:h}
src="${1:-$project_dir/build/Fan Control.app}"
dest="$HOME/Applications/Fan Control.app"

if [[ ! -d "$src" ]]; then
  echo "Missing app bundle: $src" >&2
  echo "Build first with ./build.sh (needs Xcode CLT license accepted + Stats.app)." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$dest"
ditto "$src" "$dest"
xattr -cr "$dest"
codesign --force --deep --sign - "$dest"
echo "Installed: $dest"
echo "Launch with: open \"$dest\""
