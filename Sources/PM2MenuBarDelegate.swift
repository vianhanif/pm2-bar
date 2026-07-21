import AppKit
import ServiceManagement

// MARK: - PM2Process Model

struct PM2Process: Identifiable {
    let id: String
    let name: String
    let pid: String
    let uptime: String
    let status: String  // online / errored / stopped / paused
    let cpu: String
    let mem: String

    var statusColor: NSColor {
        switch status {
        case "online":  return .systemGreen
        case "errored": return .systemRed
        case "stopped": return .systemOrange
        case "paused":  return .systemYellow
        default:        return .systemGray
        }
    }
}

// MARK: - PM2Model

final class PM2Model: NSObject {
    var processes: [PM2Process] = [] { didSet { onUpdate?() } }
    var errorMessage: String? { didSet { onUpdate?() } }
    var lastUpdated: Date? { didSet { onUpdate?() } }
    var hasErrors: Bool = false { didSet { onUpdate?() } }

    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private let pm2Path: String

    override init() {
        let candidates = [
            (FileManager.default.homeDirectoryForCurrentUser.path() + "/.asdf/shims/pm2"),
            "/usr/local/bin/pm2",
            "/opt/homebrew/bin/pm2",
            "/usr/bin/pm2",
        ]
        pm2Path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "pm2"
        super.init()

        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func fetch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "\(pm2Path) list --no-color 2>&1"]
        task.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            parse(output)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Failed: \(error.localizedDescription)"
                self?.onUpdate?()
            }
        }
    }

    private func parse(_ raw: String) {
        let lines = raw.split(separator: "\n").map(String.init)
        guard let headerIdx = lines.firstIndex(where: { $0.contains("id") && $0.contains("name") }) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "pm2 not found"
                self?.onUpdate?()
            }
            return
        }

        let bodyStart = headerIdx + 2
        guard bodyStart < lines.count else {
            DispatchQueue.main.async { [weak self] in
                self?.processes = []
                self?.lastUpdated = Date()
                self?.hasErrors = false
                self?.onUpdate?()
            }
            return
        }

        let bodyLines = lines[bodyStart...].prefix { line in
            !line.trimmingCharacters(in: .whitespaces).isEmpty
        }

        var parsed: [PM2Process] = []
        for line in bodyLines {
            if let proc = parseLine(String(line)) {
                parsed.append(proc)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.processes = parsed
            self?.lastUpdated = Date()
            self?.hasErrors = parsed.contains { $0.status == "errored" }
            self?.onUpdate?()
        }
    }

    private func parseLine(_ line: String) -> PM2Process? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let rawCols = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "│ "))
            .split(separator: "│")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard let statusIdx = rawCols.firstIndex(where: {
            ["online", "errored", "stopped", "paused"].contains($0.lowercased())
        }) else { return nil }

        let pidIdx = statusIdx - 3
        let uptimeIdx = statusIdx - 2
        let cpuIdx = statusIdx + 1
        let memIdx = statusIdx + 2

        return PM2Process(
            id: rawCols[0],
            name: rawCols[1],
            pid: pidIdx >= 0 && pidIdx < rawCols.count ? rawCols[pidIdx] : "?",
            uptime: uptimeIdx >= 0 && uptimeIdx < rawCols.count ? rawCols[uptimeIdx] : "?",
            status: rawCols[statusIdx].lowercased(),
            cpu: cpuIdx < rawCols.count ? rawCols[cpuIdx] : "?",
            mem: memIdx < rawCols.count ? rawCols[memIdx] : "?"
        )
    }
}

// MARK: - Menu Bar Delegate

final class PM2MenuBarDelegate: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var model: PM2Model!

    func start() {
        model = PM2Model()
        model.onUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.updateButtonTitle()
                self?.rebuildMenu()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateButtonTitle()

        LoginItemManager.refreshStatus()
    }

    func updateButtonTitle() {
        guard let button = statusItem.button else { return }
        let count = model.processes.count
        let imageName = model.hasErrors ? "exclamationmark.triangle.fill" : "terminal.fill"

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) {
            image.isTemplate = !model.hasErrors
            button.image = image
            if model.hasErrors {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
        }
        button.title = " \(count)"
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        rebuildMenu()
    }

    // NSMenuDelegate — rebuild before showing
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    public func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let textColor = NSColor.textColor
        let secondaryColor = NSColor.secondaryLabelColor
        let normalFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let statsFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        // Header
        let headerItem = NSMenuItem()
        headerItem.attributedTitle = NSAttributedString(string: "PM2 Daemon Monitor", attributes: [
            .font: boldFont,
            .foregroundColor: textColor
        ])
        headerItem.isEnabled = true
        headerItem.target = self
        headerItem.action = #selector(nullAction)
        menu.addItem(headerItem)

        // Error
        if let error = model.errorMessage {
            let errItem = NSMenuItem()
            errItem.attributedTitle = NSAttributedString(string: error, attributes: [
                .font: normalFont,
                .foregroundColor: textColor
            ])
            errItem.isEnabled = true
            errItem.target = self
            errItem.action = #selector(nullAction)
            menu.addItem(errItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Empty state
        if model.processes.isEmpty && model.errorMessage == nil {
            let emptyItem = NSMenuItem()
            emptyItem.attributedTitle = NSAttributedString(string: "No processes", attributes: [
                .font: normalFont,
                .foregroundColor: textColor
            ])
            emptyItem.isEnabled = true
            emptyItem.target = self
            emptyItem.action = #selector(nullAction)
            menu.addItem(emptyItem)
        }

        // Process rows
        for proc in model.processes {
            let item = NSMenuItem()
            item.isEnabled = true
            item.target = self
            item.action = #selector(nullAction)

            let attr = NSMutableAttributedString(string: proc.name, attributes: [
                .font: nameFont,
                .foregroundColor: textColor
            ])
            attr.append(NSAttributedString(string: "  "))
            attr.append(NSAttributedString(
                string: "\u{25CF}",
                attributes: [.foregroundColor: proc.statusColor, .font: NSFont.systemFont(ofSize: 13)]
            ))
            attr.append(NSAttributedString(
                string: "  [\(proc.cpu)% | \(proc.mem)]",
                attributes: [
                    .foregroundColor: secondaryColor,
                    .font: statsFont
                ]
            ))
            item.attributedTitle = attr
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Last updated
        if let last = model.lastUpdated {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            let tsItem = NSMenuItem()
            tsItem.attributedTitle = NSAttributedString(
                string: "Updated \(fmt.localizedString(for: last, relativeTo: Date()))",
                attributes: [.font: statsFont, .foregroundColor: secondaryColor]
            )
            tsItem.isEnabled = true
            tsItem.target = self
            tsItem.action = #selector(nullAction)
            menu.addItem(tsItem)
        }

        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.attributedTitle = NSAttributedString(string: "Refresh R", attributes: [
            .font: normalFont,
            .foregroundColor: textColor
        ])
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.attributedTitle = NSAttributedString(string: "Launch at Login", attributes: [
            .font: normalFont,
            .foregroundColor: textColor
        ])
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        if LoginItemManager.requiresApproval {
            let noteItem = NSMenuItem()
            noteItem.attributedTitle = NSAttributedString(
                string: "  Requires System Settings approval",
                attributes: [.foregroundColor: NSColor.systemYellow, .font: NSFont.systemFont(ofSize: 11)]
            )
            noteItem.isEnabled = true
            noteItem.target = self
            noteItem.action = #selector(nullAction)
            menu.addItem(noteItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        quitItem.attributedTitle = NSAttributedString(string: "Quit ⌘Q", attributes: [
            .font: normalFont,
            .foregroundColor: textColor
        ])
        menu.addItem(quitItem)
    }

    @objc private func refreshClicked() { model.fetch() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        LoginItemManager.isEnabled.toggle()
        sender.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func quitClicked() { NSApplication.shared.terminate(nil) }
    @objc private func nullAction() {}
}
