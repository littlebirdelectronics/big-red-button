# Big Red Button: Windows setup guide

**Big Game Button with Enclosure 100mm USB Red** from Little Bird Electronics (SKU **LB-LS7008-R**)

## The short version

- Plug it in with the **USB-A to USB-C cable that came in the box**. You don't need drivers or software.
- Windows sees the button as a keyboard with one key: **Enter**.
- If your quiz or buzzer software already listens for Enter, you're done. See [Use it as-is](#2-use-it-as-is-no-setup).
- To make the button do something else, like run a program or send a shortcut, **without changing the Enter key on your real keyboard**, use [Option A (LuaMacros)](#option-a-luamacros-no-driver) or [Option B (AutoHotkey + AutoHotInterception)](#option-b-autohotkey-v2--autohotinterception).
- On a PC that's only used for the quiz or kiosk, a simple global remap is fine. See [Dedicated quiz or kiosk PC](#4-dedicated-quiz-or-kiosk-pc).

---

## 1. Plug it in

1. Plug the USB-C end of the **supplied cable** into the button.
2. Plug the USB-A end (the big rectangular one) into your PC.
3. Press the button. It lights up while you're holding it down.
4. To test it, open Notepad and press the button. The cursor should jump to a new line.

> **Only the supplied USB-A to USB-C cable works.** On a USB-C to USB-C cable the button gets no power at all: no light and nothing in Windows. If your PC only has USB-C ports, use the supplied cable with a **USB-C to USB-A adapter** or a hub that has USB-A ports.

---

## 2. Use it as-is (no setup)

The button sends **Enter**. It sends key down when you press it and key up when you let go, just like a keyboard key.

That suits:

- quiz, buzzer and game-show software that waits for Enter
- anything else that responds to the Enter key

Two things to know:

- Key presses go to whichever window is active. Click on the quiz program's window first.
- Holding the button down repeats Enter, the same as holding down a keyboard key.

---

## 3. Make it do something else (just the button)

The catch is that Windows treats every keyboard's Enter key the same way. Most remapping tools, including Microsoft PowerToys Keyboard Manager and ordinary AutoHotkey hotkeys, would change the Enter key on **every** keyboard. Microsoft's PowerToys documentation confirms that it can't use different mappings for different keyboards.

To change only the button, you need a tool that can tell keyboards apart. These two are free:

| | Option A: LuaMacros | Option B: AutoHotkey + AutoHotInterception |
|---|---|---|
| Needs a driver | No | Yes (admin install and a restart) |
| Stops the button's Enter reaching apps | In most apps (see the [limits](#limits)) | Everywhere, at the driver level |
| Script language | Lua | AutoHotkey v2 |
| Still being developed? | No. Development officially ended in March 2023 | AutoHotInterception v0.9.2 (August 2026). The Interception driver dates from 2017 |

Which should you pick?

- **Only need Enter?** Nothing to install. See [Use it as-is](#2-use-it-as-is-no-setup).
- **A PC used only for the quiz or kiosk?** The easiest route is a simple global remap. See [section 4](#4-dedicated-quiz-or-kiosk-pc).
- **A shared PC where the keyboard's Enter must keep working?** Use **Option B**, which you can download today. Option A needs no driver, but its download site was offline when we checked in October 2026.

---

### Option A: LuaMacros (no driver)

LuaMacros is a free program from the author of HidMacros. It can tell keyboards apart and run a small Lua script when a key on a particular keyboard is pressed.

> **Heads-up:** The author officially ended development in March 2023 and doesn't offer support. The download is on the author's website, which the [LuaMacros GitHub page](https://github.com/me2d13/luamacros) links to. When we checked in October 2026, that website wasn't loading. If you can't download it, use [Option B](#option-b-autohotkey-v2--autohotinterception).

#### Set it up

1. Plug the button in.
2. Download **luamacros.zip** from the link on the GitHub page: <http://www.hidmacros.eu/luamacros.zip>
3. Extract the whole zip into a folder, such as `C:\BigButton`. There's nothing to install, but keep all the files together.
4. Double-click `LuaMacros.exe`. If Windows says it "protected your PC", click **More info**, then **Run anyway**.
5. Paste one of the scripts below into the big editor box.
6. Save it as `C:\BigButton\button.lua`.
7. Run the script by pressing **Ctrl+Enter** on your normal keyboard, or by clicking the **Run script** button on the toolbar.
8. Press the big red button.

If you unplug the button and plug it back in, run the script again so LuaMacros finds it again.

#### Script 1: run a program when the button is pressed

```lua
-- Big Red Button (Little Bird LB-LS7008-R): run a program on press

-- Find the button by its USB vendor ID (8189) and call it BUTTON
local found = lmc_device_set_name('BUTTON', '8189')
if found == nil or found == '' then
  print('Big Red Button not found. Plug it in, then run the script again.')
end

local held = false

-- This handler covers every key from the button. Because it covers the
-- whole device, LuaMacros also stops the button's Enter reaching your apps.
-- Your normal keyboard is a different device, so its Enter is unaffected.
lmc_set_handler('BUTTON', function(button, direction)
  if direction == 1 then        -- 1 = pressed
    if held then return end     -- ignore key repeat while it's held down
    held = true
    lmc_spawn('notepad')        -- <-- change this to what you want to run
  else                          -- 0 = released
    held = false
  end
end)
```

Other things you can put in place of `lmc_spawn('notepad')`:

```lua
lmc_spawn('calc')                                      -- open Calculator
lmc_spawn('notepad', 'C:\\BigButton\\notes.txt')       -- a program plus a file to open
lmc_spawn('cmd', '/c', 'C:\\BigButton\\pressed.bat')   -- run your own batch file
```

In Lua strings, every backslash in a Windows path is written twice (`\\`). The batch-file option lets you do almost anything, such as open a website with `start "" "https://example.com"`. A command window may flash up for a moment when it runs.

#### Script 2: send a keyboard shortcut when the button is pressed

```lua
-- Big Red Button (Little Bird LB-LS7008-R): send a shortcut on press

local found = lmc_device_set_name('BUTTON', '8189')
if found == nil or found == '' then
  print('Big Red Button not found. Plug it in, then run the script again.')
end

local held = false

lmc_set_handler('BUTTON', function(button, direction)
  if direction == 1 then        -- 1 = pressed
    if held then return end     -- ignore key repeat while it's held down
    held = true
    lmc_send_keys('^+m')        -- <-- Ctrl+Shift+M. Change to the shortcut you need
  else                          -- 0 = released
    held = false
  end
end)
```

How to write shortcuts for `lmc_send_keys`:

| Write | For |
|---|---|
| `^` | Ctrl |
| `+` | Shift |
| `%` | Alt |
| `#` | Windows key |
| `{F5}`, `{ENTER}`, `{TAB}`, `{ESC}`, `{LEFT}`, `{RIGHT}`, `{UP}`, `{DOWN}`, `{HOME}`, `{END}`, `{PGUP}`, `{PGDN}` | That key |

Some examples: `'^+m'` is Ctrl+Shift+M, `'%{F4}'` is Alt+F4 and `'{RIGHT}'` is the right arrow. Use lower-case letters, because an upper-case letter adds Shift.

**Tip:** `{F13}` through `{F24}` also work. Normal keyboards don't have those keys, so if your app lets you set a hotkey by pressing a key, have the button send `{F18}` and use it as a hotkey that nothing else clashes with.

#### Start it automatically when Windows starts

1. Add these two lines to the **top** of your script and save it. They hide LuaMacros in the system tray. Double-click the tray icon to bring the window back.

   ```lua
   lmc.minimizeToTray = true
   lmc_minimize()
   ```

2. Press **Win+R**, type `shell:startup` and press Enter. A folder opens.
3. Right-click in the folder and choose **New → Shortcut**. For the location, enter the line below, changing the paths if you used a different folder:

   ```
   "C:\BigButton\LuaMacros.exe" -r "C:\BigButton\button.lua"
   ```

   The `-r` tells LuaMacros to run the script straight away.
4. Give the shortcut a name, like `Big Red Button`, and finish.

#### Limits

- LuaMacros must be running for the button to do anything other than Enter.
- LuaMacros stops the button's Enter using a standard Windows keyboard hook. Windows doesn't let that hook reach programs running **as administrator**, so those programs may still get an Enter. If that's a problem, use Option B.
- The device name is matched by searching the button's Windows device ID for the text `8189`. To see what LuaMacros found, add `lmc_print_devices()` on its own line and run the script again. The list appears in the bottom pane.

---

### Option B: AutoHotkey v2 + AutoHotInterception

[AutoHotInterception](https://github.com/evilC/AutoHotInterception) (AHI) lets an [AutoHotkey](https://www.autohotkey.com/) script react to a key on **one specific keyboard** and block that key so Windows never sees it. It relies on the free **Interception** driver.

> **Before you start:**
>
> - Installing the driver needs an **administrator** Command Prompt and a **restart**.
> - Interception works below Windows itself, so a badly written script could block keys you need. The script below only blocks Enter on the button, but keep a mouse handy while you set things up.
> - **Known Interception limit:** every time you unplug and replug a keyboard, or the PC resumes from hibernate, its Interception ID goes up by 1. If a keyboard's ID goes above 10, that keyboard **stops working completely, in Windows too, until you restart**. If you plug the button in and out a lot, restart the PC now and then.
> - Interception is free for non-commercial use. If you're using it in a business, read its licence on the [Interception GitHub page](https://github.com/oblitum/Interception).

#### Step 1: install AutoHotkey v2

1. Go to <https://www.autohotkey.com/download/> and download the current v2 release (2.0.31 when we checked).
2. Run the installer and accept the defaults.

#### Step 2: install the Interception driver

1. Download **Interception.zip** from the releases page: <https://github.com/oblitum/Interception/releases>. **Only download it from GitHub.** The driver's old website, oblita.com, has been compromised and was serving malware.
2. Right-click the zip and choose **Properties**. If there's an **Unblock** tickbox, tick it and click **OK**. Then extract the zip.
3. Open the Start menu and type `cmd`. Right-click **Command Prompt** and choose **Run as administrator**.
4. Go to the installer folder inside the extracted zip, for example:

   ```
   cd "%USERPROFILE%\Downloads\Interception\command line installer"
   ```

5. Run:

   ```
   install-interception.exe /install
   ```

   It should say: `Interception successfully installed. You must reboot for it to take effect.` Don't double-click the installer, because it has to run from an administrator prompt.
6. **Restart the PC.**

To remove the driver later, run `install-interception.exe /uninstall` from an administrator Command Prompt and restart.

#### Step 3: set up the AutoHotInterception folder

1. Download **AutoHotInterception.zip** from the releases page: <https://github.com/evilC/AutoHotInterception/releases>. Use the zip attached to the release. GitHub's "Download ZIP" of the source code won't work.
2. Unblock the zip the same way as before (Properties, tick **Unblock**), then open it.
3. Copy the **`AHK v2`** folder out of the zip to somewhere permanent, such as `C:\BigButton\AHI`. This is your working folder.
4. From the AHI zip, copy `Common\Lib\AutoHotInterception.dll` into `C:\BigButton\AHI\Lib`.
5. From the Interception zip, copy **both** the `library\x86` and `library\x64` folders into `C:\BigButton\AHI\Lib`.

You should end up with:

```
C:\BigButton\AHI
    Monitor.ahk
    (other example scripts)
    Lib
        AutoHotInterception.ahk
        AutoHotInterception.dll
        CLR.ahk
        x86\interception.dll
        x64\interception.dll
```

#### Step 4: check that it can see the button

1. Plug the button in.
2. Double-click `Monitor.ahk` in `C:\BigButton\AHI`.
3. Find the keyboard with **VID 0x8189** and **PID 0x0019**, and tick just that one. **Don't tick everything at once.** If the monitor crashes with every device ticked, it can lock up all your keyboards and mice.
4. Press the big red button. You should see its key events appear.
5. Close the monitor.

#### Step 5: the script

Save this as `C:\BigButton\AHI\BigRedButton.ahk`, in the same folder as `Monitor.ahk`, then double-click it to run it.

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#include Lib\AutoHotInterception.ahk

AHI := AutoHotInterception()

; Find the Big Red Button by its USB IDs (VID 0x8189, PID 0x0019).
; If it isn't plugged in, AHI shows a message and the script stops.
buttonId := AHI.GetKeyboardId(0x8189, 0x0019)

; Watch the Enter key on the button only. "true" blocks it, so apps
; never see the button's Enter. Your normal keyboard is untouched.
AHI.SubscribeKey(buttonId, GetKeySC("Enter"), true, ButtonEvent)

ButtonEvent(state) {
    static held := false
    if (state = 1) {                 ; 1 = pressed
        if held                      ; ignore key repeat while it's held down
            return
        held := true
        Run("notepad.exe")           ; <-- run a program...
        ; Send("^+m")                ; <-- ...or send a shortcut (Ctrl+Shift+M)
    } else {                         ; 0 = released
        held := false
    }
}

; Press Ctrl+Esc on your normal keyboard to quit the script
^Esc::
{
    ExitApp
}
```

- To **run a program**, change `Run("notepad.exe")` to your program, for example `Run("C:\Program Files\My App\app.exe")`. AutoHotkey paths use single backslashes.
- To **send a shortcut**, put `;` at the start of the `Run(...)` line and remove the `;` from the `Send(...)` line. In AutoHotkey, `^` is Ctrl, `+` is Shift, `!` is Alt and `#` is the Windows key, so `Send("^+m")` sends Ctrl+Shift+M.
- If you unplug the button and plug it back in, its ID changes. Run the script again by double-clicking it. `#SingleInstance Force` replaces the old copy.

#### Step 6: start it automatically

AutoHotkey's FAQ recommends a shortcut in the Startup folder:

1. Click `BigRedButton.ahk` and press **Ctrl+C**.
2. Press **Win+R**, type `shell:startup` and press Enter.
3. Right-click in the folder and choose **Paste shortcut**.

---

## 4. Dedicated quiz or kiosk PC

If the PC is only used for your quiz, game or kiosk and nobody needs a normal Enter key on it, changing Enter for every keyboard is fine. Then you don't need the extra tools above:

- **Microsoft PowerToys Keyboard Manager:** in PowerToys Settings, open **Keyboard Manager**, choose **Remap a key** and map **Enter** to the key or shortcut you want. PowerToys has to be running for this to work.
- **Plain AutoHotkey v2:** a one-line script makes Enter, on any keyboard, run a program:

  ```autohotkey
  #Requires AutoHotkey v2.0
  Enter::Run("notepad.exe")
  ```

Both of these change the Enter key on **every** keyboard plugged into that PC.

---

## 5. Troubleshooting

**Nothing happens and the button doesn't light up**

- Check that you're using the **supplied USB-A to USB-C cable**. A USB-C to USB-C cable won't power the button.
- On a USB-C-only PC, use a USB-C to USB-A adapter or hub with the supplied cable.
- Try a different USB port.

**Check that Windows sees the button**

1. Right-click the **Start** button and choose **Device Manager**.
2. Expand **Keyboards**.
3. Unplug the button and plug it back in while you watch the list. A **HID Keyboard Device** entry should appear when it's plugged in and disappear when it's unplugged.

**Check that it's the right device (hardware ID)**

1. In Device Manager, right-click the **HID Keyboard Device** and choose **Properties**.
2. Open the **Details** tab.
3. Set **Property** to **Hardware Ids**.
4. The button's IDs contain **`VID_8189&PID_0019`**. If you have more than one HID Keyboard Device, check each one.

**LuaMacros prints "Big Red Button not found"**

- Plug the button in, then run the script again (**Ctrl+Enter**).
- Add `lmc_print_devices()` to the script and run it. Look for a device with `8189` in its ID.

**AutoHotInterception says "Could not get Keyboard with VID ..."**

- The button isn't plugged in, or the Interception driver isn't installed. Did you restart after installing it?
- Run `Monitor.ahk` and check that a keyboard with VID 0x8189 and PID 0x0019 is listed.

**The button stopped working after a lot of unplugging (Option B)**

- That's the Interception device limit described in Option B. Restart the PC.

**An app still gets an Enter from the button (Option A)**

- If that app is running as administrator, LuaMacros can't block keys in it. Use Option B instead.

**Can I reprogram the button itself so it sends a different key?**

- The button's chip has a separate configuration interface, but we don't have the manufacturer's setup software. For now, use one of the PC-side options above.

---

## Why isn't there a Little Bird app for Windows?

On macOS and Linux, our software reads the button directly and silences only its Enter key, using built-in features of the operating system. Windows doesn't offer an equivalent without a driver: ordinary apps can't read a keyboard's raw USB data, and a keyboard hook can't tell which keyboard a key came from. That's why both options above use a helper (a keyboard hook in LuaMacros, a driver in Interception).

---

## Where this information comes from

- LuaMacros source code, samples and download link: <https://github.com/me2d13/luamacros>
- AutoHotInterception README and releases: <https://github.com/evilC/AutoHotInterception>
- Interception driver: <https://github.com/oblitum/Interception>
- AutoHotkey v2 download and FAQ (startup folder): <https://www.autohotkey.com/download/>, <https://www.autohotkey.com/docs/v2/FAQ.htm>
- PowerToys Keyboard Manager (no per-keyboard mappings): <https://learn.microsoft.com/en-us/windows/powertoys/keyboard-manager>
- Finding hardware IDs in Device Manager: <https://learn.microsoft.com/en-us/windows-hardware/drivers/install/hardware-ids>

---

*Note: Little Bird hasn't tested these steps on Windows yet. They're based on each tool's official documentation and source code, checked in October 2026, and on testing the button itself on a Mac. If something doesn't match what you see, please let us know.*
