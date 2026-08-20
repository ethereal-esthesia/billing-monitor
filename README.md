# Usage Pie

Usage Pie is a tiny, draggable macOS usage monitor for Codex. It reads the
current account usage from the locally installed Codex app server and displays
it as a transparent, borderless pie divided into one equal section per day in
the current usage window.

## Features

- Native macOS interface built with Swift and AppKit
- Transparent, borderless, always-on-top window
- Drag from anywhere and remember the last window position
- Divide the usage window into equal daily sections
- Show current usage percentage and reset date
- Poll automatically at a configurable interval
- Refresh usage, reload settings, or quit from the right-click menu
- Read usage without storing browser cookies or account credentials

## Requirements

- macOS 13 or later
- Apple Swift toolchain or Xcode Command Line Tools
- Node.js
- Codex CLI or the ChatGPT app, signed in to a Codex-enabled account

## Run

Build and launch the widget:

```sh
./run-widget.sh
```

Build the app without launching it:

```sh
./build-widget.sh
```

The generated application is `Usage Pie.app`.

To retrieve the same usage information as JSON without opening the widget:

```sh
./codex-usage.mjs
```

## Settings

Edit [`usage-pie.settings.json`](usage-pie.settings.json):

```json
{
  "opacity": 0.30,
  "pollIntervalSeconds": 300
}
```

- `opacity` accepts values from `0.05` through `1.0`.
- `pollIntervalSeconds` controls how often usage is checked and has a minimum
  value of 15 seconds.

After editing the file, right-click the widget and choose **Reload Settings**,
or relaunch the app.

You can override executable and settings locations with `CODEX_BIN`,
`NODE_BIN`, `CODEX_USAGE_SCRIPT`, and `USAGE_PIE_SETTINGS`.

## Project layout

- `UsagePie.swift` — native window, chart, polling, and settings
- `codex-usage.mjs` — one-shot Codex usage reader
- `usage-pie.settings.json` — user-editable widget configuration
- `build-widget.sh` — creates the macOS app bundle
- `run-widget.sh` — builds and launches the widget

## License

Copyright © 2026 Shane Reilly.

Usage Pie is free software licensed under the GNU General Public License,
version 3 or any later version. See [`LICENSE`](LICENSE) for the complete terms.
