#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

project_dir=${0:A:h}
app_dir="$project_dir/Usage Pie.app"
contents_dir="$app_dir/Contents"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

swiftc \
  -swift-version 5 \
  -framework AppKit \
  "$project_dir/UsagePie.swift" \
  -o "$contents_dir/MacOS/UsagePie"

cp "$project_dir/UsagePie-Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/codex-usage.mjs" "$contents_dir/Resources/codex-usage.mjs"

echo "$app_dir"
