// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

private struct UsageSnapshot {
    let usedPercent: Double
    let dayCount: Int
    let resetText: String
}

private struct WidgetSettings {
    var opacity: CGFloat = 0.30
    var pollIntervalSeconds: TimeInterval = 300
}

private final class PieView: NSView {
    var snapshot = UsageSnapshot(usedPercent: 0, dayCount: 7, resetText: "Loading…") {
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
        let fillColor = NSColor(calibratedWhite: 0.72, alpha: 1)

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
        drawText(snapshot.resetText, size: 9, weight: .medium,
                 color: NSColor(calibratedWhite: 0.47, alpha: 1), y: center.y - 29)
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

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private let pieView = PieView(frame: NSRect(x: 0, y: 0, width: 210, height: 210))
    private var settings = WidgetSettings()
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = readSettings()
        createPanel()
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
        panel.delegate = self
        panel.contentView = pieView

        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "r")
        menu.addItem(withTitle: "Reload Settings", action: #selector(reloadSettings), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Usage Pie", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        pieView.menu = menu

        if let saved = UserDefaults.standard.array(forKey: "windowOrigin") as? [Double], saved.count == 2 {
            panel.setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
    }

    @objc private func reloadSettings() {
        settings = readSettings()
        panel.alphaValue = settings.opacity
        schedulePolling()
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
        pieView.snapshot = UsageSnapshot(usedPercent: pieView.snapshot.usedPercent,
                                         dayCount: pieView.snapshot.dayCount,
                                         resetText: "Refreshing…")
        let snapshot = readUsage()
        pieView.snapshot = snapshot ?? UsageSnapshot(usedPercent: 0, dayCount: 7,
                                                     resetText: "Usage unavailable")
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
        let minutes = primary["windowMinutes"] as? Double ?? 10_080
        let days = max(1, Int((minutes / 1_440).rounded()))
        let reset = primary["resetsAtLocal"] as? String ?? "Reset unknown"
        return UsageSnapshot(usedPercent: used, dayCount: days, resetText: shortReset(reset))
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
        return WidgetSettings(opacity: opacity, pollIntervalSeconds: pollSeconds)
    }

    private func settingsURL() -> URL? {
        let fileManager = FileManager.default
        let fileName = "usage-pie.settings.json"
        let candidates = [
            ProcessInfo.processInfo.environment["USAGE_PIE_SETTINGS"].map { URL(fileURLWithPath: $0) },
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(fileName),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(fileName),
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
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
