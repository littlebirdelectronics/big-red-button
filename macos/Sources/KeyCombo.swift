import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut written as text, e.g. "cmd+shift+4", "ctrl+alt+t", "space", "f13", "playpause".
/// The names are shared with the Linux daemon so one config file works on both.
struct KeyCombo: Equatable {
    var modifiers: CGEventFlags = []
    /// Virtual key code of the main key, or nil for a modifier-only combo ("cmd").
    var keyCode: CGKeyCode?
    /// NX_KEYTYPE_* for media keys (volume, play/pause…), which macOS sends as system-defined events.
    var mediaKey: Int32?

    static let modifierNames: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "super": .maskCommand, "win": .maskCommand, "meta": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate,
        "shift": .maskShift,
    ]

    static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7,
        "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13,
        "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19,
        "f20": kVK_F20,
        "enter": kVK_Return, "return": kVK_Return, "space": kVK_Space, "tab": kVK_Tab,
        "esc": kVK_Escape, "escape": kVK_Escape, "backspace": kVK_Delete, "delete": kVK_ForwardDelete,
        "insert": kVK_Help, "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "leftbracket": kVK_ANSI_LeftBracket,
        "rightbracket": kVK_ANSI_RightBracket, "backslash": kVK_ANSI_Backslash, "semicolon": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "apostrophe": kVK_ANSI_Quote, "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
        "dot": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "grave": kVK_ANSI_Grave, "backtick": kVK_ANSI_Grave,
        "capslock": kVK_CapsLock,
    ]

    // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
    static let mediaKeys: [String: Int32] = [
        "volumeup": 0, "volumedown": 1, "brightnessup": 2, "brightnessdown": 3, "mute": 7,
        "playpause": 16, "next": 17, "nextsong": 17, "previous": 18, "previoussong": 18,
    ]

    /// Parses "cmd+shift+4". Returns nil if any part is unknown or there's more than one main key.
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }
        for part in parts {
            if let flag = Self.modifierNames[part] {
                modifiers.insert(flag)
            } else if keyCode == nil, mediaKey == nil, let code = Self.keyCodes[part] {
                keyCode = CGKeyCode(code)
            } else if keyCode == nil, mediaKey == nil, let media = Self.mediaKeys[part] {
                mediaKey = media
            } else {
                return nil
            }
        }
    }

    /// Builds the text form from a key the user pressed in the shortcut recorder.
    static func text(for event: NSEvent) -> String? {
        guard let name = keyCodes.first(where: { $0.value == Int(event.keyCode) && !["return", "escape", "apostrophe", "dot", "backtick"].contains($0.key) })?.key else {
            return nil
        }
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        parts.append(name)
        return parts.joined(separator: "+")
    }

    /// "cmd+shift+4" → "⌘⇧4" for the menu. Falls back to the raw text.
    static func display(_ text: String) -> String {
        guard KeyCombo(text) != nil else { return text }
        let symbols: [String: String] = ["ctrl": "⌃", "control": "⌃", "alt": "⌥", "option": "⌥", "opt": "⌥",
                                         "shift": "⇧", "cmd": "⌘", "command": "⌘", "super": "⌘", "win": "⌘", "meta": "⌘"]
        return text.lowercased().split(separator: "+").map { part in
            let p = String(part)
            return symbols[p] ?? (p.count == 1 ? p.uppercased() : p.capitalized)
        }.joined()
    }
}
