// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement

private struct UsageSnapshot {
    let usedPercent: Double
    let remainingPercent: Double
    let dayCount: Int
    let windowDuration: String
    let resetText: String
    let checkedAt: Date
}

private struct WidgetSettings {
    var opacity: CGFloat = 0.30
    var pollIntervalSeconds: TimeInterval = 300
    var fillColor = NSColor(srgbRed: 193 / 255, green: 233 / 255, blue: 242 / 255, alpha: 1)
}

private final class PieView: NSView {
    var snapshot = UsageSnapshot(usedPercent: 0, remainingPercent: 100, dayCount: 7,
                                 windowDuration: "7 days", resetText: "Loading…",
                                 checkedAt: Date()) {
        didSet { needsDisplay = true }
    }
    var fillColor = NSColor(srgbRed: 193 / 255, green: 233 / 255, blue: 242 / 255, alpha: 1) {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = min(bounds.width, bounds.height) * 0.42
        let innerRadius = outerRadius * 0.59
        let count = max(1, snapshot.dayCount)
        let fullTurn = CGFloat.pi * 2
        let segmentAngle = fullTurn / CGFloat(count)
        let gap = min(0.035, segmentAngle * 0.10)
        let startAt = -CGFloat.pi / 2
        let sectionColor = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 0.82)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)

        for index in 0..<count {
            let segmentStart = startAt + CGFloat(index) * segmentAngle + gap
            let segmentEnd = startAt + CGFloat(index + 1) * segmentAngle - gap
            context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                     outerRadius: outerRadius, start: segmentStart, end: segmentEnd))
            context.setFillColor(sectionColor.cgColor)
            context.fillPath()

            let filledSegments = CGFloat(snapshot.usedPercent / 100) * CGFloat(count)
            let fraction = min(1, max(0, filledSegments - CGFloat(index)))
            if fraction > 0 {
                let fillEnd = segmentStart + (segmentEnd - segmentStart) * fraction
                context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                         outerRadius: outerRadius, start: segmentStart, end: fillEnd))
                context.setFillColor(fillColor.cgColor)
                context.fillPath()
            }
        }
        context.restoreGState()

        drawCenter(center: center, innerRadius: innerRadius)
    }

    private func ringPath(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
                          start: CGFloat, end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func drawCenter(center: CGPoint, innerRadius: CGFloat) {
        let centerRect = CGRect(x: center.x - innerRadius + 4, y: center.y - innerRadius + 4,
                                width: (innerRadius - 4) * 2, height: (innerRadius - 4) * 2)
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 0.90).setFill()
        NSBezierPath(ovalIn: centerRect).fill()

        let percent = "\(Int(snapshot.usedPercent.rounded()))%"
        drawText(percent, size: 26, weight: .bold,
                 color: NSColor(calibratedWhite: 0.20, alpha: 1), y: center.y + 11)
        drawText("\(snapshot.dayCount) day window", size: 10, weight: .semibold,
                 color: NSColor(calibratedWhite: 0.34, alpha: 1), y: center.y - 13)
    }

    private func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight,
                          color: NSColor, y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: CGPoint(x: bounds.midX - textSize.width / 2,
                                    y: y - textSize.height / 2))
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var contextMenu: NSMenu!
    private let pieView = PieView(frame: NSRect(x: 0, y: 0, width: 210, height: 210))
    private var settings = WidgetSettings()
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = readSettings()
        createPanel()
        createMenus()
        createStatusItem()
        refreshUsage()
        schedulePolling()
    }

    private func createPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.alphaValue = settings.opacity
        pieView.fillColor = settings.fillColor
        panel.delegate = self
        panel.contentView = pieView

        if let saved = UserDefaults.standard.array(forKey: "windowOrigin") as? [Double], saved.count == 2 {
            panel.setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
    }

    private func createMenus() {
        statusMenu = makeMenu()
        contextMenu = makeMenu()
        pieView.menu = contextMenu
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "UsagePieStatusItem"
        statusItem.menu = statusMenu

        if let button = statusItem.button {
            button.image = makeStatusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = usageToolTip(for: pieView.snapshot)
            button.setAccessibilityLabel("Usage Pie")
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Usage Pie")
        menu.delegate = self

        let summary = NSMenuItem(title: "Loading usage…", action: nil, keyEquivalent: "")
        summary.tag = 100
        summary.isEnabled = false
        menu.addItem(summary)
        let reset = NSMenuItem(title: "Reset date unavailable", action: nil, keyEquivalent: "")
        reset.tag = 101
        reset.isEnabled = false
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "r")
        menu.addItem(withTitle: "Reload Settings", action: #selector(reloadSettings), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Widget", action: #selector(toggleWidget), keyEquivalent: "h")
        menu.addItem(withTitle: "Run at Login", action: #selector(toggleRunAtLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Usage Pie", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let summary = menu.item(withTag: 100) {
            summary.title = menuSummary(for: pieView.snapshot)
        }
        if let reset = menu.item(withTag: 101) {
            reset.title = pieView.snapshot.resetText
        }
        if let visibilityItem = menu.items.first(where: { $0.action == #selector(toggleWidget) }) {
            visibilityItem.title = panel.isVisible ? "Hide Widget" : "Show Widget"
        }
        if let loginItem = menu.items.first(where: { $0.action == #selector(toggleRunAtLogin) }) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func reloadSettings() {
        settings = readSettings()
        panel.alphaValue = settings.opacity
        pieView.fillColor = settings.fillColor
        schedulePolling()
    }

    @objc private func openSettings() {
        guard let url = editableSettingsURL() else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleWidget() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func toggleRunAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                presentError(title: "Couldn’t update Login Items", message: error.localizedDescription)
            }
        }
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(timeInterval: settings.pollIntervalSeconds,
                                         target: self,
                                         selector: #selector(refreshUsage),
                                         userInfo: nil,
                                         repeats: true)
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    @objc private func refreshUsage() {
        let previous = pieView.snapshot
        pieView.snapshot = UsageSnapshot(usedPercent: previous.usedPercent,
                                         remainingPercent: previous.remainingPercent,
                                         dayCount: previous.dayCount,
                                         windowDuration: previous.windowDuration,
                                         resetText: "Refreshing…",
                                         checkedAt: previous.checkedAt)
        let snapshot = readUsage()
        pieView.snapshot = snapshot ?? UsageSnapshot(usedPercent: 0, remainingPercent: 100,
                                                     dayCount: 7, windowDuration: "7 days",
                                                     resetText: "Usage unavailable",
                                                     checkedAt: Date())
        updateStatusItem()
    }

    private func readUsage() -> UsageSnapshot? {
        guard let script = usageScriptURL() else { return nil }

        let process = Process()
        guard let node = executable(named: "node", commonPaths: [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]) else { return nil }
        process.executableURL = node
        process.arguments = [script.path]
        process.currentDirectoryURL = script.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        if environment["CODEX_BIN"] == nil {
            let bundledCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
            if FileManager.default.isExecutableFile(atPath: bundledCodex) {
                environment["CODEX_BIN"] = bundledCodex
            }
        }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
              let limits = json["limits"] as? [[String: Any]],
              let first = limits.first,
              let primary = first["primary"] as? [String: Any] else { return nil }

        let used = primary["usedPercent"] as? Double ?? 0
        let remaining = primary["remainingPercent"] as? Double ?? max(0, 100 - used)
        let minutes = primary["windowMinutes"] as? Double ?? 10_080
        let days = max(1, Int((minutes / 1_440).rounded()))
        let duration = primary["windowDuration"] as? String ?? "\(days) days"
        let reset = primary["resetsAtLocal"] as? String ?? "Reset unknown"
        let checkedAt = (json["checkedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return UsageSnapshot(usedPercent: used, remainingPercent: remaining, dayCount: days,
                             windowDuration: duration, resetText: shortReset(reset),
                             checkedAt: checkedAt)
    }

    private func usageScriptURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_USAGE_SCRIPT"].map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL?.appendingPathComponent("codex-usage.mjs"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("codex-usage.mjs"),
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func readSettings() -> WidgetSettings {
        guard let url = settingsURL(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return WidgetSettings()
        }

        let opacity = min(1, max(0.05, json["opacity"] as? Double ?? 0.30))
        let pollSeconds = max(15, json["pollIntervalSeconds"] as? Double ?? 300)
        let fillColor = color(fromHex: json["fillColor"] as? String) ?? WidgetSettings().fillColor
        return WidgetSettings(opacity: opacity, pollIntervalSeconds: pollSeconds,
                              fillColor: fillColor)
    }

    private func color(fromHex value: String?) -> NSColor? {
        guard var hex = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8,
              let number = UInt64(hex, radix: 16) else { return nil }

        let hasAlpha = hex.count == 8
        let red = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(number & 0xFF) / 255 : 1
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private func settingsURL() -> URL? {
        let fileManager = FileManager.default
        let fileName = "usage-pie.settings.json"
        let candidates = [
            ProcessInfo.processInfo.environment["USAGE_PIE_SETTINGS"].map { URL(fileURLWithPath: $0) },
            applicationSupportSettingsURL(),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(fileName),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(fileName),
            Bundle.main.resourceURL?.appendingPathComponent(fileName),
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func editableSettingsURL() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["USAGE_PIE_SETTINGS"] {
            return URL(fileURLWithPath: override)
        }

        let sibling = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("usage-pie.settings.json")
        if !Bundle.main.bundleURL.path.hasPrefix("/Applications/") &&
            fileManager.fileExists(atPath: sibling.path) {
            return sibling
        }

        let destination = applicationSupportSettingsURL()
        let directory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: destination.path) {
                if let source = settingsURL(), source != destination {
                    try fileManager.copyItem(at: source, to: destination)
                } else {
                    let defaults = "{\n  \"opacity\": 0.30,\n  \"pollIntervalSeconds\": 300,\n  \"fillColor\": \"#C1E9F2\"\n}\n"
                    try defaults.write(to: destination, atomically: true, encoding: .utf8)
                }
            }
            return destination
        } catch {
            presentError(title: "Couldn’t open settings", message: error.localizedDescription)
            return nil
        }
    }

    private func applicationSupportSettingsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Usage Pie", isDirectory: true)
            .appendingPathComponent("usage-pie.settings.json")
    }

    private func executable(named name: String, commonPaths: [String]) -> URL? {
        let fileManager = FileManager.default
        let configured = ProcessInfo.processInfo.environment["\(name.uppercased())_BIN"]
        let pathCandidates = [configured].compactMap { $0 } + commonPaths
        return pathCandidates
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func shortReset(_ value: String) -> String {
        guard let comma = value.firstIndex(of: ",") else { return value }
        return "resets " + value[..<comma].lowercased()
    }

    private func updateStatusItem() {
        statusItem.button?.toolTip = usageToolTip(for: pieView.snapshot)
    }

    private func menuSummary(for snapshot: UsageSnapshot) -> String {
        "\(Int(snapshot.usedPercent.rounded()))% used · \(Int(snapshot.remainingPercent.rounded()))% remaining"
    }

    private func usageToolTip(for snapshot: UsageSnapshot) -> String {
        let checked = DateFormatter.localizedString(from: snapshot.checkedAt,
                                                    dateStyle: .none,
                                                    timeStyle: .short)
        return [
            "Codex: \(Int(snapshot.usedPercent.rounded()))% used · \(Int(snapshot.remainingPercent.rounded()))% remaining",
            "\(snapshot.windowDuration) · \(snapshot.resetText)",
            "Checked \(checked)",
        ].joined(separator: "\n")
    }

    private func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outerRadius: CGFloat = 7.8
            let innerRadius: CGFloat = 4.3
            let count = 7
            let segment = CGFloat.pi * 2 / CGFloat(count)
            let gap: CGFloat = 0.075

            context.setFillColor(NSColor.black.cgColor)
            for index in 0..<count {
                let start = -CGFloat.pi / 2 + CGFloat(index) * segment + gap
                let end = -CGFloat.pi / 2 + CGFloat(index + 1) * segment - gap
                let path = CGMutablePath()
                path.addArc(center: center, radius: outerRadius,
                            startAngle: start, endAngle: end, clockwise: false)
                path.addArc(center: center, radius: innerRadius,
                            startAngle: end, endAngle: start, clockwise: true)
                path.closeSubpath()
                context.addPath(path)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func presentError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: "windowOrigin")
    }

    @objc private func quit() {
        pollTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
