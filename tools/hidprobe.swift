// Logs raw HID reports + decoded values from the LinTx big red button (0x8189:0x0019),
// plus the key events macOS actually delivers (CGEventTap, listen-only).
import Foundation
import IOKit.hid
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)
let duration = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60

print("Input Monitoring access (0=granted 1=denied 2=unknown):", IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue)

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x8189, kIOHIDProductIDKey: 0x19] as CFDictionary)

IOHIDManagerRegisterDeviceMatchingCallback(mgr, { _, _, _, dev in
    let page = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
    let usage = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
    let desc = (IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data)?
        .map { String(format: "%02x", $0) }.joined(separator: " ") ?? "nil"
    print("INTERFACE usagePage=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16))")
    print("  report descriptor: \(desc)")
    let size = IOHIDDeviceGetProperty(dev, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: max(size, 1))
    IOHIDDeviceRegisterInputReportCallback(dev, buf, max(size, 1), { _, _, _, _, reportID, report, len in
        let bytes = (0..<len).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
        print("RAW  t=\(String(format: "%.3f", Date().timeIntervalSince1970)) id=\(reportID) len=\(len): \(bytes)")
    }, nil)
}, nil)

IOHIDManagerRegisterInputValueCallback(mgr, { _, _, _, value in
    let el = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
    if page == 7 && (usage == 0xFFFFFFFF || usage < 4) { return }
    print("HID  page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(IOHIDValueGetIntegerValue(value))")
}, nil)

IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
print("IOHIDManagerOpen: 0x\(String(UInt32(bitPattern: openResult), radix: 16))")

// What reaches macOS after the driver (and Karabiner, if it grabs the device).
let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14) // 14 = NSSystemDefined (media keys)
if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                               eventsOfInterest: mask, callback: { _, type, event, _ in
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    print("OS   type=\(type.rawValue) keycode=\(keycode) flags=0x\(String(event.flags.rawValue, radix: 16))")
    return Unmanaged.passUnretained(event)
}, userInfo: nil) {
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("event tap: on")
} else {
    print("event tap: FAILED (needs Input Monitoring)")
}

print("listening for \(Int(duration))s ...")
DispatchQueue.main.asyncAfter(deadline: .now() + duration) { print("done"); exit(0) }
CFRunLoopRun()
