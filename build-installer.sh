#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

project_dir=${0:A:h}
app_dir=$($project_dir/build-widget.sh)
dist_dir="$project_dir/dist"
installer="$dist_dir/Usage Pie.dmg"
staging_dir=$(mktemp -d)

cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$dist_dir"
cp -R "$app_dir" "$staging_dir/Usage Pie.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Usage Pie" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$installer"

echo "$installer"
