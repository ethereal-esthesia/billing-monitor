// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Security
import ServiceManagement

private enum UsageSource: String, CaseIterable {
    case codex
    case infra
    case deepseek
    case devin

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .infra: return "Infra"
        case .deepseek: return "DeepSeek"
        case .devin: return "Devin"
        }
    }

    var scriptName: String {
        switch self {
        case .codex: return "codex-usage.mjs"
        case .infra: return "infra-usage.mjs"
        case .deepseek: return "deepseek-usage.mjs"
        case .devin: return "devin-usage.mjs"
        }
    }

    var settingsFileName: String {
        switch self {
        case .codex: return "usage-pie.settings.json"
        case .infra: return "infra.settings.json"
        case .deepseek: return "deepseek.settings.json"
        case .devin: return "devin.settings.json"
        }
    }

    var settingsEnvironmentName: String {
        switch self {
        case .codex: return "USAGE_PIE_SETTINGS"
        case .infra: return "INFRA_USAGE_SETTINGS"
        case .deepseek: return "DEEPSEEK_USAGE_SETTINGS"
        case .devin: return "DEVIN_USAGE_SETTINGS"
        }
    }

    var scriptEnvironmentName: String {
        switch self {
        case .codex: return "CODEX_USAGE_SCRIPT"
        case .infra: return "INFRA_USAGE_SCRIPT"
        case .deepseek: return "DEEPSEEK_USAGE_SCRIPT"
        case .devin: return "DEVIN_USAGE_SCRIPT"
        }
    }

    var billingPageName: String {
        switch self {
        case .codex: return "Codex Billing"
        case .infra: return "Infra Billing"
        case .deepseek: return "DeepSeek Top Up"
        case .devin: return "Devin Billing"
        }
    }

    var billingURL: URL {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/#settings/Subscription")!
        case .infra: return URL(string: "https://deepinfra.com/dash/billing")!
        case .deepseek: return URL(string: "https://platform.deepseek.com/top_up")!
        case .devin: return URL(string: "https://devin.ai/settings/billing")!
        }
    }
}

private struct UsageSnapshot {
    struct InnerWindow {
        let usedPercent: Double
        let segmentCount: Int
        let elapsedWindowFraction: Double
        let duration: String
        let resetText: String
        let resetAt: Date?
    }

    let sourceName: String
    let usedPercent: Double
    let remainingPercent: Double
    let dayCount: Int
    let elapsedWindowFraction: Double
    let windowDuration: String
    let centerCaption: String
    let resetAvailabilityText: String?
    let resetText: String
    let resetAt: Date?
    let innerWindow: InnerWindow?
    let checkedAt: Date
}

private struct WidgetSettings {
    static let minimumPollInterval: TimeInterval = 60

    var opacity: CGFloat = 0.30
    var pollIntervalSeconds: TimeInterval = 300
    var fillColor = NSColor(srgbRed: 193 / 255, green: 233 / 255, blue: 242 / 255, alpha: 1)
    var topUpBalance: Double? = nil
    var billingDay: Int? = nil
}

private final class PieView: NSView {
    var snapshot = UsageSnapshot(sourceName: "Codex", usedPercent: 0, remainingPercent: 100,
                                 dayCount: 7,
                                 elapsedWindowFraction: 0,
                                 windowDuration: "7 days", centerCaption: "7 day window",
                                 resetAvailabilityText: nil,
                                 resetText: "Loading…",
                                 resetAt: nil,
                                 innerWindow: nil,
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
        let originalInnerRadius = outerRadius * 0.59
        let middleRadius = (outerRadius + originalInnerRadius) / 2
        let divider: CGFloat = snapshot.innerWindow == nil ? 0 : 1.5
        let outerRingInnerRadius = snapshot.innerWindow == nil
            ? originalInnerRadius
            : middleRadius + divider
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)
        drawRing(context: context, center: center, innerRadius: outerRingInnerRadius,
                 outerRadius: outerRadius, count: snapshot.dayCount,
                 usedPercent: snapshot.usedPercent,
                 elapsedWindowFraction: snapshot.elapsedWindowFraction,
                 color: fillColor)
        context.restoreGState()

        drawCurrentTimeMarker(context: context, center: center,
                              innerRadius: outerRingInnerRadius,
                              outerRadius: outerRadius,
                              elapsedWindowFraction: snapshot.elapsedWindowFraction)

        let centerRadius = originalInnerRadius
        if let innerWindow = snapshot.innerWindow {
            let innerOuterRadius = middleRadius - divider
            let innerColor = fillColor.blended(withFraction: 0.18, of: .black) ?? fillColor
            context.saveGState()
            drawRing(context: context, center: center, innerRadius: originalInnerRadius,
                     outerRadius: innerOuterRadius, count: innerWindow.segmentCount,
                     usedPercent: innerWindow.usedPercent,
                     elapsedWindowFraction: innerWindow.elapsedWindowFraction,
                     color: innerColor)
            context.restoreGState()

            drawCurrentTimeMarker(context: context, center: center,
                                  innerRadius: originalInnerRadius,
                                  outerRadius: innerOuterRadius,
                                  elapsedWindowFraction: innerWindow.elapsedWindowFraction)
        }

        drawCenter(center: center, radius: centerRadius)
    }

    private func drawCurrentTimeMarker(context: CGContext, center: CGPoint,
                                       innerRadius: CGFloat, outerRadius: CGFloat,
                                       elapsedWindowFraction: Double) {
        let fraction = CGFloat(min(1, max(0, elapsedWindowFraction)))
        let angle = -CGFloat.pi / 2 + fraction * CGFloat.pi * 2
        let inset: CGFloat = 1
        let start = CGPoint(x: center.x + cos(angle) * (innerRadius + inset),
                            y: center.y + sin(angle) * (innerRadius + inset))
        let end = CGPoint(x: center.x + cos(angle) * (outerRadius - inset),
                          y: center.y + sin(angle) * (outerRadius - inset))

        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(5)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        context.setStrokeColor(NSColor(calibratedWhite: 0.16, alpha: 0.95).cgColor)
        context.setLineWidth(2.25)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private func drawRing(context: CGContext, center: CGPoint, innerRadius: CGFloat,
                          outerRadius: CGFloat, count rawCount: Int, usedPercent: Double,
                          elapsedWindowFraction: Double, color: NSColor) {
        let count = max(1, rawCount)
        let fullTurn = CGFloat.pi * 2
        let segmentAngle = fullTurn / CGFloat(count)
        let gap: CGFloat = count == 1 ? 0 : min(0.035, segmentAngle * 0.10)
        let startAt = -CGFloat.pi / 2
        let sectionColor = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 0.82)
        let elapsedSectionColor = sectionColor.blended(withFraction: 0.35, of: .white) ?? sectionColor
        let elapsedFillColor = color.blended(withFraction: 0.22, of: .white) ?? color

        for index in 0..<count {
            let segmentStart = startAt + CGFloat(index) * segmentAngle + gap
            let segmentEnd = startAt + CGFloat(index + 1) * segmentAngle - gap
            context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                     outerRadius: outerRadius, start: segmentStart, end: segmentEnd))
            context.setFillColor(sectionColor.cgColor)
            context.fillPath()

            let elapsedSegments = CGFloat(elapsedWindowFraction) * CGFloat(count)
            let elapsedFraction = min(1, max(0, elapsedSegments - CGFloat(index)))
            if elapsedFraction > 0 {
                let elapsedEnd = segmentStart + (segmentEnd - segmentStart) * elapsedFraction
                context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                         outerRadius: outerRadius, start: segmentStart, end: elapsedEnd))
                context.setFillColor(elapsedSectionColor.cgColor)
                context.fillPath()
            }

            let filledSegments = CGFloat(usedPercent / 100) * CGFloat(count)
            let fraction = min(1, max(0, filledSegments - CGFloat(index)))
            if fraction > 0 {
                let fillEnd = segmentStart + (segmentEnd - segmentStart) * fraction
                context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                         outerRadius: outerRadius, start: segmentStart, end: fillEnd))
                context.setFillColor(color.cgColor)
                context.fillPath()

                let elapsedFillFraction = min(fraction, elapsedFraction)
                if elapsedFillFraction > 0 {
                    let elapsedFillEnd = segmentStart + (segmentEnd - segmentStart) * elapsedFillFraction
                    context.addPath(ringPath(center: center, innerRadius: innerRadius,
                                             outerRadius: outerRadius, start: segmentStart, end: elapsedFillEnd))
                    context.setFillColor(elapsedFillColor.cgColor)
                    context.fillPath()
                }
            }
        }
    }

    private func ringPath(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
                          start: CGFloat, end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func drawCenter(center: CGPoint, radius: CGFloat) {
        let centerRect = CGRect(x: center.x - radius + 3, y: center.y - radius + 3,
                                width: (radius - 3) * 2, height: (radius - 3) * 2)
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 0.90).setFill()
        NSBezierPath(ovalIn: centerRect).fill()

        if let innerWindow = snapshot.innerWindow {
            let percentages = "\(Int(snapshot.usedPercent.rounded()))% · \(Int(innerWindow.usedPercent.rounded()))%"
            drawText(percentages, size: 18, weight: .bold,
                     color: NSColor(calibratedWhite: 0.20, alpha: 1), y: center.y + 18)
            drawText("7d outer · 5h inner", size: 9, weight: .semibold,
                     color: NSColor(calibratedWhite: 0.34, alpha: 1), y: center.y)
            if let resetAvailabilityText = snapshot.resetAvailabilityText {
                drawText(resetAvailabilityText, size: 9, weight: .semibold,
                         color: NSColor(calibratedWhite: 0.34, alpha: 1), y: center.y - 18)
            }
        } else {
            let percent = "\(Int(snapshot.usedPercent.rounded()))%"
            drawText(percent, size: 26, weight: .bold,
                     color: NSColor(calibratedWhite: 0.20, alpha: 1), y: center.y + 11)
            drawText(snapshot.centerCaption, size: 10, weight: .semibold,
                     color: NSColor(calibratedWhite: 0.34, alpha: 1), y: center.y - 13)
        }
    }

    private func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight,
                          color: NSColor, y: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let width = bounds.width - 32
        let measured = attributed.boundingRect(with: NSSize(width: width, height: 80),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading])
        attributed.draw(with: NSRect(x: 16, y: y - measured.height / 2,
                                     width: width, height: measured.height + 2),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var contextMenu: NSMenu!
    private var settingsPanel: NSPanel?
    private var opacityField: NSTextField!
    private var pollIntervalField: NSTextField!
    private var fillColorField: NSTextField!
    private var fillColorWell: NSColorWell!
    private var topUpBalanceLabel: NSTextField!
    private var topUpBalanceField: NSTextField!
    private let pieView = PieView(frame: NSRect(x: 0, y: 0, width: 210, height: 210))
    private var settings = WidgetSettings()
    private var currentSource = UsageSource(rawValue: UserDefaults.standard.string(forKey: "usageSource") ?? "") ?? .codex
    private var pollTimer: Timer?
    private var resetRefreshTimer: Timer?
    private var lastRefreshAt: Date?

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
            button.addTrackingArea(NSTrackingArea(rect: button.bounds,
                                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: self,
                                                  userInfo: nil))
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
        let innerReset = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        innerReset.tag = 102
        innerReset.isEnabled = false
        innerReset.isHidden = true
        menu.addItem(innerReset)
        menu.addItem(.separator())
        let sourceItem = NSMenuItem(title: "Source", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu(title: "Source")
        for (index, source) in UsageSource.allCases.enumerated() {
            let item = NSMenuItem(title: source.displayName,
                                  action: #selector(selectUsageSource(_:)), keyEquivalent: "")
            item.tag = 200 + index
            item.representedObject = source.rawValue
            item.target = self
            sourceMenu.addItem(item)
        }
        menu.setSubmenu(sourceMenu, for: sourceItem)
        menu.addItem(sourceItem)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Billing…", action: #selector(openBillingPage), keyEquivalent: "")
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
        if menu === statusMenu {
            refreshUsageIfStale()
        }
        if let summary = menu.item(withTag: 100) {
            summary.title = menuSummary(for: pieView.snapshot)
        }
        if let reset = menu.item(withTag: 101) {
            reset.title = pieView.snapshot.innerWindow == nil
                ? pieView.snapshot.resetText
                : "7-day: \(pieView.snapshot.resetText)"
        }
        if let innerReset = menu.item(withTag: 102) {
            innerReset.isHidden = pieView.snapshot.innerWindow == nil
            innerReset.title = pieView.snapshot.innerWindow.map { "5-hour: \($0.resetText)" } ?? ""
        }
        if let sourceMenu = menu.items.first(where: { $0.submenu?.title == "Source" })?.submenu {
            for item in sourceMenu.items {
                item.state = item.representedObject as? String == currentSource.rawValue ? .on : .off
            }
        }
        if let visibilityItem = menu.items.first(where: { $0.action == #selector(toggleWidget) }) {
            visibilityItem.title = panel.isVisible ? "Hide Widget" : "Show Widget"
        }
        if let billingItem = menu.items.first(where: { $0.action == #selector(openBillingPage) }) {
            billingItem.title = "Open \(currentSource.billingPageName)…"
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

    @objc private func selectUsageSource(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let source = UsageSource(rawValue: rawValue), source != currentSource else { return }
        currentSource = source
        UserDefaults.standard.set(source.rawValue, forKey: "usageSource")
        lastRefreshAt = nil
        settings = readSettings()
        panel.alphaValue = settings.opacity
        pieView.fillColor = settings.fillColor
        settingsPanel?.orderOut(nil)
        refreshUsage()
        schedulePolling()
    }

    @objc private func openSettings() {
        if settingsPanel == nil {
            settingsPanel = makeSettingsPanel()
        }
        populateSettingsFields()
        settingsPanel?.title = "\(currentSource.displayName) Settings"
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel?.center()
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    @objc private func openBillingPage() {
        NSWorkspace.shared.open(currentSource.billingURL)
    }

    private func makeSettingsPanel() -> NSPanel {
        let editor = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        editor.title = "Usage Pie Settings"
        editor.isReleasedWhenClosed = false
        editor.level = .floating

        let content = editor.contentView!
        let title = NSTextField(labelWithString: "Appearance & Updates")
        title.frame = NSRect(x: 24, y: 244, width: 370, height: 24)
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        content.addSubview(title)

        let detail = NSTextField(labelWithString: "Changes apply immediately when you save.")
        detail.frame = NSRect(x: 24, y: 222, width: 370, height: 18)
        detail.textColor = .secondaryLabelColor
        content.addSubview(detail)

        addSettingsLabel("Opacity", y: 180, to: content)
        opacityField = NSTextField(frame: NSRect(x: 170, y: 176, width: 150, height: 26))
        opacityField.placeholderString = "30"
        content.addSubview(opacityField)
        let percentSuffix = NSTextField(labelWithString: "%")
        percentSuffix.frame = NSRect(x: 328, y: 180, width: 44, height: 20)
        percentSuffix.textColor = .secondaryLabelColor
        content.addSubview(percentSuffix)

        addSettingsLabel("Polling interval", y: 140, to: content)
        pollIntervalField = NSTextField(frame: NSRect(x: 170, y: 136, width: 150, height: 26))
        pollIntervalField.placeholderString = "300"
        content.addSubview(pollIntervalField)
        let secondsSuffix = NSTextField(labelWithString: "seconds")
        secondsSuffix.frame = NSRect(x: 328, y: 140, width: 68, height: 20)
        secondsSuffix.textColor = .secondaryLabelColor
        content.addSubview(secondsSuffix)

        addSettingsLabel("Fill color", y: 100, to: content)
        fillColorField = NSTextField(frame: NSRect(x: 170, y: 96, width: 150, height: 26))
        fillColorField.placeholderString = "#C1E9F2"
        content.addSubview(fillColorField)
        fillColorWell = NSColorWell(frame: NSRect(x: 328, y: 95, width: 48, height: 28))
        fillColorWell.target = self
        fillColorWell.action = #selector(colorWellChanged)
        content.addSubview(fillColorWell)

        topUpBalanceLabel = NSTextField(labelWithString: "Initial top-up")
        topUpBalanceLabel.frame = NSRect(x: 24, y: 60, width: 135, height: 20)
        topUpBalanceLabel.alignment = .right
        content.addSubview(topUpBalanceLabel)
        topUpBalanceField = NSTextField(frame: NSRect(x: 170, y: 56, width: 150, height: 26))
        topUpBalanceField.placeholderString = "2.00"
        content.addSubview(topUpBalanceField)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancel.frame = NSRect(x: 238, y: 14, width: 78, height: 30)
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.frame = NSRect(x: 322, y: 14, width: 78, height: 30)
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        content.addSubview(save)

        return editor
    }

    private func addSettingsLabel(_ text: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 24, y: y, width: 135, height: 20)
        label.alignment = .right
        view.addSubview(label)
    }

    private func populateSettingsFields() {
        opacityField.stringValue = String(Int((settings.opacity * 100).rounded()))
        pollIntervalField.stringValue = String(Int(settings.pollIntervalSeconds.rounded()))
        fillColorWell.color = settings.fillColor
        fillColorField.stringValue = hexString(from: settings.fillColor)
        topUpBalanceField.stringValue = settings.topUpBalance.map { String(format: "%.2f", $0) } ?? ""
        if currentSource == .codex {
            topUpBalanceLabel.stringValue = "Billing day (1–31)"
            topUpBalanceField.placeholderString = "Recommended"
            topUpBalanceField.stringValue = settings.billingDay.map(String.init) ?? ""
        } else {
            topUpBalanceLabel.stringValue = "Initial top-up"
            topUpBalanceField.placeholderString = "2.00"
        }
        let showTopUpBalance = currentSource == .deepseek || currentSource == .codex
        topUpBalanceLabel.isHidden = !showTopUpBalance
        topUpBalanceField.isHidden = !showTopUpBalance
    }

    @objc private func colorWellChanged() {
        fillColorField.stringValue = hexString(from: fillColorWell.color)
    }

    @objc private func cancelSettings() {
        settingsPanel?.orderOut(nil)
    }

    @objc private func saveSettings() {
        guard let opacityPercent = Double(opacityField.stringValue),
              (5...100).contains(opacityPercent) else {
            presentError(title: "Invalid opacity", message: "Enter a value from 5 through 100 percent.")
            return
        }
        guard let pollSeconds = Double(pollIntervalField.stringValue),
              pollSeconds >= WidgetSettings.minimumPollInterval else {
            presentError(title: "Invalid polling interval", message: "Enter 60 seconds or longer.")
            return
        }
        guard let fillColor = color(fromHex: fillColorField.stringValue) else {
            presentError(title: "Invalid fill color", message: "Use #RRGGBB or #RRGGBBAA format.")
            return
        }
        var topUpBalance: Double?
        if currentSource == .deepseek {
            guard let value = Double(topUpBalanceField.stringValue), value > 0 else {
                presentError(title: "Invalid initial top-up", message: "Enter the starting DeepSeek balance.")
                return
            }
            topUpBalance = value
        }
        var billingDay: Int?
        if currentSource == .codex {
            let value = topUpBalanceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                guard let day = Int(value), (1...31).contains(day) else {
                    presentError(title: "Invalid billing day", message: "Enter a day from 1 through 31, or leave blank.")
                    return
                }
                billingDay = day
            }
        }
        guard let destination = editableSettingsURL() else { return }

        let opacity = opacityPercent / 100
        var payload: [String: Any] = [
            "opacity": NSDecimalNumber(string: String(format: "%.2f", opacity)),
            "pollIntervalSeconds": pollSeconds,
            "fillColor": hexString(from: fillColor),
        ]
        if let billingDay { payload["billingDay"] = billingDay }
        if let topUpBalance {
            payload["topUpBalance"] = topUpBalance
        }

        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            var data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys])
            data.append(0x0A)
            try data.write(to: destination, options: .atomic)
            settings = WidgetSettings(opacity: opacity,
                                      pollIntervalSeconds: pollSeconds,
                                      fillColor: fillColor,
                                      topUpBalance: topUpBalance, billingDay: billingDay)
            panel.alphaValue = settings.opacity
            pieView.fillColor = settings.fillColor
            schedulePolling()
            settingsPanel?.orderOut(nil)
            refreshUsage()
        } catch {
            presentError(title: "Couldn’t save settings", message: error.localizedDescription)
        }
    }

    @objc private func toggleWidget() {
        if panel.isVisible {
            panel.orderOut(nil)
            stopPolling()
        } else {
            panel.orderFrontRegardless()
            refreshUsageIfStale()
            schedulePolling()
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
        stopPolling()
        guard panel.isVisible else { return }

        pollTimer = Timer.scheduledTimer(timeInterval: settings.pollIntervalSeconds,
                                         target: self,
                                         selector: #selector(refreshUsageIfStale),
                                         userInfo: nil,
                                         repeats: true)
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func mouseEntered(with event: NSEvent) {
        refreshUsageIfStale()
    }

    @objc private func refreshUsageIfStale() {
        let now = Date()
        let resetIsDue = [pieView.snapshot.resetAt, pieView.snapshot.innerWindow?.resetAt]
            .compactMap { $0 }
            .contains { $0 <= now }
        guard resetIsDue || lastRefreshAt.map({ now.timeIntervalSince($0) >= settings.pollIntervalSeconds }) ?? true else {
            return
        }
        refreshUsage()
    }

    @objc private func refreshUsage() {
        lastRefreshAt = Date()
        let previous = pieView.snapshot
        pieView.snapshot = UsageSnapshot(sourceName: previous.sourceName,
                                         usedPercent: previous.usedPercent,
                                         remainingPercent: previous.remainingPercent,
                                         dayCount: previous.dayCount,
                                         elapsedWindowFraction: previous.elapsedWindowFraction,
                                         windowDuration: previous.windowDuration,
                                         centerCaption: previous.centerCaption,
                                         resetAvailabilityText: previous.resetAvailabilityText,
                                         resetText: "Refreshing…",
                                         resetAt: previous.resetAt,
                                         innerWindow: previous.innerWindow,
                                         checkedAt: previous.checkedAt)
        let snapshot = readUsage()
        let fallbackDays: Int
        switch currentSource {
        case .codex: fallbackDays = 7
        case .infra: fallbackDays = 30
        case .deepseek: fallbackDays = 1
        case .devin: fallbackDays = 30
        }
        pieView.snapshot = snapshot ?? UsageSnapshot(sourceName: currentSource.displayName,
                                                     usedPercent: 0, remainingPercent: 100,
                                                     dayCount: fallbackDays, elapsedWindowFraction: 0,
                                                     windowDuration: "\(fallbackDays) days",
                                                     centerCaption: currentSource == .deepseek ? "balance\nunavailable" : "\(fallbackDays) day window",
                                                     resetAvailabilityText: nil,
                                                     resetText: "Usage unavailable",
                                                     resetAt: nil,
                                                     innerWindow: nil,
                                                     checkedAt: Date())
        scheduleResetRefresh(for: pieView.snapshot)
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
        if currentSource == .codex, environment["CODEX_BIN"] == nil {
            let bundledCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
            if FileManager.default.isExecutableFile(atPath: bundledCodex) {
                environment["CODEX_BIN"] = bundledCodex
            }
        }
        if currentSource == .infra, environment["DEEPINFRA_TOKEN"] == nil,
           let token = keychainPassword(service: "deepinfra-api-key") {
            environment["DEEPINFRA_TOKEN"] = token
        }
        if currentSource == .deepseek, environment["DEEPSEEK_API_KEY"] == nil,
           let token = keychainPassword(service: "deepseek-api-key") {
            environment["DEEPSEEK_API_KEY"] = token
        }
        if currentSource == .devin, environment["DEVIN_SERVICE_USER_TOKEN"] == nil, environment["DEVIN_API_KEY"] == nil,
           let token = keychainPassword(service: "devin-service-user-token") ?? keychainPassword(service: "devin-api-key") {
            environment["DEVIN_SERVICE_USER_TOKEN"] = token
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
              let json = try? JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any] else {
            return nil
        }

        if currentSource == .infra {
            return infraSnapshot(from: json)
        }
        if currentSource == .deepseek {
            return deepseekSnapshot(from: json)
        }
        if currentSource == .devin {
            return devinSnapshot(from: json)
        }

        guard
              let limits = json["limits"] as? [[String: Any]],
              let first = limits.first else { return nil }

        let windows = ["primary", "secondary"]
            .compactMap { first[$0] as? [String: Any] }
            .sorted {
                ($0["windowMinutes"] as? Double ?? 0) < ($1["windowMinutes"] as? Double ?? 0)
            }
        guard let selectedWindow = windows.last else { return nil }

        let used = selectedWindow["usedPercent"] as? Double ?? 0
        let remaining = selectedWindow["remainingPercent"] as? Double ?? max(0, 100 - used)
        let minutes = selectedWindow["windowMinutes"] as? Double ?? 10_080
        let days = max(1, Int((minutes / 1_440).rounded()))
        let segmentCount: Int
        if minutes < 1_440 {
            segmentCount = max(1, min(12, Int((minutes / 60).rounded())))
        } else {
            segmentCount = days
        }
        let duration = selectedWindow["windowDuration"] as? String ?? "\(days) days"
        let centerCaption: String
        if minutes < 1_440, minutes.truncatingRemainder(dividingBy: 60) == 0 {
            centerCaption = "\(Int(minutes / 60)) hour window"
        } else if minutes < 1_440 {
            centerCaption = "\(Int(minutes.rounded())) minute window"
        } else {
            centerCaption = "\(days) day weekly limit"
        }
        let checkedAt = (json["checkedAt"] as? String).flatMap(parseISO8601) ?? Date()
        let reportedResetAt = (selectedWindow["resetsAt"] as? String).flatMap(parseISO8601)
        let resetAt = billingCappedReset(reportedResetAt, checkedAt: checkedAt)
        let windowSeconds = max(1, minutes * 60)
        let elapsedSeconds = resetAt.map { windowSeconds - max(0, $0.timeIntervalSince(checkedAt)) } ?? 0
        let elapsedFraction = min(1, max(0, elapsedSeconds / windowSeconds))
        let resetText = resetAt.map {
            formattedReset($0, relativeTo: checkedAt, windowSeconds: windowSeconds, reportedResetAt: reportedResetAt)
        }
            ?? (selectedWindow["resetsAtLocal"] as? String).map(shortReset)
            ?? "Reset unknown"
        let availableResetCount = max(0, json["availableResetCount"] as? Int ?? 0)
        let resetAvailabilityText = availableResetCount == 1
            ? "1 reset available"
            : "\(availableResetCount) resets available"
        let innerWindow: UsageSnapshot.InnerWindow?
        if windows.count > 1, let smallerWindow = windows.first {
            let innerMinutes = max(1, smallerWindow["windowMinutes"] as? Double ?? 300)
            let innerWindowSeconds = innerMinutes * 60
            let innerReportedResetAt = (smallerWindow["resetsAt"] as? String).flatMap(parseISO8601)
            let innerResetAt = billingCappedReset(innerReportedResetAt, checkedAt: checkedAt)
            let innerElapsedSeconds = innerResetAt.map {
                innerWindowSeconds - max(0, $0.timeIntervalSince(checkedAt))
            } ?? 0
            let innerResetText = innerResetAt.map {
                formattedReset($0, relativeTo: checkedAt, windowSeconds: innerWindowSeconds, reportedResetAt: innerReportedResetAt)
            }
                ?? (smallerWindow["resetsAtLocal"] as? String).map(shortReset)
                ?? "Reset unknown"
            innerWindow = UsageSnapshot.InnerWindow(
                usedPercent: smallerWindow["usedPercent"] as? Double ?? 0,
                segmentCount: max(1, min(12, Int((innerMinutes / 60).rounded()))),
                elapsedWindowFraction: min(1, max(0, innerElapsedSeconds / innerWindowSeconds)),
                duration: smallerWindow["windowDuration"] as? String ?? "\(Int(innerMinutes)) minutes",
                resetText: innerResetText,
                resetAt: innerResetAt
            )
        } else {
            innerWindow = nil
        }
        return UsageSnapshot(sourceName: currentSource.displayName,
                             usedPercent: used, remainingPercent: remaining, dayCount: segmentCount,
                             elapsedWindowFraction: elapsedFraction,
                             windowDuration: duration, centerCaption: centerCaption,
                             resetAvailabilityText: resetAvailabilityText,
                             resetText: resetText,
                             resetAt: resetAt,
                             innerWindow: innerWindow,
                             checkedAt: checkedAt)
    }

    private func infraSnapshot(from json: [String: Any]) -> UsageSnapshot? {
        guard let spent = json["spent"] as? Double,
              let limit = json["limit"] as? Double, limit > 0 else { return nil }
        let remaining = max(0, (json["remaining"] as? Double) ?? limit - spent)
        let usedPercent = min(100, max(0, spent / limit * 100))
        let remainingPercent = min(100, max(0, remaining / limit * 100))
        let checkedAt = (json["checkedAt"] as? String).flatMap(parseISO8601) ?? Date()
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.currencyCode = "USD"
        currency.maximumFractionDigits = 2
        let spentText = currency.string(from: NSNumber(value: spent)) ?? String(format: "$%.2f", spent)
        let remainingText = currency.string(from: NSNumber(value: remaining)) ?? String(format: "$%.2f", remaining)

        return UsageSnapshot(sourceName: currentSource.displayName,
                             usedPercent: usedPercent, remainingPercent: remainingPercent,
                             dayCount: 30, elapsedWindowFraction: 29.0 / 30.0,
                             windowDuration: "30 rolling days",
                             centerCaption: "30 day window",
                             resetAvailabilityText: nil,
                             resetText: "\(spentText) spent · \(remainingText) remaining",
                             resetAt: nil,
                             innerWindow: nil,
                             checkedAt: checkedAt)
    }

    private func deepseekSnapshot(from json: [String: Any]) -> UsageSnapshot? {
        guard let balance = json["balance"] as? Double,
              let topUpBalance = settings.topUpBalance, topUpBalance > 0 else { return nil }
        let spent = min(topUpBalance, max(0, topUpBalance - balance))
        let remaining = min(topUpBalance, max(0, balance))
        let usedPercent = min(100, max(0, spent / topUpBalance * 100))
        let remainingPercent = min(100, max(0, remaining / topUpBalance * 100))
        let checkedAt = (json["checkedAt"] as? String).flatMap(parseISO8601) ?? Date()
        let currencyCode = json["currency"] as? String ?? "USD"
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.currencyCode = currencyCode
        currency.maximumFractionDigits = 2
        let spentText = currency.string(from: NSNumber(value: spent)) ?? String(format: "%.2f %@", spent, currencyCode)
        let remainingText = currency.string(from: NSNumber(value: balance)) ?? String(format: "%.2f %@", balance, currencyCode)

        return UsageSnapshot(sourceName: currentSource.displayName,
                             usedPercent: usedPercent, remainingPercent: remainingPercent,
                             dayCount: 1, elapsedWindowFraction: 0,
                             windowDuration: "Prepaid balance",
                             centerCaption: "\(Int(remainingPercent.rounded()))% remaining",
                             resetAvailabilityText: nil,
                             resetText: "\(spentText) used · \(remainingText) remaining",
                             resetAt: nil,
                             innerWindow: nil,
                             checkedAt: checkedAt)
    }

    private func devinSnapshot(from json: [String: Any]) -> UsageSnapshot? {
        guard let totalAcus = json["totalAcus"] as? Double else { return nil }
        let checkedAt = (json["checkedAt"] as? String).flatMap(parseISO8601) ?? Date()
        let dayCount = 30

        let usedPercent = min(100, totalAcus)
        let remainingPercent = max(0, 100 - usedPercent)

        return UsageSnapshot(sourceName: currentSource.displayName,
                             usedPercent: usedPercent, remainingPercent: remainingPercent,
                             dayCount: dayCount, elapsedWindowFraction: 0,
                             windowDuration: "30 day period",
                             centerCaption: "\(Int(totalAcus.rounded())) ACUs used",
                             resetAvailabilityText: nil,
                             resetText: "\(Int(totalAcus.rounded())) ACUs · 30 days",
                             resetAt: nil,
                             innerWindow: nil,
                             checkedAt: checkedAt)
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func usageScriptURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment[currentSource.scriptEnvironmentName]
                .map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL?.appendingPathComponent(currentSource.scriptName),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(currentSource.scriptName),
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
        let pollSeconds = max(WidgetSettings.minimumPollInterval,
                              json["pollIntervalSeconds"] as? Double ?? 300)
        let fillColor = color(fromHex: json["fillColor"] as? String) ?? WidgetSettings().fillColor
        let topUpBalance = (json["topUpBalance"] as? Double) ?? (json["amountPaid"] as? Double)
        return WidgetSettings(opacity: opacity, pollIntervalSeconds: pollSeconds,
                              fillColor: fillColor, topUpBalance: topUpBalance,
                              billingDay: (json["billingDay"] as? Int).flatMap { (1...31).contains($0) ? $0 : nil })
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

    private func hexString(from color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "#C1E9F2" }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        let alpha = Int((srgb.alphaComponent * 255).rounded())
        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func settingsURL() -> URL? {
        let fileManager = FileManager.default
        let fileName = currentSource.settingsFileName
        let candidates = [
            ProcessInfo.processInfo.environment[currentSource.settingsEnvironmentName].map { URL(fileURLWithPath: $0) },
            applicationSupportSettingsURL(),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(fileName),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(fileName),
            Bundle.main.resourceURL?.appendingPathComponent(fileName),
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func editableSettingsURL() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment[currentSource.settingsEnvironmentName] {
            return URL(fileURLWithPath: override)
        }

        let sibling = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(currentSource.settingsFileName)
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
                    let defaultFill: String
                    switch currentSource {
                    case .codex: defaultFill = "#C1E9F2"
                    case .infra: defaultFill = "#B9E6C8"
                    case .deepseek: defaultFill = "#9FC5FF"
                    case .devin: defaultFill = "#C1E9F2"
                    }
                    let topUpBalance = currentSource == .deepseek ? ",\n  \"topUpBalance\": 0.00" : ""
                    let defaults = "{\n  \"opacity\": 0.30,\n  \"pollIntervalSeconds\": 300,\n  \"fillColor\": \"\(defaultFill)\"\(topUpBalance)\n}\n"
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
            .appendingPathComponent(currentSource.settingsFileName)
    }

    private func executable(named name: String, commonPaths: [String]) -> URL? {
        let fileManager = FileManager.default
        let configured = ProcessInfo.processInfo.environment["\(name.uppercased())_BIN"]
        let pathCandidates = [configured].compactMap { $0 } + commonPaths
        return pathCandidates
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func keychainPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let password = String(data: data, encoding: .utf8), !password.isEmpty {
            return password
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortReset(_ value: String) -> String {
        guard let comma = value.firstIndex(of: ",") else { return value }
        return "resets " + value[..<comma].lowercased()
    }

    // Calendar arithmetic keeps midnight local across DST and clamps short months.
    private func billingCappedReset(_ reported: Date?, checkedAt: Date) -> Date? {
        guard let day = settings.billingDay, (1...31).contains(day) else { return reported }
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: checkedAt)?.start else { return reported }
        for offset in 0...1 {
            guard let start = calendar.date(byAdding: .month, value: offset, to: month),
                  let days = calendar.range(of: .day, in: .month, for: start),
                  let date = calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: start) else { continue }
            let midnight = calendar.startOfDay(for: date)
            if midnight > checkedAt { return reported.map { min($0, midnight) } ?? midnight }
        }
        return reported
    }

    private func formattedReset(_ resetAt: Date, relativeTo checkedAt: Date,
                                windowSeconds: TimeInterval, reportedResetAt: Date? = nil) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm:ss a z"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "MMM d, h:mm:ss a z"
        let startedAt = (reportedResetAt ?? resetAt).addingTimeInterval(-windowSeconds)
        let startText = Calendar.current.isDate(startedAt, inSameDayAs: checkedAt)
            ? timeFormatter.string(from: startedAt)
            : dateTimeFormatter.string(from: startedAt)
        let resetText = Calendar.current.isDate(resetAt, inSameDayAs: checkedAt)
            ? timeFormatter.string(from: resetAt)
            : dateTimeFormatter.string(from: resetAt)
        return "started \(startText) · resets \(resetText)"
    }

    private func scheduleResetRefresh(for snapshot: UsageSnapshot) {
        resetRefreshTimer?.invalidate()
        let now = Date()
        let resetDates = [snapshot.resetAt, snapshot.innerWindow?.resetAt]
            .compactMap { $0 }
            .filter { $0 > now }
        guard let resetAt = resetDates.min() else { return }
        resetRefreshTimer = Timer(fireAt: resetAt.addingTimeInterval(1), interval: 0, target: self,
                                  selector: #selector(refreshUsage), userInfo: nil, repeats: false)
        RunLoop.main.add(resetRefreshTimer!, forMode: .common)
    }

    private func updateStatusItem() {
        statusItem.button?.toolTip = usageToolTip(for: pieView.snapshot)
    }

    private func menuSummary(for snapshot: UsageSnapshot) -> String {
        if let innerWindow = snapshot.innerWindow {
            return "\(snapshot.sourceName): \(Int(snapshot.usedPercent.rounded()))% weekly · \(Int(innerWindow.usedPercent.rounded()))% 5-hour"
        }
        return "\(snapshot.sourceName): \(Int(snapshot.usedPercent.rounded()))% used · \(Int(snapshot.remainingPercent.rounded()))% remaining"
    }

    private func usageToolTip(for snapshot: UsageSnapshot) -> String {
        let checked = DateFormatter.localizedString(from: snapshot.checkedAt,
                                                    dateStyle: .none,
                                                    timeStyle: .short)
        var lines = [menuSummary(for: snapshot),
                     "\(snapshot.windowDuration) · \(snapshot.resetText)"]
        if let innerWindow = snapshot.innerWindow {
            lines.append("\(innerWindow.duration) · \(innerWindow.resetText)")
        }
        lines.append("Checked \(checked)")
        return lines.joined(separator: "\n")
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
