#!/bin/zsh
set -euo pipefail

if (( EUID != 0 )); then
  echo 'Administrator authorization is required.' >&2
  exit 1
fi

uid=${1:-}
if [[ ! "$uid" =~ '^[0-9]+$' ]]; then
  echo 'Invalid user ID.' >&2
  exit 1
fi

resources=${0:A:h}
helper_dir=/Library/PrivilegedHelperTools
plist=/Library/LaunchDaemons/local.shawndsouza.FanControl.Helper.plist
label=local.shawndsouza.FanControl.Helper

if [[ -e "$plist" ]]; then
  /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
fi

/usr/bin/install -o root -g wheel -m 755 "$resources/FanControlHelper" "$helper_dir/$label"
/usr/bin/install -o root -g wheel -m 755 "$resources/fan-smc" "$helper_dir/local.shawndsouza.FanControl.smc"
/usr/bin/sed "s/__UID__/$uid/g" "$resources/local.shawndsouza.FanControl.Helper.plist" > "$plist"
/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"
/usr/bin/plutil -lint "$plist" >/dev/null
/bin/launchctl bootstrap system "$plist"
echo 'Fan helper installed.'
