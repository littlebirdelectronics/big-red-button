import Foundation
import IOKit.hid

/// Watches the button over HID and reports presses/releases.
///
/// We can't seize a keyboard without root, so to stop the button's own key reaching apps we use
/// macOS's per-device key remapping (the same mechanism as `hidutil property --matching … --set
/// UserKeyMapping`): every key on *this device only* is remapped to a usage that produces no event.
/// Raw HID values are read before remapping, so we still see the press. Needs Input Monitoring.
final class ButtonMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private(set) var isConnected = false
    private(set) var isListening = false

    /// Keyboard usage that macOS turns into no key event at all.
    static let silentUsage: UInt64 = 0x7_0000_0000

    private var manager: IOHIDManager?
    private var device: ButtonConfig.DeviceID
    private var suppressKey: Bool
    private var devices = Set<IOHIDDevice>()
    private var held = Set<UInt64>()

    init(device: ButtonConfig.DeviceID, suppressKey: Bool) {
        self.device = device
        self.suppressKey = suppressKey
    }

    static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt the first time; afterwards the user has to flip the switch in System Settings.
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func start() {
        stop()
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: device.vendor_id, kIOHIDProductIDKey: device.product_id] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            Unmanaged<ButtonMonitor>.fromOpaque(ctx!).takeUnretainedValue().added(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            Unmanaged<ButtonMonitor>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            Unmanaged<ButtonMonitor>.fromOpaque(ctx!).takeUnretainedValue().received(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        isListening = result == kIOReturnSuccess && Self.hasInputMonitoringAccess
        if !isListening {
            Log.write("Couldn't open HID manager: 0x\(String(UInt32(bitPattern: result), radix: 16)) (Input Monitoring not granted?)")
        }
        manager = mgr
    }

    func stop() {
        if let mgr = manager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        isListening = false
        devices.removeAll()
        held.removeAll()
        setConnected(false)
    }

    /// Applies new settings. Restarts matching if the device IDs changed.
    func update(device newDevice: ButtonConfig.DeviceID, suppressKey newSuppress: Bool) {
        let deviceChanged = newDevice != device
        if deviceChanged { restoreKey() }
        device = newDevice
        suppressKey = newSuppress
        if deviceChanged { start() } else { applyKeyMapping() }
    }

    /// Puts the button back to its normal key. Call before quitting.
    func restoreKey() {
        Self.setUserKeyMapping([], device: device, wait: true)
    }

    // MARK: - HID callbacks

    private func added(_ dev: IOHIDDevice) {
        devices.insert(dev)
        let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?"
        let page = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        Log.write("Button interface connected: \(name) usage page 0x\(String(page, radix: 16))")
        setConnected(true)
        // The HID event service can appear a moment after the device, so apply the mapping a few times.
        for delay in [0.0, 0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyKeyMapping() }
        }
    }

    private func removed(_ dev: IOHIDDevice) {
        devices.remove(dev)
        if devices.isEmpty {
            Log.write("Button disconnected")
            if !held.isEmpty {
                held.removeAll()
                onRelease?()
            }
            setConnected(false)
        }
    }

    private func received(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let isKey: Bool
        switch page {
        case UInt32(kHIDPage_KeyboardOrKeypad): isKey = (4...0xE7).contains(usage)
        case UInt32(kHIDPage_Consumer), UInt32(kHIDPage_Button): isKey = usage != 0
        default: isKey = false
        }
        guard isKey else { return }
        let id = UInt64(page) << 32 | UInt64(usage)
        let wasEmpty = held.isEmpty
        if IOHIDValueGetIntegerValue(value) != 0 { held.insert(id) } else { held.remove(id) }
        if wasEmpty && !held.isEmpty { onPress?() }
        if !wasEmpty && held.isEmpty { onRelease?() }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChange?(connected)
    }

    // MARK: - Key mapping

    private func applyKeyMapping() {
        // Never silence the key unless we can actually hear the presses ourselves.
        guard isConnected, isListening else { return }
        Self.setUserKeyMapping(suppressKey ? Self.silenceAllKeys : [], device: device, wait: false)
    }

    /// Every keyboard usage (letters through modifiers) → silent, so whatever key the button was
    /// programmed with, it never reaches apps.
    private static let silenceAllKeys: [[String: UInt64]] = (Array(0x04...0x65) + Array(0xE0...0xE7)).map {
        ["HIDKeyboardModifierMappingSrc": 0x7_0000_0000 | UInt64($0), "HIDKeyboardModifierMappingDst": silentUsage]
    }

    private static func setUserKeyMapping(_ mapping: [[String: UInt64]], device: ButtonConfig.DeviceID, wait: Bool) {
        let entries = mapping.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0["HIDKeyboardModifierMappingSrc"]!),\"HIDKeyboardModifierMappingDst\":\($0["HIDKeyboardModifierMappingDst"]!)}"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property",
            "--matching", "{\"VendorID\":\(device.vendor_id),\"ProductID\":\(device.product_id)}",
            "--set", "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            if wait { process.waitUntilExit() }
        } catch {
            Log.write("hidutil failed: \(error.localizedDescription)")
        }
    }
}
