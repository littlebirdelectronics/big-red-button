# bigredbutton for Linux and Raspberry Pi

Makes the Little Bird **Big Red Button** run a command, press keys or type text. It runs in the background as a systemd service and takes the button over, so it stops pressing Enter. Your normal keyboard isn't affected.

It's a single program with no dependencies. It works on every Raspberry Pi (Zero, 1–5, 32-bit or 64-bit Raspberry Pi OS) and on other Linux PCs, with or without a desktop.

## Install

```sh
curl -fsSL https://littlebirdelectronics.com.au/button/install.sh | bash
```

This installs `/usr/local/bin/bigredbutton`, a `bigredbutton` systemd service, and a config file at `/etc/bigredbutton.json`. Commands run as the user who ran the installer.

Plug the button in with the **supplied USB-A to USB-C cable**. It won't power up on a USB-C to USB-C cable. On a Pi Zero, use a micro-USB OTG adapter.

## Make it do something

Each `set` saves the config and restarts the service, so the change takes effect straight away.

```sh
# Play a sound
sudo bigredbutton set command "aplay /usr/share/sounds/alsa/Front_Center.wav"

# Take a photo with the camera module
sudo bigredbutton set command 'rpicam-still -n -t 500 -o "$HOME/button-$(date +%Y%m%d-%H%M%S).jpg"'

# Run your own Python script
sudo bigredbutton set command "python3 /home/pi/button.py"

# Toggle an LED on GPIO 17
sudo bigredbutton set command 'if pinctrl get 17 | grep -q "| hi"; then pinctrl set 17 op dl; else pinctrl set 17 op dh; fi'

# Pulse GPIO 17 high for one second (a buzzer, relay or door strike)
sudo bigredbutton set command "pinctrl set 17 op dh; sleep 1; pinctrl set 17 op dl"

# Press a key in a game. The key is held for as long as the button is held.
sudo bigredbutton set keys space

# Press a shortcut, e.g. open a terminal
sudo bigredbutton set keys "ctrl+alt+t"

# Type some text
sudo bigredbutton set text "Hello from the big red button!"

# Back to normal: the button presses Enter
sudo bigredbutton set enter

# Make the button do nothing
sudo bigredbutton set none
```

Try out the action without the button: `sudo bigredbutton test`.

### Key names

`a`–`z`, `0`–`9`, `f1`–`f24`, `enter`, `space`, `tab`, `esc`, `backspace`, `delete`, `insert`, `home`, `end`, `pageup`, `pagedown`, `up`, `down`, `left`, `right`, `minus`, `equal`, `leftbracket`, `rightbracket`, `backslash`, `semicolon`, `quote`, `comma`, `period`, `slash`, `grave`, `capslock`, `printscreen`, `volumeup`, `volumedown`, `mute`, `playpause`, `next`, `previous`, `stop`.

Modifiers are `ctrl`, `shift`, `alt` and `super`. Join names with `+`, e.g. `ctrl+shift+s`. Typed text assumes a US keyboard layout.

### Commands

- Commands run with `/bin/sh -c` as the `run_as` user, with that user's `HOME`, so `~` and `$HOME` work.
- Each press starts a new copy of the command, without waiting for the last one to finish.
- Desktop programs work too: the command gets `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and the session bus of the user who's logged in to the desktop.
- Output and errors go to the service log.

Keys and text go through a virtual keyboard ("Big Red Button (virtual)"), so they work on X11 and Wayland desktops and on the text console.

## Config file

`/etc/bigredbutton.json`, which the macOS app shares the format of:

```json
{
  "action": "command",
  "command": "aplay /usr/share/sounds/alsa/Front_Center.wav",
  "keys": "ctrl+alt+t",
  "text": "Hello!",
  "run_as": "pi",
  "device": { "vendor_id": 33161, "product_id": 25 }
}
```

| Field | Meaning |
|---|---|
| `action` | `enter` (default, button untouched), `none`, `keys`, `text` or `command` |
| `keys` / `text` / `command` | Used by the matching action. The others are kept so you can switch back. |
| `run_as` | User that commands run as. Leave it out or use `root` to run as root. |
| `device` | Optional USB IDs, if your button reports different ones (`bigredbutton status` shows what's connected) |

After editing the file by hand, run `sudo systemctl restart bigredbutton`.

## Checking it works

```sh
bigredbutton status                 # config, whether the button is plugged in, service state
journalctl -u bigredbutton -f       # live log: presses, commands, errors
```

To watch raw presses, stop the service first, because only one program can hold the button:

```sh
sudo systemctl stop bigredbutton
sudo bigredbutton listen
sudo systemctl start bigredbutton
```

## Troubleshooting

- **"Button: not found"**: the button only works with the supplied USB-A to USB-C cable (or another USB-A to USB-C cable). With a USB-C to USB-C cable it gets no power, and its light won't come on when pressed. `lsusb` should list `8189:0019`.
- **Keys or text don't appear**: check the log for a uinput error. Run `sudo modprobe uinput` and restart the service.
- **A command works in a terminal but not from the button**: it probably needs something from your login shell. Use full paths, and check `journalctl -u bigredbutton` for its error output.

## Uninstall

```sh
curl -fsSL https://littlebirdelectronics.com.au/button/install.sh | bash -s -- --uninstall
```

Or by hand:

```sh
sudo systemctl disable --now bigredbutton
sudo rm /etc/systemd/system/bigredbutton.service /usr/local/bin/bigredbutton /etc/bigredbutton.json
sudo systemctl daemon-reload
```

## Building and testing

```sh
go test ./...                  # unit tests
VERSION=v1.0.0 ./build.sh      # static binaries for arm64, armv6 (every Pi) and amd64 in dist/
sudo ./e2e-test.sh             # end-to-end, on Linux with uinput: emulates the button
```

From a Mac with Podman: `./build.sh && podman machine ssh "sudo modprobe uinput && sudo CREATE_TEST_USER=1 $PWD/e2e-test.sh"`.
