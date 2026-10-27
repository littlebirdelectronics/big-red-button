# Big Red Button: hardware notes

Little Bird SKU **LB-LS7008-R** (product ID 589, handle `big-game-button-with-enclosure-100mm-usb-c`).

How the button works under the hood, from probing a real unit on a Mac (2026-10-27). For setup, see the [main README](../README.md).

## TL;DR

- It is a **USB keyboard with one key: Enter (Return)**. Press = key down, release = key up. It lights up while pressed.
- No drivers or software needed. Any OS that accepts a USB keyboard works.
- **Use the supplied USB-A to USB-C cable.** On a USB-C to USB-C cable the button gets no power: no light, nothing on the USB bus, in either plug orientation.
- To make it do something other than Enter, remap Enter **from this device only** with a hotkey app (Karabiner-Elements on Mac). See [Remapping on macOS](#remapping-on-macos).

## The cable gotcha (why it "does nothing")

| Cable | Result |
|---|---|
| USB-C to USB-C, known-good cable and port (a DJI mic receiver worked on it minutes earlier) | Dead. No light, no USB enumeration, no kernel USB log entries. Same after flipping the plug 180°. |
| Supplied USB-A to USB-C, Mac's USB-A port | Enumerates instantly, lights when pressed, types Enter. |

Most likely cause: the button's USB-C socket is missing the 5.1 kΩ CC pull-down resistors a USB-C device needs before a USB-C host will switch on 5 V. A USB-A port always supplies 5 V, so an A-to-C cable bypasses the problem. This is inferred from the behaviour above, not measured with a meter.

If a customer's computer only has USB-C ports, use the supplied cable with a USB-C to USB-A adapter or a hub that has USB-A ports.

On first connection macOS opens **Keyboard Setup Assistant** ("identify your keyboard"). Close it. A one-key keyboard can't answer it, and closing it has no side effects.

## USB identity

| Field | Value |
|---|---|
| Manufacturer string | `LinTx` |
| Product string | `USB Keyboard` |
| Vendor ID | `0x8189` (33161) |
| Product ID | `0x0019` (25) |
| bcdUSB / speed | USB 2.0, full speed (12 Mbit/s) |
| Power | 200 mA |

## HID interfaces

### Interface 0: keyboard (usage page 0x01, usage 0x06)

One composite interface with four report IDs. The report descriptor shows the controller can send any of these, though this unit ships configured to send only Enter.

| Report ID | Type | Contents |
|---|---|---|
| 1 | Keyboard | 8 modifier bits, reserved byte, 6-key array (usages 0x00 to 0x65), 5 LED output bits |
| 2 | Consumer control | 18 one-bit keys: My Computer, Calculator, Media Player, Home, Email, Favourites, Search, Back, Forward, Stop, Refresh, Previous Track, Next Track, Stop, Play/Pause, Volume Up, Volume Down, Mute |
| 3 | Mouse (relative) | 8 buttons, wheel, X, Y (−127 to 127) |
| 4 | Pointer (absolute) | 8 buttons, wheel, X/Y absolute (0 to 32767) |

Observed reports for one press:

```
press    id=1: 01 00 00 28 00 00 00 00 00   # key array = 0x28 (Keyboard Return/Enter)
release  id=1: 01 00 00 00 00 00 00 00 00
```

While held, the button re-sends reports 1 to 4 about every 13 ms. The key state stays "down", so the OS auto-repeats Enter exactly as it would for a held keyboard key.

### Interface 1: vendor-defined (usage page 0xFF00)

64-byte input and 64-byte output reports. This is almost certainly the configuration channel used to reprogram which key, combo, media key or mouse action the button sends. One unsolicited input report was seen: `66 cc 03 00 01 09 00 …`.

We have **not** found the vendor's configuration software. A web search for LinTx 0x8189:0x0019 turned up nothing. If we want customers to be able to reprogram the button itself, ask the supplier for the tool.

## What macOS sees

- HID: usage page 0x07, usage 0x28 (Keyboard Return/Enter)
- Karabiner-EventViewer: `{"key_code":"return_or_enter"}` from **USB Keyboard**
- CGEvent: keycode 36

## Remapping on macOS

Use [Karabiner-Elements](https://karabiner-elements.pqrs.org/) (free). The rule must be scoped to this device. A global Enter remap would also change the Enter key on the real keyboard.

1. Install Karabiner-Elements and grant the permissions it asks for.
2. Plug the button in. In **Settings → Devices**, check that **Modify events** is on for *USB Keyboard (LinTx)*. It is on by default for keyboards.
3. **Settings → Complex Modifications → Add your own rule**, then paste one of the rules below and save.

Button sends F18, which nothing uses by default, so it's free to bind in any app or hotkey tool:

```json
{
  "description": "Big Red Button → F18",
  "manipulators": [
    {
      "type": "basic",
      "conditions": [
        { "type": "device_if", "identifiers": [{ "vendor_id": 33161, "product_id": 25 }] }
      ],
      "from": { "key_code": "return_or_enter", "modifiers": { "optional": ["any"] } },
      "to": [{ "key_code": "f18" }]
    }
  ]
}
```

Button runs a shell command:

```json
{
  "description": "Big Red Button → run a command",
  "manipulators": [
    {
      "type": "basic",
      "conditions": [
        { "type": "device_if", "identifiers": [{ "vendor_id": 33161, "product_id": 25 }] }
      ],
      "from": { "key_code": "return_or_enter", "modifiers": { "optional": ["any"] } },
      "to": [{ "shell_command": "open -a Calculator" }]
    }
  ]
}
```

To map it to a key combo instead, e.g. ⌘⇧4 for a screenshot: `"to": [{ "key_code": "4", "modifiers": ["left_command", "left_shift"] }]`.

Karabiner-EventViewer, which ships with Karabiner, is the quickest way to confirm the button is connected: press the button and look for `return_or_enter` from **USB Keyboard**.

## Probing tool

[`tools/hidprobe.swift`](../tools/hidprobe.swift) prints the button's HID report descriptors and raw reports, plus the key events macOS delivers. The terminal needs **Input Monitoring** permission (System Settings → Privacy & Security). While it runs it also logs keystrokes from every other keyboard, so don't type anything private.

```sh
swiftc -O tools/hidprobe.swift -o /tmp/hidprobe && /tmp/hidprobe 30   # listen for 30 s
```

To probe a different device, change the vendor and product IDs in `IOHIDManagerSetDeviceMatching`.

