import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let helpURL = URL(string: "https://littlebirdelectronics.com.au/help/big-red-button-setup")!

    private let store = ConfigStore()
    private lazy var monitor = ButtonMonitor(device: store.config.resolvedDevice, suppressKey: store.config.suppressesKey)
    private let runner = ActionRunner()
    private var statusItem: NSStatusItem!
    private var pressedConfig: ButtonConfig?
    private var isPressed = false
    private var permissionTimer: Timer?
    private var recorder: ShortcutRecorder?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        monitor.onPress = { [weak self] in self?.buttonDown() }
        monitor.onRelease = { [weak self] in self?.buttonUp() }
        monitor.onConnectionChange = { [weak self] _ in self?.refreshIcon() }
        runner.onNeedsAccessibility = { [weak self] in self?.askForAccessibility() }

        firstRunSetup()
        startMonitoring()
        handleTerminationSignals()
        refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.restoreKey()
    }

    // MARK: - Button

    private func buttonDown() {
        store.reloadIfChanged()
        let config = store.config
        pressedConfig = config
        isPressed = true
        refreshIcon()
        Log.write("Pressed: \(config.summary)")
        runner.pressed(config)
    }

    private func buttonUp() {
        isPressed = false
        refreshIcon()
        runner.released(pressedConfig ?? store.config)
        pressedConfig = nil
    }

    private func startMonitoring() {
        if !ButtonMonitor.hasInputMonitoringAccess {
            ButtonMonitor.requestInputMonitoringAccess()
        }
        monitor.start()
        if !monitor.isListening { waitForInputMonitoringAccess() }
    }

    /// After the user flips the Input Monitoring switch, pick it up without a relaunch.
    private func waitForInputMonitoringAccess() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, ButtonMonitor.hasInputMonitoringAccess else { return }
            timer.invalidate()
            self.monitor.start()
            self.refreshIcon()
        }
    }

    private func applyConfig(_ config: ButtonConfig) {
        store.save(config)
        monitor.update(device: config.resolvedDevice, suppressKey: config.suppressesKey)
        if config.action == .keys || config.action == .text, !ActionRunner.canPostKeys {
            askForAccessibility()
        }
        refreshIcon()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if store.reloadIfChanged() {
            monitor.update(device: store.config.resolvedDevice, suppressKey: store.config.suppressesKey)
        }
        menu.removeAllItems()
        let config = store.config

        menu.addItem(disabled(statusLine()))
        if let error = store.lastError { menu.addItem(disabled("⚠️ " + error)) }
        if !monitor.isListening {
            menu.addItem(item("Allow Input Monitoring…", #selector(openInputMonitoringSettings)))
        }
        if (config.action == .keys || config.action == .text) && !ActionRunner.canPostKeys {
            menu.addItem(item("Allow Accessibility (needed to send keys)…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        menu.addItem(disabled("When the button is pressed:"))
        let choices: [(ButtonConfig.Action, String, Selector)] = [
            (.enter, "Press Enter (normal)", #selector(chooseEnter)),
            (.keys, "Press a keyboard shortcut…", #selector(chooseKeys)),
            (.text, "Type some text…", #selector(chooseText)),
            (.command, "Run a shell command…", #selector(chooseCommand)),
            (.open, "Open an app, file or website…", #selector(chooseOpen)),
        ]
        for (action, title, selector) in choices {
            let mi = item(title, selector)
            mi.state = config.action == action ? .on : .off
            if config.action == action, action != .enter { mi.title = "\(title.replacingOccurrences(of: "…", with: ""))  —  \(detail(config))" }
            mi.indentationLevel = 1
            menu.addItem(mi)
        }
        let soundItem = NSMenuItem(title: config.action == .sound ? "Play a sound  —  \(config.sound ?? "Buzzer")" : "Play a sound", action: nil, keyEquivalent: "")
        soundItem.state = config.action == .sound ? .on : .off
        soundItem.indentationLevel = 1
        soundItem.submenu = soundMenu(selected: config.action == .sound ? (config.sound ?? "Buzzer") : nil)
        menu.addItem(soundItem)
        let mute = item("Do nothing (mute the button)", #selector(chooseNone))
        mute.state = config.action == .none ? .on : .off
        mute.indentationLevel = 1
        menu.addItem(mute)

        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "Button Colour", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu()
        menu.addItem(colorItem)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Edit Settings File…", #selector(editSettings)))
        menu.addItem(item("Show Log", #selector(showLog)))
        menu.addItem(item("Setup Guide…", #selector(openHelp)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Big Red Button", #selector(quit), key: "q"))
    }

    private func statusLine() -> String {
        if !monitor.isListening { return "⚪️ Needs Input Monitoring permission" }
        if !monitor.isConnected { return "⚪️ Button not found — plug it in with the USB-A cable" }
        return isPressed ? "🔴 Button pressed!" : "🔴 Button connected"
    }

    private func detail(_ config: ButtonConfig) -> String {
        let summary = config.summary
        if let space = summary.firstIndex(of: " ") { return String(summary[summary.index(after: space)...]) }
        return summary
    }

    private func soundMenu(selected: String?) -> NSMenu {
        let menu = NSMenu()
        for name in ActionRunner.builtInSounds + [""] + ActionRunner.systemSounds {
            if name.isEmpty { menu.addItem(.separator()); continue }
            let mi = item(name, #selector(chooseSound(_:)))
            mi.representedObject = name
            mi.state = name == selected ? .on : .off
            menu.addItem(mi)
        }
        return menu
    }

    private func colorMenu() -> NSMenu {
        let menu = NSMenu()
        for color in ButtonColor.allCases {
            let mi = item(color.title, #selector(chooseColor(_:)))
            mi.representedObject = color.rawValue
            mi.state = color == ButtonColor.current ? .on : .off
            mi.image = StatusIcon.image(color: color, connected: true, pressed: false)
            menu.addItem(mi)
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    // MARK: - Choosing actions

    @objc private func chooseEnter() { var c = store.config; c.action = .enter; applyConfig(c) }
    @objc private func chooseNone() { var c = store.config; c.action = .none; applyConfig(c) }

    @objc private func chooseSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var c = store.config
        c.action = .sound
        c.sound = name
        applyConfig(c)
        runner.pressed(c)
    }

    @objc private func chooseColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let color = ButtonColor(rawValue: raw) else { return }
        ButtonColor.current = color
        refreshIcon()
    }

    @objc private func chooseKeys() {
        NSApp.activate(ignoringOtherApps: true)
        recorder = ShortcutRecorder(current: store.config.keys) { [weak self] combo in
            guard let self else { return }
            self.recorder = nil
            guard let combo else { return }
            var c = self.store.config
            c.action = .keys
            c.keys = combo
            self.applyConfig(c)
        }
        recorder?.show()
    }

    @objc private func chooseText() {
        prompt(title: "Type some text", message: "The button will type this text into whatever app you're using.", value: store.config.text ?? "") { [weak self] value in
            guard let self else { return }
            var c = self.store.config
            c.action = .text
            c.text = value
            self.applyConfig(c)
        }
    }

    @objc private func chooseCommand() {
        prompt(title: "Run a shell command", message: "Runs in zsh as you, e.g. say \"Buzz\"  or  open -a Calculator  or  shortcuts run \"My Shortcut\"", value: store.config.command ?? "") { [weak self] value in
            guard let self else { return }
            var c = self.store.config
            c.action = .command
            c.command = value
            self.applyConfig(c)
        }
    }

    @objc private func chooseOpen() {
        prompt(title: "Open an app, file or website", message: "An app name (Calculator), a file path, or a web address (https://…).", value: store.config.open ?? "") { [weak self] value in
            guard let self else { return }
            var c = self.store.config
            c.action = .open
            c.open = value
            self.applyConfig(c)
        }
    }

    private func prompt(title: String, message: String, value: String, completion: @escaping (String) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { completion(text) }
    }

    // MARK: - Other menu commands

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.write("Login item change failed: \(error.localizedDescription)")
        }
    }

    @objc private func editSettings() {
        if !FileManager.default.fileExists(atPath: store.url.path) { store.save(store.config) }
        NSWorkspace.shared.open(store.url)
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) { Log.write("Log started") }
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func openHelp() { NSWorkspace.shared.open(Self.helpURL) }

    @objc private func openInputMonitoringSettings() {
        ButtonMonitor.requestInputMonitoringAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        waitForInputMonitoringAccess()
    }

    @objc private func openAccessibilitySettings() {
        ActionRunner.requestPostKeysAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func askForAccessibility() {
        if !ActionRunner.requestPostKeysAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: - Setup

    private func firstRunSetup() {
        let key = "didFirstRun"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
        if !FileManager.default.fileExists(atPath: store.url.path) {
            var c = ButtonConfig()
            c.action = .sound
            c.sound = "Buzzer"
            applyConfig(c)
        }
    }

    /// Restore the button's normal key if we're killed (e.g. by the installer during an update).
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func refreshIcon() {
        statusItem?.button?.image = StatusIcon.image(color: ButtonColor.current, connected: monitor.isConnected && monitor.isListening, pressed: isPressed)
        statusItem?.button?.toolTip = "Big Red Button — \(store.config.summary)"
    }
}

/// Small window that captures the next shortcut the user presses.
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var completion: ((String?) -> Void)?

    init(current: String?, completion: @escaping (String?) -> Void) {
        self.completion = completion
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 130), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Keyboard shortcut for the button"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let heading = NSTextField(labelWithString: "Press the shortcut the button should send.")
        heading.font = .boldSystemFont(ofSize: 13)
        label.stringValue = current.map { "Current: \(KeyCombo.display($0))   ·   Esc to cancel" } ?? "e.g. ⌘⇧4, Space, F13   ·   Esc to cancel"
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.frame = window.contentView!.bounds.insetBy(dx: 16, dy: 30)
        stack.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(stack)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                self.finish(nil)
            } else if let text = KeyCombo.text(for: event) {
                self.finish(text)
            } else {
                self.label.stringValue = "That key isn't supported — try another."
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }

    private func finish(_ result: String?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let done = completion
        completion = nil
        window.orderOut(nil)
        done?(result)
    }
}
