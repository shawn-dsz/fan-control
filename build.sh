#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/build/Fan Control.app"
contents="$app/Contents"

mkdir -p "$contents/MacOS" "$contents/Resources"
swiftc -O -target arm64-apple-macosx13.0 \
  "$project_dir/Sources/FanParser.swift" \
  "$project_dir/Sources/FanSpeedPlan.swift" \
  "$project_dir/Sources/CPUTemperatureParser.swift" \
  "$project_dir/Sources/FanTemperatureEstimator.swift" \
  "$project_dir/Sources/TemperatureFanController.swift" \
  "$project_dir/Sources/FanSocket.swift" \
  "$project_dir/Sources/FanHelperClient.swift" \
  "$project_dir/Sources/FanControlApp.swift" \
  -o "$contents/MacOS/FanControl"
swiftc -O -target arm64-apple-macosx13.0 \
  "$project_dir/Sources/FanParser.swift" \
  "$project_dir/Sources/FanSpeedPlan.swift" \
  "$project_dir/Sources/FanSocket.swift" \
  "$project_dir/Sources/FanHelper.swift" \
  -o "$contents/Resources/FanControlHelper"
cp /Applications/Stats.app/Contents/Resources/smc "$contents/Resources/fan-smc"
cp "$project_dir/Resources/install-helper.sh" "$contents/Resources/install-helper.sh"
cp "$project_dir/Resources/local.shawndsouza.FanControl.Helper.plist" "$contents/Resources/local.shawndsouza.FanControl.Helper.plist"
cp "$project_dir/Resources/LICENSE.stats" "$contents/Resources/LICENSE.stats"
cp "$project_dir/Resources/FanControl.icns" "$contents/Resources/FanControl.icns"

cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.shawndsouza.FanControl</string>
  <key>CFBundleName</key><string>Fan Control</string>
  <key>CFBundleDisplayName</key><string>Fan Control</string>
  <key>CFBundleExecutable</key><string>FanControl</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>26</string>
  <key>CFBundleShortVersionString</key><string>1.25</string>
  <key>CFBundleIconFile</key><string>FanControl.icns</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$contents/Resources/FanControlHelper"
codesign --force --sign - "$app"
echo "$app"
