import AppKit

/// Carries out the configured action when the button goes down / up.
final class ActionRunner {
    /// Called when an action needs a permission we don't have yet.
    var onNeedsAccessibility: (() -> Void)?

    private var heldCombo: KeyCombo?
    private var sound: NSSound?

    static let builtInSounds = ["Buzzer", "Ding"]
    static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    /// Posting keystrokes needs the Accessibility switch for this app.
    static var canPostKeys: Bool { CGPreflightPostEventAccess() }

    @discardableResult
    static func requestPostKeysAccess() -> Bool { CGRequestPostEventAccess() }

    func pressed(_ config: ButtonConfig) {
        switch config.action {
        case .enter, .none:
            break
        case .keys:
            guard let combo = KeyCombo(config.keys ?? "") else {
                Log.write("Can't understand shortcut “\(config.keys ?? "")”")
                return
            }
            guard ensureCanPostKeys() else { return }
            heldCombo = combo
            post(combo, down: true)
        case .text:
            guard ensureCanPostKeys() else { return }
            type(config.text ?? "")
        case .command:
            run(config.command ?? "")
        case .open:
            open(config.open ?? "")
        case .sound:
            play(config.sound ?? "Buzzer")
        }
    }

    func released(_ config: ButtonConfig) {
        // Keys stay down for as long as the button is held, so it works for push-to-talk and games.
        if let combo = heldCombo {
            post(combo, down: false)
            heldCombo = nil
        }
    }

    private func ensureCanPostKeys() -> Bool {
        if Self.canPostKeys { return true }
        Log.write("Accessibility permission needed to send keystrokes")
        onNeedsAccessibility?()
        return false
    }

    // MARK: - Keys

    private func post(_ combo: KeyCombo, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let media = combo.mediaKey {
            postMediaKey(media, down: down)
            return
        }
        if let code = combo.keyCode {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = combo.modifiers
            event?.post(tap: .cghidEventTap)
            return
        }
        // Modifier-only combo, e.g. "cmd" held for push-to-talk.
        let modifierKeys: [(CGEventFlags, Int)] = [(.maskCommand, kVKCommand), (.maskShift, kVKShift), (.maskAlternate, kVKOption), (.maskControl, kVKControl)]
        var flags: CGEventFlags = down ? [] : combo.modifiers
        for (flag, key) in modifierKeys where combo.modifiers.contains(flag) {
            if down { flags.insert(flag) } else { flags.remove(flag) }
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.type = .flagsChanged
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private let kVKCommand = 55, kVKShift = 56, kVKOption = 58, kVKControl = 59

    private func postMediaKey(_ key: Int32, down: Bool) {
        let data1 = Int((key << 16) | (down ? 0xA00 : 0xB00))
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.offset > 0 {
                for down in [true, false] {
                    CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(36), keyDown: down)?.post(tap: .cghidEventTap)
                }
            }
            for ch in line.element {
                let utf16 = Array(String(ch).utf16)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: - Command / open / sound

    private func run(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let process = Process()
        // A login shell picks up the user's PATH (Homebrew etc).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        if let log = try? FileHandle(forWritingTo: Log.url) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }
        process.terminationHandler = { p in
            if p.terminationStatus != 0 { Log.write("Command exited with status \(p.terminationStatus): \(command)") }
        }
        do {
            try process.run()
            Log.write("Ran: \(command)")
        } catch {
            Log.write("Couldn't run command: \(error.localizedDescription)")
        }
    }

    private func open(_ target: String) {
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let path = (target as NSString).expandingTildeInPath
        if let url = URL(string: target), let scheme = url.scheme, scheme.count > 1 {
            NSWorkspace.shared.open(url)
        } else if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            // Treat it as an app name, e.g. "Calculator".
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", target]
            try? process.run()
        }
    }

    private func play(_ name: String) {
        sound?.stop()
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") {
            sound = NSSound(contentsOf: url, byReference: true)
        } else if FileManager.default.fileExists(atPath: (name as NSString).expandingTildeInPath) {
            sound = NSSound(contentsOfFile: (name as NSString).expandingTildeInPath, byReference: true)
        } else {
            sound = NSSound(named: NSSound.Name(name))
        }
        if sound?.play() != true { Log.write("Couldn't play sound “\(name)”") }
    }
}
