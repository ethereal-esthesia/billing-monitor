#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

project_dir=${0:A:h}
app_dir=$($project_dir/build-widget.sh)
open "$app_dir"
