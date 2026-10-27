import Foundation

/// What the button does. The JSON field names match the Linux daemon's /etc/bigredbutton.json,
/// so one example config works on both.
struct ButtonConfig: Codable, Equatable {
    enum Action: String, Codable, CaseIterable {
        case enter, keys, text, command, open, sound, none
    }

    struct DeviceID: Codable, Equatable {
        var vendor_id: Int
        var product_id: Int
    }

    var action: Action = .enter
    var keys: String?
    var text: String?
    var command: String?
    var open: String?
    var sound: String?
    var device: DeviceID?

    static let defaultDevice = DeviceID(vendor_id: 0x8189, product_id: 0x0019)

    var resolvedDevice: DeviceID { device ?? Self.defaultDevice }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .action) ?? "enter"
        guard let action = Action(rawValue: raw.lowercased()) else {
            throw ConfigError.unknownAction(raw)
        }
        self.action = action
        keys = try c.decodeIfPresent(String.self, forKey: .keys)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        open = try c.decodeIfPresent(String.self, forKey: .open)
        sound = try c.decodeIfPresent(String.self, forKey: .sound)
        device = try c.decodeIfPresent(DeviceID.self, forKey: .device)
    }

    /// Whether the button's own Enter key must be silenced so only our action happens.
    var suppressesKey: Bool { action != .enter }

    /// Short human description for the menu.
    var summary: String {
        switch action {
        case .enter: return "Press Enter (normal)"
        case .keys: return "Press \(KeyCombo.display(keys ?? ""))"
        case .text: return "Type “\(Self.clip(text ?? ""))”"
        case .command: return "Run “\(Self.clip(command ?? ""))”"
        case .open: return "Open \(Self.clip(open ?? ""))"
        case .sound: return "Play sound “\(sound ?? "Buzzer")”"
        case .none: return "Do nothing (muted)"
        }
    }

    private static func clip(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 32 ? String(oneLine.prefix(31)) + "…" : oneLine
    }
}

enum ConfigError: LocalizedError {
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .unknownAction(let a):
            return "Unknown action “\(a)”. Use one of: " + ButtonConfig.Action.allCases.map(\.rawValue).joined(separator: ", ")
        }
    }
}

/// Loads and saves ~/Library/Application Support/BigRedButton/config.json.
final class ConfigStore {
    let url: URL
    private(set) var config = ButtonConfig()
    private(set) var lastError: String?
    private var loadedModDate: Date?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("BigRedButton/config.json")
        reload()
    }

    /// Re-reads the file only if it changed on disk. Returns true when the config changed.
    @discardableResult
    func reloadIfChanged() -> Bool {
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        guard mod != loadedModDate else { return false }
        let before = config
        reload()
        return config != before
    }

    func reload() {
        loadedModDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        guard let data = try? Data(contentsOf: url) else {
            config = ButtonConfig()
            lastError = nil
            return
        }
        do {
            config = try JSONDecoder().decode(ButtonConfig.self, from: data)
            lastError = nil
        } catch {
            lastError = "Settings file problem: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            Log.write(lastError!)
        }
    }

    func save(_ newConfig: ButtonConfig) {
        config = newConfig
        lastError = nil
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try enc.encode(newConfig).write(to: url, options: .atomic)
            loadedModDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        } catch {
            lastError = "Couldn’t save settings: \(error.localizedDescription)"
            Log.write(lastError!)
        }
    }
}

enum Log {
    static let url: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
        return logs.appendingPathComponent("BigRedButton.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        NSLog("%@", message)
        try? appendHandle()?.write(contentsOf: Data(line.utf8))
    }

    /// Opens the log with O_APPEND, so every write lands at the end, including output from commands we run.
    static func appendHandle() -> FileHandle? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return fd < 0 ? nil : FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
