#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

project_dir=${0:A:h}
app_dir="$project_dir/Usage Pie.app"
contents_dir="$app_dir/Contents"
iconset_dir="$project_dir/.build/UsagePie.iconset"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$iconset_dir"

swift -framework AppKit "$project_dir/IconRenderer.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/UsagePie.icns"

swiftc \
  -swift-version 5 \
  -framework AppKit \
  "$project_dir/UsagePie.swift" \
  -o "$contents_dir/MacOS/UsagePie"

cp "$project_dir/UsagePie-Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/codex-usage.mjs" "$contents_dir/Resources/codex-usage.mjs"
cp "$project_dir/infra-usage.mjs" "$contents_dir/Resources/infra-usage.mjs"
cp "$project_dir/deepseek-usage.mjs" "$contents_dir/Resources/deepseek-usage.mjs"
cp "$project_dir/usage-pie.settings.json" "$contents_dir/Resources/usage-pie.settings.json"
cp "$project_dir/infra.settings.json" "$contents_dir/Resources/infra.settings.json"
cp "$project_dir/deepseek.settings.json" "$contents_dir/Resources/deepseek.settings.json"

codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
